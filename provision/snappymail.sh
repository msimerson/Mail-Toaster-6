#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

mt6-include php
mt6-include nginx

PHP_VER="82"

install_snappymail()
{
	local _php_modules="ctype curl dom fileinfo gd iconv intl mbstring pdo_sqlite pecl-APCu pecl-gnupg pecl-uuid phar session simplexml sodium tidy xml zip zlib"

	if [ "$TOASTER_MYSQL" != "1" ]; then
		tell_status "using sqlite DB backend"
		stage_pkg_install sqlite3
		# _php_modules="$_php_modules pdo_sqlite"
		stage_make_conf snappymail_SET 'mail_snappymail_SET=SQLITE3 GNUPG'
		stage_make_conf snappymail_UNSET 'mail_snappymail_UNSET=MYSQL PGSQL REDIS LDAP'
	else
		tell_status "using mysql DB backend"
		_php_modules="$_php_modules pdo_mysql"
		stage_make_conf snappymail_SET 'mail_snappymail_SET=MYSQL GNUPG'
		stage_make_conf snappymail_UNSET 'mail_snappymail_UNSET=SQLITE3 PGSQL REDIS LDAP'
	fi

	install_php "$PHP_VER" "$_php_modules"
	install_nginx

	if ! stage_exec pkg install -y php82-pecl-xxtea; then
		stage_pkg_install bsddialog gnupg autoconf automake re2c pcre2 pkgconf libxml2
	fi

	tell_status "installing snappymail"
	stage_pkg_install gnupg
	# stage_pkg_install snappymail-php$PHP_VER
	stage_port_install mail/snappymail
}

configure_nginx_server()
{
	# shellcheck disable=SC2089
	_NGINX_SERVER='
		server_name  snappymail;

		add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
		add_header X-Content-Type-Options "nosniff" always;
		add_header X-XSS-Protection "1; mode=block" always;
		add_header X-Robots-Tag "none" always;
		add_header X-Download-Options "noopen" always;
		add_header X-Permitted-Cross-Domain-Policies "none" always;
		add_header Referrer-Policy "no-referrer" always;
		add_header X-Frame-Options "SAMEORIGIN" always;
		fastcgi_hide_header X-Powered-By;

		location /snappymail/ {
			root   /usr/local/www/snappymail;
			index  index.php;
			try_files $uri index.php?$query_string;
		}

		location ~ \.php$ {
			root           /usr/local/www/snappymail;
			try_files $uri $uri/ /index.php?$query_string;
			fastcgi_split_path_info ^(.+\.php)(.*)$;
			fastcgi_keep_conn on;
			include        /usr/local/etc/nginx/fastcgi_params;
			fastcgi_index  index.php;
			fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
			fastcgi_pass   php;
		}

		location ~ /\.ht {
			deny  all;
		}

		location ^~ /data {
			deny all;
		}
'
	# shellcheck disable=SC2090
	export _NGINX_SERVER
	configure_nginx_server_d snappymail
}

install_default_json()
{
	local _rlconfdir="$ZFS_DATA_MNT/snappymail/_data_/_default_"
	if [ ! -d "$_rlconfdir/domains" ]; then
		tell_status "creating default/domains dir"
		mkdir -p "$_rlconfdir/domains"
	fi

	local _djson="$_rlconfdir/domains/default.json"
	store_config "$_djson" "overwrite" <<EO_JSON
{
    "name": "*",
    "IMAP": {
        "host": "dovecot",
        "port": 143,
        "type": 0,
        "timeout": 300,
        "shortLogin": false,
        "sasl": [
            "LOGIN",
            "PLAIN"
        ],
        "ssl": {
            "verify_peer": false,
            "verify_peer_name": false,
            "allow_self_signed": true,
            "SNI_enabled": true,
            "disable_compression": true,
            "security_level": 1
        },
        "disable_list_status": false,
        "disable_metadata": false,
        "disable_move": false,
        "disable_sort": false,
        "disable_thread": false,
        "use_expunge_all_on_delete": false,
        "fast_simple_search": true,
        "force_select": false,
        "message_all_headers": false,
        "message_list_limit": 0,
        "search_filter": ""
    },
    "SMTP": {
        "host": "haraka",
        "port": 465,
        "type": 1,
        "timeout": 60,
        "shortLogin": false,
        "sasl": [
            "SCRAM-SHA3-512",
            "SCRAM-SHA-512",
            "SCRAM-SHA-256",
            "SCRAM-SHA-1",
            "PLAIN",
            "LOGIN"
        ],
        "ssl": {
            "verify_peer": false,
            "verify_peer_name": false,
            "allow_self_signed": true,
            "SNI_enabled": true,
            "disable_compression": true,
            "security_level": 1
        },
        "useAuth": true,
        "setSender": true,
        "usePhpMail": false
    },
    "Sieve": {
        "host": "dovecot",
        "port": 4190,
        "type": 0,
        "timeout": 10,
        "shortLogin": false,
        "sasl": [
            "PLAIN",
            "LOGIN"
        ],
        "ssl": {
            "verify_peer": false,
            "verify_peer_name": false,
            "allow_self_signed": false,
            "SNI_enabled": true,
            "disable_compression": true,
            "security_level": 1
        },
        "enabled": true
    },
    "whiteList": ""
}
EO_JSON
}

set_default_path()
{
	local _rl_root="$STAGE_MNT/usr/local/www/snappymail"
	tee -a "$_rl_root/include.php" <<'EO_INCLUDE'
<?php
define('APP_DATA_FOLDER_PATH', '/data/');
EO_INCLUDE
}

set_application_path()
{
	local _appini="$ZFS_DATA_MNT/snappymail/_data_/_default_/domains/default.json"

	if [ ! -f "$_appini" ]; then
		echo "missing $_appini"
		curl -k "https://haproxy/stage/snappymail/?admin"
		sleep 1
	fi

	if [ ! -f "$_appini" ]; then
		echo; echo "still missing $_appini"
		exit
	fi

	sed -i.bak \
		-e '/^app_path =/ s/""/"\/snappymail"/' \
		"$_appini"
}

configure_admin_password()
{
	_email="postmaster@$TOASTER_MAIL_DOMAIN"
	_pass=$(jexec vpopmail /usr/local/vpopmail/bin/vuserinfo -C "$_email")
	_hash=$(echo "$_pass" | jexec stage /usr/local/bin/php -r 'echo password_hash(stream_get_contents(STDIN), PASSWORD_DEFAULT);')

	if [ -z "$_hash" ]; then
		echo "no hash"
		exit 1
	fi

	echo "hash: $_hash"
	sed -i '' \
		-e "/^admin_login/ s:\".*\":\"$_email\":" \
		-e "/^admin_password/ s:\".*\":\"$_hash\":" \
		"$STAGE_MNT/data/_data_/_default_/configs/application.ini"
}

configure_snappymail()
{
	configure_php snappymail
	configure_nginx snappymail
	configure_nginx_server

	set_default_path
	install_default_json

	# for persistent data storage
	chown -R 80:80 "$ZFS_DATA_MNT/snappymail/"

	#configure_admin_password
}

start_snappymail()
{
	start_php_fpm
	start_nginx

	set_application_path
}

test_snappymail()
{
	test_nginx
	test_php_fpm
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs snappymail
start_staged_jail snappymail
install_snappymail
configure_snappymail
start_snappymail
test_snappymail
promote_staged_jail snappymail
