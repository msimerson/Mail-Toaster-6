#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/sqwebmail \$path/data nullfs rw 0 0\";
		mount += \"$ZFS_DATA_MNT/vpopmail \$path/usr/local/vpopmail nullfs rw 0 0\";"

install_authdaemond()
{
	tell_status "building courier-authlib with vpopmail support"
	stage_make_conf security_courier-authlib "
security_courier-authlib_SET=AUTH_VCHKPW
"
	export BATCH=${BATCH:="1"}
	stage_exec make -C /usr/ports/security/courier-authlib deinstall install clean || exit
}

install_sqwebmail_src()
{

	stage_make_conf mail_sqwebmail "
mail_sqwebmail_SET=AUTH_VCHKPW
mail_sqwebmail_UNSET=SENTRENAME
"
	export BATCH=${BATCH:="1"}
	stage_exec make -C /usr/ports/mail/sqwebmail deinstall install clean || exit
}

install_qmail()
{
	tell_status "linking qmail control and user dirs"
	stage_exec ln -s /usr/local/vpopmail/qmail-control /var/qmail/control
	stage_exec ln -s /usr/local/vpopmail/qmail-users /var/qmail/users

	tell_status "installing qmail"
	mkdir -p "$STAGE_MNT/usr/local/etc/rc.d"
	echo "$TOASTER_HOSTNAME" > "$ZFS_DATA_MNT/vpopmail/qmail-control/me"
	stage_pkg_install netqmail daemontools ucspi-tcp || exit

	stage_make_conf mail_qmail_ 'mail_qmail_SET=DNS_CNAME DOCS MAILDIRQUOTA_PATCH
mail_qmail_UNSET=RCDLINK
'
}

install_vpopmail_port()
{
	if [ "$TOASTER_MYSQL" = "1" ]; then
		tell_status "installing vpopmail mysql dependency"
		stage_pkg_install mysql56-client
	fi

	tell_status "copying vpopmail options from vpopmail jail"
	grep ^mail "$ZFS_JAIL_MNT/vpopmail/etc/make.conf" >> "$STAGE_MNT/etc/make.conf"
	mkdir -p "$STAGE_MNT/var/db/ports/mail_vpopmail" || exit
	cp "$ZFS_JAIL_MNT/vpopmail/var/db/ports/mail_vpopmail/options" \
		"$STAGE_MNT/var/db/ports/mail_vpopmail" || exit

	tell_status "install vpopmail deps"
	stage_pkg_install gmake gettext ucspi-tcp netqmail fakeroot maildrop

	tell_status "installing vpopmail port with custom options"
	stage_exec make -C /usr/ports/mail/vpopmail deinstall install clean

	tell_status "mounting shared vpopmail fs"
	mount_data vpopmail

	tell_status "linking to shared qmail control dirs"
	stage_exec rm -rf /var/qmail/users || exit
	stage_exec ln -s /usr/local/vpopmail/qmail-users /var/qmail/users || exit

	stage_exec rm -rf /var/qmail/control || exit
	stage_exec ln -s /usr/local/vpopmail/qmail-control /var/qmail/control || exit
}

install_sqwebmail()
{
	if [ "$TOASTER_MYSQL" = "1" ]; then
		tell_status "installing mysql client libs (for vpopmail)"
		stage_pkg_install mysql56-client dialog4ports
	fi

	install_qmail
	install_vpopmail_port

	tell_status "installing sqwebmail"
	stage_pkg_install sqwebmail courier-authlib lighttpd || exit

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
	sed -i .bak \
		-e '/^var.server_root/ s/data/data-dist/' \
		-e '/^server.use-ipv6/ s/enable/disable/' \
		-e '/^server.document-root/ s/data/data-dist/' \
		-e '/^$SERVER/ s/$SER/#$SER/' \
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
    "172.16.15.12"  => "trust",
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
