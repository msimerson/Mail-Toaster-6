#!/bin/sh

. mail-toaster.sh || exit

export VPOPMAIL_OPTIONS_SET="CLEAR_PASSWD"
export VPOPMAIL_OPTIONS_UNSET="ROAMING"
export JAIL_FSTAB="$ZFS_DATA_MNT/vpopmail/home $ZFS_JAIL_MNT/vpopmail/usr/local/vpopmail nullfs rw 0 0"

mt6-include vpopmail
mt6-include mysql

install_maildrop()
{
	tell_status "installing maildrop"
	# stage_pkg_install maildrop
	stage_pkg_install libidn
	stage_port_install maildrop

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
	cat <<EO_LIGHTTPD >> "$_conf"

server.modules += ( "mod_alias", "mod_auth", "mod_authn_file" )

alias.url = ( "/cgi-bin/"     => "/usr/local/www/cgi-bin/",
              "/qmailadmin/"  => "/usr/local/www/data/qmailadmin/",
           )

server.modules += ( "mod_cgi" )
\$HTTP["url"] =~ "^/cgi-bin" {
   cgi.assign = ( "" => "" )
}

server.modules += ( "mod_extforward" )
extforward.forwarder = (
     "$(get_jail_ip haproxy)"  => "trust",
     "$(get_jail_ip6 haproxy)"  => "trust",
)

auth.backend                   = "htdigest"
auth.backend.htdigest.userfile = "/usr/local/etc/WebUsers"

auth.require   = ( "/cgi-bin/vqadmin" =>
                     (
                         "method"  => "digest",
                         "realm"   => "Admins Only",
                         "require" => "valid-user"
                      ),
                 )

EO_LIGHTTPD

	if grep -q ^var.state_dir "$STAGE_MNT/usr/local/etc/lighttpd/lighttpd.conf"; then
		sed -i.bak -e 's/^var.state_dir.*$/var.state_dir = "\/var\/run\/lighttpd"/' "$STAGE_MNT/usr/local/etc/lighttpd/lighttpd.conf"
	fi

	stage_sysrc lighttpd_enable=YES
	stage_sysrc lighttpd_pidfile="/var/run/lighttpd/lighttpd.pid"
	stage_exec service lighttpd start
}

install_qmailadmin()
{
	tell_status "installing qmailadmin"
	stage_pkg_install autorespond ezmlm-idx autoconf automake help2man portconfig
	stage_make_conf mail_qmailadmin_ '
mail_qmailadmin_SET=HELP IDX MODIFY_QUOTA TRIVIAL_PASSWORD USER_INDEX
mail_qmailadmin_UNSET=CATCHALL CRACKLIB IDX_SQL SPAM_DETECTION SPAM_NEEDS_EMAIL
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

	stage_port_install mail/qmailadmin || exit

	install_lighttpd
}

install_vqadmin()
{
	tell_status "installing vqadmin"
	export WEBDATADIR=www/data CGIBINDIR=www/cgi-bin
	stage_port_install mail/vqadmin || exit
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
		exit 1
	fi

	if ! mysql_db_exists vpopmail; then
		mysql_create_db vpopmail || mysql_error_warning
	fi

	mysql_db_exists vpopmail || return

	local _last; _last=$(grep -v ^# "$_vpe" | head -n1 | cut -f4 -d'|')
	if [ "$_last" != "secret" ]; then
		echo "preserving password $_last"
		return
	fi

	local _vpass; _vpass=$(openssl rand -hex 18)

	# mysql doesn't allow a /24 (default prefix) within a /12 (default mask)
	local _ip="${JAIL_NET_PREFIX}.0/24"

	sed -i.bak \
		-e "s/^localhost/$(get_jail_ip mysql)/" \
		-e 's/root/vpopmail/' \
		-e "s/secret/$_vpass/" \
		"$_vpe" || exit

	tell_status "setting up mysql user vpopmail"
	for _jail in stage vpopmail dovecot sqwebmail; do
		for _ip in $(get_jail_ip "$_jail") $(get_jail_ip6 "$_jail");
		do
			mysql_user_exists vpopmail $_ip \
				|| echo "CREATE USER 'vpopmail'@'$_ip' IDENTIFIED BY '$_vpass'; FLUSH PRIVILEGES;" | mysql_query \
				|| exit 1

			echo "GRANT ALL PRIVILEGES ON vpopmail.* to 'vpopmail'@'$_ip'" | mysql_query || exit
		done
	done
}

install_vpop_nrpe()
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

	sed -i '' \
		-e "/\$admin/ s/postmaster@example.com/$TOASTER_ADMIN_EMAIL/" \
		-e "/assistance/ s/example.com/$TOASTER_HOSTNAME/" \
		-e "s/My Great Company/$TOASTER_ORG_NAME/" \
		"$_qr"
}

install_vpopmail()
{
	install_qmail
	configure_qmail
	install_maildrop
	install_qqtool
	install_quota_report

	local _fbsd_major; _fbsd_major=$(freebsd-version | cut -f1 -d'.')
	if [ "$_fbsd_major" -gt "12" ]; then
		echo "CFLAGS+= -fcommon" >> $STAGE_MNT/etc/make.conf
	fi

	tell_status "installing vpopmail package"
	stage_pkg_install vpopmail || exit

	# install_vpopmail_port
	install_vpopmail_source
	if [ "$TOASTER_MYSQL" = "1" ]; then
		install_vpopmail_mysql_grants
	fi

	install_qmailadmin
	install_vpop_nrpe
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

	if [ ! -d "$STAGE_MNT/usr/local/vpopmail/domains/$TOASTER_MAIL_DOMAIN" ]; then
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
	stage_listening 25 2
	stage_listening 80 1
	stage_listening 89 1
	stage_listening 8998 2

	stage_test_running lighttpd
	#stage_test_running vpopmaild
	echo "it worked"
}

migrate_vpopmail_home()
{
	if [ ! -d "$ZFS_DATA_MNT/vpopmail/domains" ]; then
		# no vpopmail data or data already migrated
		return
	fi

	echo "
	WARNING: vpopmail data migration required. Migration requires that you
	         manually perform the following steps:

	1. stop the running dovecot and vpopmail jails

		   service jail stop dovecot vpopmail

	2. move the vpopmail data into a 'home' subdirectory

           cd /data/vpopmail
           mkdir home
           mv bin doc domains etc include lib qmail-control qmail-users home/

    3. edit /etc/jail.conf per this diff:

# diff -u /etc/jail.conf.bak /etc/jail.conf
--- /etc/jail.conf.bak	2023-09-29 18:18:38.958413000 -0400
+++ /etc/jail.conf	2023-09-29 18:18:46.394384000 -0400
@@ -17,14 +17,15 @@
 vpopmail	{
 		ip4.addr = 172.16.15.8;
 		ip6.addr = lo1|fd7a:e5cd:1fc1:bc2c:dead:beef:cafe:0008;
-		mount += "/data/vpopmail $path/usr/local/vpopmail nullfs rw 0 0";
+		mount += "/data/vpopmail $path/data nullfs rw 0 0";
+		mount += "/data/vpopmail/home $path/usr/local/vpopmail nullfs rw 0 0";
 	}
 
 dovecot	{
 		ip4.addr = 172.16.15.15;
 		ip6.addr = lo1|fd7a:e5cd:1fc1:bc2c:dead:beef:cafe:000f;
 		mount += "/data/dovecot $path/data nullfs rw 0 0";
-		mount += "/data/vpopmail $path/usr/local/vpopmail nullfs rw 0 0";
+		mount += "/data/vpopmail/home $path/usr/local/vpopmail nullfs rw 0 0";
 	}
 
	4. start the dovecot and vpopmail jails

		   service jail start vpopmail dovecot

	"
	exit

	# service jail stop dovecot vpopmail

	# for _d in bin domains include qmail-control doc etc lib qmail-users; do
	# 	echo "mv $ZFS_DATA_MNT/vpopmail/$_d $ZFS_DATA_MNT/vpopmail/home/"
	# 	mv "$ZFS_DATA_MNT/vpopmail/$_d" "$ZFS_DATA_MNT/vpopmail/home/"
	# done

	# if [ ! -d "$ZFS_DATA_MNT/vpopmail/etc" ]; then
	# 	mkdir "$ZFS_DATA_MNT/vpopmail/etc"
	# fi

	# if [ -d "$ZFS_DATA_MNT/vpopmail/home/etc/pf.conf.d" ]; then
	# 	mv "$ZFS_DATA_MNT/vpopmail/home/etc/pf.conf.d" "$ZFS_DATA_MNT/vpopmail/etc/"
	# fi

	# # TODO: patch fstab mounts in /etc/jail.conf
	# service jail stop dovecot vpopmail
}

migrate_vpopmail_home
base_snapshot_exists || exit
create_staged_fs vpopmail

mkdir -p "$STAGE_MNT/usr/local/vpopmail" \
	"$ZFS_DATA_MNT/vpopmail/home" \
	"$ZFS_DATA_MNT/vpopmail/etc"

start_staged_jail vpopmail
install_vpopmail
configure_vpopmail
start_vpopmail
test_vpopmail
promote_staged_jail vpopmail
