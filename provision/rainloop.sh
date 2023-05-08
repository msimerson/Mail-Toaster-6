#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include php
mt6-include nginx

install_rainloop()
{
	local _php_modules="curl dom iconv pdo_sqlite simplexml xml zlib"

	if [ "$TOASTER_MYSQL" != "1" ]; then
		tell_status "using sqlite DB backend"
		_php_modules="$_php_modules pdo_sqlite"
		stage_make_conf rainloop_SET 'mail_rainloop_SET=SQLITE'
		stage_make_conf rainloop_UNSET 'mail_rainloop_UNSET=MYSQL PGSQL'
	else
		tell_status "using mysql DB backend"
		_php_modules="$_php_modules pdo_mysql"
		stage_make_conf rainloop_SET 'mail_rainloop_SET=MYSQL'
		stage_make_conf rainloop_UNSET 'mail_rainloop_UNSET=SQLITE PGSQL'
	fi

	install_php 80 "$_php_modules" || exit
	install_nginx || exit

	tell_status "installing rainloop"
	#stage_pkg_install rainloop
	stage_port_install mail/rainloop || exit
}

configure_nginx_server()
{
	configure_nginx_server_d rainloop <<'EO_NGINX_SERVER'

	server_name  rainloop;

	location / {
		root   /usr/local/www/rainloop;
		index  index.php;
		try_files $uri $uri/ /index.php?$query_string;
	}

	location ~ \.php$ {
		root           /usr/local/www/rainloop;
		try_files $uri $uri/ /index.php?$query_string;
		fastcgi_split_path_info ^(.+\.php)(.*)$;
		fastcgi_keep_conn on;
		include        /usr/local/etc/nginx/fastcgi_params;
		fastcgi_index  index.php;
		fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
		fastcgi_pass   php;
	}

	location ^~ /data {
		deny all;
	}

EO_NGINX_SERVER

}

install_default_ini()
{
	local _rlconfdir="$ZFS_DATA_MNT/rainloop/_data_/_default_"
	local _dini="$_rlconfdir/domains/default.ini"
	if [ -f "$_dini" ]; then
		tell_status "preserving default.ini"
		return
	fi

	if [ ! -d "$_rlconfdir/domains" ]; then
		tell_status "creating default/domains dir"
		mkdir -p "$_rlconfdir/domains" || exit
	fi

	tell_status "installing domains/default.ini"
	tee -a "$_dini" <<EO_INI
imap_host = "dovecot"
imap_port = 143
imap_secure = "None"
imap_short_login = Off
sieve_use = On
sieve_allow_raw = Off
sieve_host = "$(get_jail_ip dovecot)"
sieve_port = 4190
sieve_secure = "None"
smtp_host = "$TOASTER_MSA"
smtp_port = 465
smtp_secure = "SSL"
smtp_short_login = Off
smtp_auth = On
smtp_php_mail = Off
white_list = ""
EO_INI
}

set_default_path()
{
	local _rl_ver;
	_rl_ver="$(pkg -j stage info rainloop-php80 | grep Version | awk '{ print $3 }' | cut -f1 -d_)"
	local _rl_root="$STAGE_MNT/usr/local/www/rainloop/rainloop/v/$_rl_ver"
	tee -a "$_rl_root/include.php" <<'EO_INCLUDE'

	function __get_custom_data_full_path()
	{
		return '/data/'; // custom data folder path
	}
EO_INCLUDE
}

configure_rainloop()
{
	configure_php rainloop
	configure_nginx rainloop
	configure_nginx_server

	set_default_path
	install_default_ini

	# for persistent data storage
	chown -R 80:80 "$ZFS_DATA_MNT/rainloop/"
}

start_rainloop()
{
	start_php_fpm
	start_nginx
}

test_rainloop()
{
	test_nginx
	test_php_fpm
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs rainloop
start_staged_jail rainloop
install_rainloop
configure_rainloop
start_rainloop
test_rainloop
promote_staged_jail rainloop
