#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/sqwebmail \$path/data nullfs rw 0 0\";
		mount += \"$ZFS_DATA_MNT/vpopmail \$path/usr/local/vpopmail nullfs rw 0 0\";"

mt6-include vpopmail

install_authdaemond()
{
	tell_status "building courier-authlib with vpopmail support"
	stage_make_conf security_courier-authlib "
security_courier-authlib_SET=AUTH_VCHKPW
"
	export BATCH=${BATCH:="1"}

	# sunset after 2017-08 (when courier-unicode 2.0 is installed by pkg)
	#stage_port_install devel/courier-unicode || exit

	stage_port_install security/courier-authlib || exit
}

install_sqwebmail_src()
{

	stage_make_conf mail_sqwebmail "
mail_sqwebmail_SET=AUTH_VCHKPW
mail_sqwebmail_UNSET=SENTRENAME
"
	export BATCH=${BATCH:="1"}
	stage_port_install mail/sqwebmail || exit
}

install_sqwebmail()
{
	if [ "$TOASTER_MYSQL" = "1" ]; then
		tell_status "installing mysql client libs (for vpopmail)"
		stage_pkg_install mysql57-client dialog4ports
	fi

	install_qmail
	install_vpopmail_port

	tell_status "installing sqwebmail"
	stage_pkg_install courier-authlib lighttpd maildrop gnupg || exit

	install_authdaemond
	install_sqwebmail_src
}

configure_lighttpd()
{
	stage_sysrc lighttpd_enable=YES

	local _lighttpd="$STAGE_MNT/usr/local/etc/lighttpd/lighttpd.conf"

	if grep -qs data-dist "$_lighttpd"; then
		tell_status "sqwebmail already configured"
		return
	fi

	tell_status "enabling sqwebmail in lighttpd.conf"
	# shellcheck disable=2016
	sed -i .bak \
		-e '/^var.server_root/ s/data/data-dist/' \
		-e '/^server.document-root/ s/data/data-dist/' \
		"$_lighttpd"

	tee -a "$_lighttpd" <<EO_LIGHTTPD
server.modules += ( "mod_cgi", "mod_alias", "mod_extforward" )
alias.url += (
    "/cgi-bin"        => "/usr/local/www/cgi-bin-dist/sqwebmail/",
    "/sqwebmail/"     => "/usr/local/www/data-dist/sqwebmail/",
)
\$HTTP["url"] =~ "^/cgi-bin" {
    cgi.assign = ( "" => "" )
}
extforward.forwarder = (
    "$(get_jail_ip haproxy)"  => "trust",
)
EO_LIGHTTPD

}

configure_authdaemon()
{
	stage_sysrc courier_authdaemond_enable=YES

	tell_status "configuring authdaemond"
	sed -i .bak \
		-e '/^authmodulelist/ s/authuserdb authvchkpw authpam authldap authmysql authpgsql/authvchkpw/' \
		"$STAGE_MNT/usr/local/etc/authlib/authdaemonrc"
}

configure_sqwebmail()
{
	tell_status "configuring sqwebmail"
	stage_sysrc sqwebmaild_enable=YES

	configure_authdaemon

	tee -a "$STAGE_MNT/usr/local/etc/sqwebmail/maildirfilterconfig" <<EO_MFC
MAILDIRFILTER=../.mailfilter
MAILDIR=./Maildir
EO_MFC

}

start_sqwebmail()
{
	tell_status "starting sqwebmaild"
	stage_exec service sqwebmail-sqwebmaild start || exit

	tell_status "starting courier-authdaemond"
	stage_exec service courier-authdaemond start || exit

	tell_status "starting lighttpd"
	stage_exec service lighttpd start || exit
}

test_sqwebmail()
{
	tell_status "testing sqwebmaild"
	if [ ! -S "$STAGE_MNT/var/sqwebmail/sqwebmail.sock" ]; then
		tell_status "sqwebmail socket missing"
		exit
	fi

	tell_status "testing courier-authdaemond"
	if [ ! -S "$STAGE_MNT/var/run/authdaemond/socket" ]; then
		tell_status "courier-authdaemond socket missing"
		exit
	fi

	tell_status "testing lighttpd on port 80"
	stage_listening 80

	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs sqwebmail
start_staged_jail sqwebmail
install_sqwebmail
configure_sqwebmail
configure_lighttpd
start_sqwebmail
test_sqwebmail
promote_staged_jail sqwebmail
