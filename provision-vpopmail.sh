#!/bin/sh

. mail-toaster.sh || exit

export VPOPMAIL_OPTIONS_SET="CLEAR_PASSWD"
export VPOPMAIL_OPTIONS_UNSET="ROAMING"
#export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/vpopmail \$path/usr/local/vpopmail nullfs rw 0 0\";"

install_qmail()
{
	tell_status "setting up data fs for qmail control files"
	mkdir -p "$STAGE_MNT/var/qmail" \
	         "$ZFS_DATA_MNT/vpopmail/qmail-control" \
	         "$ZFS_DATA_MNT/vpopmail/qmail-users"

	stage_exec ln -s /usr/local/vpopmail/qmail-control /var/qmail/control
	stage_exec ln -s /usr/local/vpopmail/qmail-users /var/qmail/users

	tell_status "installing qmail"
	mkdir -p "$STAGE_MNT/usr/local/etc/rc.d"
	echo "$TOASTER_HOSTNAME" > "$ZFS_DATA_MNT/vpopmail/qmail-control/me"
	stage_pkg_install netqmail daemontools ucspi-tcp || exit

	tell_status "enabling qmail"
	stage_exec /var/qmail/scripts/enable-qmail

	stage_make_conf mail_qmail_ 'mail_qmail_SET=DNS_CNAME DOCS MAILDIRQUOTA_PATCH
mail_qmail_UNSET=RCDLINK
'
	# stage_exec make -C /usr/ports/mail/qmail deinstall install clean
}

install_maildrop()
{
	tell_status "installing maildrop"
	stage_pkg_install maildrop

	tell_status "installing maildrop filter file"
	fetch -o "$STAGE_MNT/etc/mailfilter" http://mail-toaster.com/install/mt6-mailfilter.txt
	chown 89:89 "$STAGE_MNT/etc/mailfilter"
	chmod 600 "$STAGE_MNT/etc/mailfilter"
}

install_lighttpd()
{
	tell_status "installing lighttpd"
	stage_pkg_install lighttpd

	local _conf; _conf="$STAGE_MNT/usr/local/etc/lighttpd/lighttpd.conf"
	sed -i -e 's/server.use-ipv6 = "enable"/server.use-ipv6 = "disable"/' "$_conf"
	sed -i -e 's/^\$SERVER\["socket"\]/#\$SERVER\["socket"\]/' "$_conf"
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
	stage_pkg_install autorespond cracklib ezmlm-idx autoconf automake
	stage_make_conf mail_qmailadmin_ '
mail_qmailadmin_SET=CRACKLIB HELP IDX MODIFY_QUOTA SPAM_DETECTION TRIVIAL_PASSWORD USER_INDEX
mail_qmailadmin_UNSET=CATCHALL IDX_SQL
'
	export WEBDATADIR=www/data CGIBINDIR=www/cgi-bin CGIBINSUBDIR=qmailadmin
	stage_exec make -C /usr/ports/mail/qmailadmin install clean

	install_lighttpd
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
		echo "CREATE DATABASE vpopmail;" | jexec mysql /usr/local/bin/mysql || exit
	fi

	local _last; _last=$(grep -v ^# "$_vpe" | head -n1 | cut -f4 -d'|')
	if [ "$_last" != "secret" ]; then
		echo "preserving password $_last"
		return
	fi

	local _vpass; _vpass=$(openssl rand -hex 18)

	sed -i -e "s/localhost/$JAIL_NET_PREFIX.4/" "$_vpe"
	sed -i -e 's/root/vpopmail/' "$_vpe"
	sed -i -e "s/secret/$_vpass/" "$_vpe"

	local _vpopmail_ip; _vpopmail_ip=$(get_jail_ip vpopmail)
	echo "GRANT ALL PRIVILEGES ON vpopmail.* to 'vpopmail'@'${_vpopmail_ip}' IDENTIFIED BY '${_vpass}';" \
 		| jexec mysql /usr/local/bin/mysql || exit

	local _stage_ip; _stage_ip=$(get_jail_ip)
	echo "GRANT ALL PRIVILEGES ON vpopmail.* to 'vpopmail'@'${_stage_ip}' IDENTIFIED BY '${_vpass}';" \
 		| jexec mysql /usr/local/bin/mysql || exit
}

install_vpopmail_port()
{
	if [ "$TOASTER_MYSQL" = "1" ]; then
		tell_status "installing vpopmail mysql dependency"
		stage_pkg_install mysql56-client
		VPOPMAIL_OPTIONS_SET="$VPOPMAIL_OPTIONS_SET MYSQL VALIAS"
		VPOPMAIL_OPTIONS_UNSET="$VPOPMAIL_OPTIONS_UNSET CDB"
	fi

	tell_status "installing vpopmail port with custom options"
	stage_make_conf mail_vpopmail_ "
mail_vpopmail_SET=$VPOPMAIL_OPTIONS_SET
mail_vpopmail_UNSET=$VPOPMAIL_OPTIONS_UNSET
"
	stage_pkg_install gmake gettext dialog4ports fakeroot
	stage_exec make -C /usr/ports/mail/vpopmail deinstall install clean

	if [ "$TOASTER_MYSQL" = "1" ]; then
		install_vpopmail_mysql_grants
	fi
}

install_vpopmail()
{
	install_qmail
	install_maildrop

	# stage_exec pw groupadd -n vpopmail -g 89
	# stage_exec pw useradd -n vpopmail -s /nonexistent -d /usr/local/vpopmail -u 89 -g 89 -m -h-

	tell_status "installing vpopmail package"
	stage_pkg_install vpopmail || exit

	install_vpopmail_port
	install_qmailadmin
}

configure_vpopmail()
{
	tell_status "setting up daemon supervision"
	fetch -o - http://mail-toaster.com/install/mt6-qmail-run.txt | jexec "$SAFE_NAME" sh

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
	sleep 1   # give the daemons a second to start listening
	stage_exec sockstat -l -4 | grep :89 || exit
}

base_snapshot_exists || exit
create_data_fs vpopmail
create_staged_fs vpopmail
stage_sysrc hostname=vpopmail
start_staged_jail
install_vpopmail
configure_vpopmail
start_vpopmail
test_vpopmail
promote_staged_jail vpopmail
