#!/bin/sh

. mail-toaster.sh || exit

#export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA='
		mount += "/data/webmail $path/data nullfs rw 0 0";'

install_php()
{
	tell_status "installing PHP deps"
	stage_pkg_install php56 php56-fileinfo php56-mcrypt php56-exif php56-openssl

	cp $STAGE_MNT/usr/local/etc/php.ini-production $STAGE_MNT/usr/local/etc/php.ini
	sed -i .bak -e 's/^;date.timezone =/date.timezone = America\/Los_Angeles/' $STAGE_MNT/usr/local/etc/php.ini

	stage_sysrc php_fpm_enable=YES
	stage_exec service php-fpm start
}

install_roundcube_mysql()
{
	if [ "$TOASTER_MYSQL" != "1" ]; then
		return
	fi

	if ! mysql_db_exists roundcubemail; then
		tell_status "creating roundcube mysql db"
		echo "CREATE DATABASE roundcubemail;" | jexec mysql /usr/local/bin/mysql || exit
	fi

	local _active_cfg="$ZFS_JAIL_MNT/webmail/usr/local/www/roundcube/config/config.inc.php"
	if [ -f "$_active_cfg" ]; then
		local _rcpass=`grep '//roundcube:' $_active_cfg | cut -f3 -d: | cut -f1 -d@`
	fi

	local _rcc_dir="$STAGE_MNT/usr/local/www/roundcube/config"

	if [ -n "$_rcpass" ] && [ "$_rcpass" != "pass" ]; then
		echo "preserving password $_rcpass"
		sed -i -e "s/roundcube:pass@/roundcube:${_rcpass}@/" $_rcc_dir/config.inc.php
		sed -i -e "s/@localhost\//@$JAIL_NET_PREFIX.4\//" $_rcc_dir/config.inc.php
		return
	fi

	# local _mysql_ip=`get_jail_ip mysql`

	tell_status "configuring mysql permissions"
	_rcpass=`openssl rand -hex 18`
	
	local _grant='GRANT ALL PRIVILEGES ON roundcubemail.* to'
	local _webmail_host=`get_jail_ip webmail`
	local _stage_ip=`get_jail_ip stage`

	local _mysql_cmd="$_grant 'roundcube'@'${_webmail_host}' IDENTIFIED BY '${_rcpass}';"

	echo $_mysql_cmd | jexec mysql /usr/local/bin/mysql || exit
	sed -i -e "s/roundcube:pass@/roundcube:${_rcpass}@/" $_rcc_dir/config.inc.php

	if [ "$_init_db" = "1" ]; then
		jexec mysql /usr/local/bin/mysql -e \
			"$_grant 'roundcube'@'${STAGE_IP}' IDENTIFIED BY '${_rcpass}';" || exit
		roundcube_init_db
	fi
}

roundcube_init_db()
{
    pkg install -y curl || exit
	curl -i -F initdb='Initialize database' -XPOST http://staged/roundcube/installer/index.php?_step=3
}

install_roundcube()
{
	stage_pkg_install roundcube

	# for sqlite storage
	mkdir -p $STAGE_MNT/data/roundcube
	chown 80:80 $STAGE_MNT/data/roundcube

	local _rcc_conf="$STAGE_MNT/usr/local/www/roundcube/config/config.inc.php"
	cp $_rcc_conf.sample $_rcc_conf || exit

	local _dovecot_ip=`get_jail_ip dovecot`
	sed -i -e "/'default_host'/ s/'localhost'/'$_dovecot_ip'/" $_rcc_conf

	local _haraka_ip=`get_jail_ip haraka`
	sed -i -e "/'smtp_server'/  s/'';/'$_haraka_ip';/" $_rcc_conf
	sed -i -e "/'smtp_port'/    s/25;/587;/" $_rcc_conf
	sed -i -e "/'smtp_user'/    s/'';/'%u';/" $_rcc_conf
	sed -i -e "/'smtp_pass'/    s/'';/'%p';/" $_rcc_conf

	tee -a $_rcc_conf <<'EO_RC_ADD'

$config['log_driver'] = 'syslog';
$config['session_lifetime'] = 30;
$config['enable_installer'] = true;
$config['mime_types'] = '/usr/local/etc/mime.types';
$config['smtp_conn_options'] = array(
 'ssl'         => array(
   'verify_peer'  => false,
   'verify_peer_name' => false,
 ),
);
EO_RC_ADD

	
	if [ "$TOASTER_MYSQL" = "1" ]; then
		install_roundcube_mysql
	else
		sed -i -e "/^\$config\['db_dsnw'/ s/= .*/= 'sqlite:\/\/\/\/data\/roundcube\/sqlite.db?mode=0646'/" $_rcc_conf
		if [ ! -f "/data/roundcube/sqlite.db" ]; then
			roundcube_init_db
		fi
	fi

	sed -i -e "s/enable_installer'] = true;/enable_installer'] = false;/" $_rcc_conf
}

install_squirrelmail_mysql()
{
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

	if [ "$_init_db" = "1" ]; then
		jexec mysql /usr/local/bin/mysql \
			"$_grant 'squirrelmail'@'${STAGE_IP}' IDENTIFIED BY '${_sqpass}';" || exit
	fi
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
\$smtpServerAddress = '${JAIL_NET_PREFIX}.9';
\$smtpPort = 465;
\$smtp_auth_mech = 'login';
\$imapServerAddress = '${JAIL_NET_PREFIX}.15';
\$imap_server_type = 'dovecot';
\$use_smtp_tls = true;
\$data_dir = '/data/squirrelmail/data';
\$attachment_dir = '/data/squirrelmail/attach';
// \$check_referrer = '###DOMAIN###';
\$check_mail_mechanism = 'advanced';
\$prefs_dsn = 'mysql://squirrelmail:${_sqpass}@${JAIL_NET_PREFIX}.4/squirrelmail';
\$addrbook_dsn = 'mysql://squirrelmail:${_sqpass}@${JAIL_NET_PREFIX}.4/squirrelmail';
EO_SQUIRREL

	mkdir -p $STAGE_MNT/data/squirrelmail/attach $STAGE_MNT/data/squirrelmail/data
	cp $_sq_dir/../data/default_pref $STAGE_MNT/data/squirrelmail/data/
	chown -R www:www $STAGE_MNT/data/squirrelmail
	chmod 733 $STAGE_MNT/data/squirrelmail/attach

	install_squirrelmail_mysql
}

install_nginx()
{
	stage_pkg_install nginx dialog4ports || exit

	local _nginx_conf="$STAGE_MNT/usr/local/etc/nginx/conf.d"
	mkdir -p $_nginx_conf || exit
	fetch -o $_nginx_conf/mail-toaster.conf http://mail-toaster.com/install/mt6-webmail-nginx.txt

	fetch -o - http://mail-toaster.com/install/mt6-nginx.conf.diff \
		| patch -d $STAGE_MNT/usr/local/etc/nginx

	stage_make_conf www_nginx 'www_nginx_SET=HTTP_REALIP'

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

create_data_fs webmail
create_staged_fs webmail
stage_sysrc hostname=webmail
start_staged_jail
install_webmail
configure_webmail
start_webmail
test_webmail
promote_staged_jail webmail
