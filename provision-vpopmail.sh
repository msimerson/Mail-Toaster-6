#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export VPOPMAIL_OPTIONS_SET="CLEAR_PASSWD"
export VPOPMAIL_OPTIONS_UNSET="ROAMING"
export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/vpopmail \$path/usr/local/vpopmail nullfs rw 0 0\";"

mt6-include vpopmail

install_maildrop()
{
	tell_status "installing maildrop"
	stage_pkg_install maildrop

	tell_status "installing maildrop filter file"
	fetch -o "$STAGE_MNT/etc/mailfilter" "$TOASTER_SRC_URL/qmail/filter.txt" || exit

	tell_status "adding legacy mailfilter for MT5 compatibility"
	mkdir -p "$STAGE_MNT/usr/local/etc/mail" || exit
	cp "$STAGE_MNT/etc/mailfilter" "$STAGE_MNT/usr/local/etc/mail/" || exit

	tell_status "setting permissions on mailfilter files"
	chown 89:89 "$STAGE_MNT/etc/mailfilter" "$STAGE_MNT/usr/local/etc/mail/mailfilter" || exit
	chmod 600 "$STAGE_MNT/etc/mailfilter" "$STAGE_MNT/usr/local/etc/mail/mailfilter" || exit
}

install_lighttpd()
{
	tell_status "installing lighttpd"
	stage_pkg_install lighttpd

	local _conf; _conf="$STAGE_MNT/usr/local/etc/lighttpd/lighttpd.conf"
	# shellcheck disable=2016
	sed -i .bak \
		-e '/^server.use-ipv6/ s/enable/disable/' \
		-e 's/^\$SERVER\["socket"\]/#\$SERVER\["socket"\]/' \
		"$_conf"
	cat <<EO_LIGHTTPD >> "$_conf"

server.modules += ( "mod_alias" )

alias.url = ( "/cgi-bin/"     => "/usr/local/www/cgi-bin/",
              "/qmailadmin/"  => "/usr/local/www/data/qmailadmin/",
           )

server.modules += ( "mod_cgi" )
\$HTTP["url"] =~ "^/cgi-bin" {
   cgi.assign = ( "" => "" )
}
EO_LIGHTTPD

	stage_sysrc lighttpd_enable=YES
	stage_exec service lighttpd start
}

install_qmailadmin()
{
	tell_status "installing qmailadmin"
	stage_pkg_install autorespond ezmlm-idx autoconf automake
	stage_make_conf mail_qmailadmin_ '
mail_qmailadmin_SET=HELP IDX MODIFY_QUOTA SPAM_DETECTION TRIVIAL_PASSWORD USER_INDEX
mail_qmailadmin_UNSET=CATCHALL CRACKLIB IDX_SQL
'

	if [ -f "$ZFS_JAIL_MNT/vpopmail/var/db/ports/mail_qmailadmin/options" ]; then
		if [ ! -d "$STAGE_MNT/var/db/ports/mail_qmailadmin" ]; then
			mkdir -p "$STAGE_MNT/var/db/ports/mail_qmailadmin"
		fi
		tell_status "preserving port options"
		cp "$ZFS_JAIL_MNT/vpopmail/var/db/ports/mail_qmailadmin/options" \
			"$STAGE_MNT/var/db/ports/mail_qmailadmin/"
	fi

	export WEBDATADIR=www/data CGIBINDIR=www/cgi-bin CGIBINSUBDIR=qmailadmin SPAM_COMMAND="| /usr/local/bin/maildrop /usr/local/etc/mail/mailfilter"
	stage_exec make -C /usr/ports/mail/qmailadmin install clean

	install_lighttpd
}

mysql_error_warning()
{
	echo; echo "-----------------"
	echo "WARNING: could not connect to MySQL. (Maybe it's password protected?)"
	echo "If this is a new install, you will need to manually set up MySQL for"
	echo "vpopmail use. "
	echo "-----------------"; echo
	sleep 5
}

install_vpopmail_mysql_grants()
{
	tell_status "enabling vpopmail MySQL access"

	local _vpe; _vpe="$STAGE_MNT/usr/local/vpopmail/etc/vpopmail.mysql"
	if [ ! -f "$_vpe" ]; then
		echo "ERR: where is $_vpe?"
		exit
	fi

	if ! mysql_db_exists vpopmail; then
		tell_status "creating vpopmail database"
		echo "CREATE DATABASE vpopmail;" | jexec mysql /usr/local/bin/mysql || mysql_error_warning
	fi

	if ! mysql_db_exists vpopmail; then
		return
	fi

	local _last; _last=$(grep -v ^# "$_vpe" | head -n1 | cut -f4 -d'|')
	if [ "$_last" != "secret" ]; then
		echo "preserving password $_last"
		return
	fi

	local _vpass; _vpass=$(openssl rand -hex 18)

	sed -i .bak \
		-e "s/^localhost/$(get_jail_ip mysql)/" \
		-e 's/root/vpopmail/' \
		-e "s/secret/$_vpass/" \
		"$_vpe" || exit

	local _vpopmail_ip; _vpopmail_ip=$(get_jail_ip vpopmail)
	echo "GRANT ALL PRIVILEGES ON vpopmail.* to 'vpopmail'@'${_vpopmail_ip}' IDENTIFIED BY '${_vpass}';" \
 		| jexec mysql /usr/local/bin/mysql || exit

	local _stage_ip; _stage_ip=$(get_jail_ip)
	echo "GRANT ALL PRIVILEGES ON vpopmail.* to 'vpopmail'@'${_stage_ip}' IDENTIFIED BY '${_vpass}';" \
 		| jexec mysql /usr/local/bin/mysql || exit
}

install_nrpe()
{
	if [ -z "$TOASTER_NRPE" ]; then
		echo "TOASTER_NRPE unset, skipping nrpe plugin"
		return
	fi

	tell_status "install nagios plugins (mailq)"
	stage_pkg_install nagios-plugins
}

install_qqtool()
{
	tell_status "installing qqtool"
	fetch -o "$STAGE_MNT/usr/local/bin/qqtool" "$TOASTER_SRC_URL/qmail/qqtool.pl"
	chmod 755 "$STAGE_MNT/usr/local/bin/qqtool"
}

install_quota_report()
{
	_qr="$STAGE_MNT/usr/local/etc/periodic/daily/toaster-quota-report"

	tell_status "installing quota_report"
	mkdir -p "$STAGE_MNT/usr/local/etc/periodic/daily" || exit
	fetch -o "$_qr" "$TOASTER_SRC_URL/qmail/toaster-quota-report" || exit
	chmod 755 "$_qr" || exit

	sed -i .bak \
		-e "/\$admin/ s/postmaster@example.com/$TOASTER_ADMIN_EMAIL/" \
		-e "/assistance/ s/example.com/$TOASTER_HOSTNAME/" \
		"$_qr"
}

install_vpopmail()
{
	install_qmail
	configure_qmail
	install_maildrop
	install_qqtool
	install_quota_report

	# stage_exec pw groupadd -n vpopmail -g 89
	# stage_exec pw useradd -n vpopmail -s /nonexistent -d /usr/local/vpopmail -u 89 -g 89 -m -h-

	tell_status "installing vpopmail package"
	stage_pkg_install vpopmail || exit

	install_vpopmail_port
	if [ "$TOASTER_MYSQL" = "1" ]; then
		install_vpopmail_mysql_grants
	fi

	install_qmailadmin
	install_nrpe
}

configure_qmail()
{
	tell_status "enabling qmail"
	stage_exec /var/qmail/scripts/enable-qmail

	local _alias="$STAGE_MNT/var/qmail/alias"
	echo "$TOASTER_ADMIN_EMAIL" | tee "$_alias/.qmail-root"
	echo "$TOASTER_ADMIN_EMAIL" | tee "$_alias/.qmail-postmaster"
	echo "$TOASTER_ADMIN_EMAIL" | tee "$_alias/.qmail-mailer-daemon"
}

configure_vpopmail()
{
	tell_status "setting up daemon supervision"
	stage_pkg_install p5-Package-Constants
	fetch -o - "$TOASTER_SRC_URL/qmail/run.sh" | stage_exec sh

	if [ ! -d "$ZFS_DATA_MNT/vpopmail/domains/$TOASTER_MAIL_DOMAIN" ]; then
		tell_status "ATTN: Your postmaster password is..."
		stage_exec /usr/local/vpopmail/bin/vadddomain -r14 "$TOASTER_MAIL_DOMAIN"
	fi
}

start_vpopmail()
{
	true
}

test_vpopmail()
{
	echo "testing vpopmail"
	sleep 1 # give the daemons a second to start listening
	stage_listening 25
	stage_listening 80
	stage_listening 89
	stage_listening 8998

	stage_test_running lighttpd
	#stage_test_running vpopmaild
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs vpopmail
start_staged_jail
install_vpopmail
configure_vpopmail
start_vpopmail
test_vpopmail
promote_staged_jail vpopmail
