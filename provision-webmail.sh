#!/bin/sh

. mail-toaster.sh || exit

install_php()
{
	stage_pkg_install php56 php56-fileinfo php56-mcrypt php56-exif php56-openssl

	cp $STAGE_MNT/usr/local/etc/php.ini-production $STAGE_MNT/usr/local/etc/php.ini
	sed -i .bak -e 's/^;date.timezone =/date.timezone = America\/Los_Angeles/' $STAGE_MNT/usr/local/etc/php.ini

	stage_sysrc php_fpm_enable=YES
	stage_exec service php-fpm start
}

mysql_db_exists()
{
	local _query="SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='$1';"
	result=`echo $_query | jexec mysql mysql -s -N`
	if [ -z "$result" ]; then
		echo "$1 db does not exist"
		return 1  # db does not exist
	else
		echo "$1 db exists"
		return 0  # db exists
	fi
}

install_roundcube_mysql()
{
	local _init_db=1
	local _rcc_dir="$STAGE_MNT/usr/local/www/roundcube/config"

	local _rcpass=`openssl rand -hex 18`
	local _active_cfg="$ZFS_JAIL_MNT/webmail/usr/local/www/roundcube/config/config.inc.php"
	if [ -f "$_active_cfg" ]; then
		_rcpass=`grep '//roundcube:' $_active_cfg | cut -f3 -d: | cut -f1 -d@`
	fi

	local _grant='GRANT ALL PRIVILEGES ON roundcubemail.* to'
	local _webmail_host="${JAIL_NET_PREFIX}.10"
	local _mysql_cmd="$_grant 'roundcube'@'${_webmail_host}' IDENTIFIED BY '${_rcpass}';"

	if mysql_db_exists roundcubemail; then
		_init_db=0
	else
		_mysql_cmd="create database roundcubemail; $_mysql_cmd"
	fi

	echo $_mysql_cmd | jexec mysql /usr/local/bin/mysql || exit
	sed -i -e "s/roundcube:pass@/roundcube:${_rcpass}@/" $_rcc_dir/config.inc.php

	if [ "$_init_db" = "1" ]; then
		jexec mysql /usr/local/bin/mysql -e \
			"$_grant 'roundcube'@'${STAGE_IP}' IDENTIFIED BY '${_rcpass}';" || exit
	    pkg install -y curl || exit
		curl -i -F initdb='Initialize database' -XPOST http://staged/roundcube/installer/index.php?_step=3
	fi
}

install_roundcube()
{
	stage_pkg_install roundcube

	# for sqlite storage
	mkdir -p $STAGE_MNT/var/db/roundcube
	chown 80:80 $STAGE_MNT/var/db/roundcube

	local _rcc_dir="$STAGE_MNT/usr/local/www/roundcube/config"
	cp $_rcc_dir/config.inc.php.sample $_rcc_dir/config.inc.php || exit

	echo "patching roundcube config"
	fetch -o - http://mail-toaster.com/install/mt6-roundcube-cfg.diff | patch -d $_rcc_dir || exit

	install_roundcube_mysql

	sed -i -e "s/enable_installer'] = true;/enable_installer'] = false;/" $_rcc_dir/config.inc.php
}

install_squirrelmail()
{
	stage_pkg_install squirrelmail squirrelmail-sasql-plugin squirrelmail-quota_usage-plugin || exit

	local _sqpass=`openssl rand -hex 18`
	local _sq_dir="$STAGE_MNT/usr/local/www/squirrelmail/config"

	local _active_cfg="$_sq_dir/config.inc.php"
	if [ -f "$_active_cfg" ]; then
		_sqpass=`grep '//squirrelmail:' $_active_cfg | cut -f3 -d: | cut -f1 -d@`
	fi

	cp $_sq_dir/config_local.php.sample $_sq_dir/config_local.php
	cp $_sq_dir/config_default.php $_sq_dir/config.php
	cp $_sq_dir/../plugins/sasql/sasql_conf.php.dist \
	   $_sq_dir/../plugins/sasql/sasql_conf.php
	cp $_sq_dir/../plugins/quota_usage/config.php.sample \
	   $_sq_dir/../plugins/quota_usage/config.php

	tee -a $_sq_dir/config_local.php <<EO_SQUIRREL
\$domain = 'CHANGE.THIS';
\$smtpServerAddress = '127.0.0.9';
\$smtpPort = 465;
\$smtp_auth_mech = 'login';
\$imapServerAddress = '127.0.0.8';
\$imap_server_type = 'dovecot';
\$use_smtp_tls = true;
\$data_dir = '/var/db/squirrelmail/data';
\$attachment_dir = '/var/db/squirrelmail/attach';
// \$check_referrer = '###DOMAIN###';
\$check_mail_mechanism = 'advanced';
\$prefs_dsn = 'mysql://squirrelmail:${_sqpass}@127.0.0.4/squirrelmail';
\$addrbook_dsn = 'mysql://squirrelmail:${_sqpass}@127.0.0.4/squirrelmail';
EO_SQUIRREL

	# TODO: provide a webmail-data file system that preserves these directories
	# across webmail jail builds. /var/db/squirrelmail/[data|attach] && roundcube
	mkdir -p $STAGE_MNT/var/db/squirrelmail/attach $STAGE_MNT/var/db/squirrelmail/data
	cp $_sq_dir/../data/default_pref $STAGE_MNT/var/db/squirrelmail/data/
	chown -R www:www $STAGE_MNT/var/db/squirrelmail
	chmod 733 $STAGE_MNT/var/db/squirrelmail/attach

	local _webmail_host="${JAIL_NET_PREFIX}.10"

	local _init_db=1
	local _grant='GRANT ALL PRIVILEGES ON squirrelmail.* to'
	local _webmail_host="${JAIL_NET_PREFIX}.10"
	local _mysql_cmd="$_grant 'roundcube'@'${_webmail_host}' IDENTIFIED BY '${_sqpass}';"

	if mysql_db_exists squirrelmail; then
		_init_db=0
	else
		_mysql_cmd="create database squirrelmail; $_mysql_cmd"
	fi

	jexec mysql /usr/local/bin/mysql -e "$_mysql_cmd" || exit

	# if [ "$_init_db" = "1" ]; then
	# 	jexec mysql /usr/local/bin/mysql \
	# 		"$_grant 'squirrelmail'@'${STAGE_IP}' IDENTIFIED BY '${_sqpass}';" || exit
	# fi
}

install_nginx()
{
	stage_pkg_install nginx dialog4ports || exit

	local _nginx_conf="$STAGE_MNT/usr/local/etc/nginx/conf.d"
	mkdir -p $_nginx_conf || exit
	fetch -o $_nginx_conf/mail-toaster.conf http://mail-toaster.com/install/mt6-webmail-nginx.txt

	fetch -o - http://mail-toaster.com/install/mt6-nginx.conf.diff \
		| patch -d $STAGE_MNT/usr/local/etc/nginx

	cat <<EONGINX >> $STAGE_MNT/etc/make.conf
www_nginx_SET=HTTP_REALIP
EONGINX

	mount_nullfs /usr/ports $STAGE_MNT/usr/ports
	stage_exec make -C /usr/ports/www/nginx build deinstall install clean
	umount $STAGE_MNT/usr/ports

	stage_sysrc nginx_enable=YES
	stage_exec service nginx restart
}

install_lighttpd()
{
	stage_pkg_install lighttpd
	mkdir -p $STAGE_MNT/var/spool/lighttpd/sockets
	chown -R www $STAGE_MNT/var/spool/lighttpd/sockets

	local _lighttpd_dir=$STAGE_MNT/usr/local/etc/lighttpd
	local _lighttpd_conf=$_lighttpd_dir/lighttpd.conf

	sed -i .bak -e 's/server.use-ipv6 = "enable"/server.use-ipv6 = "disable"/' $_lighttpd_conf
	sed -i .bak -e 's/^\$SERVER\["socket"\]/#\$SERVER\["socket"\]/' $_lighttpd_conf

	sed -i .bak -e 's/^#include_shell "cat/include_shell "cat/' $_lighttpd_conf
	fetch -o $_lighttpd_dir/vhosts.d/mail-toaster.conf http://mail-toaster.org/etc/mt6-lighttpd.txt
	stage_sysrc lighttpd_enable=YES
	stage_exec service lighttpd start
}

install_webmail()
{
	install_php || exit
	install_roundcube || exit
	install_squirrelmail || exit
	install_nginx || exit
	# install_lighttpd || exit
}

configure_webmail()
{
	mkdir -p $STAGE_MNT/usr/local/www/data
	fetch -o $STAGE_MNT/usr/local/www/data/index.html http://mail-toaster.com/install/mt6-index.txt

	fetch -o $STAGE_MNT/usr/local/etc/mime.types http://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types

	# local _jail_ssl="$STAGE_MNT/etc/ssl"
	# cat $_jail_ssl/private/server.key $_jail_ssl/certs/server.crt > $_jail_ssl/private/server.pem
}

start_webmail()
{
	# stage_sysrc webmail_enable=YES
	# stage_exec service webmail start
}

test_webmail()
{
	echo "testing webmail..."
	stage_exec sockstat -l -4 | grep 80 || exit
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_staged_fs webmail
stage_sysrc hostname=webmail
start_staged_jail
install_webmail
configure_webmail
start_webmail
test_webmail
promote_staged_jail webmail
