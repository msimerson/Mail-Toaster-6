#!/bin/sh

set -e

. mail-toaster.sh

export TACHYON_VERSION=${TACHYON_VERSION:-"latest"}

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

mt6-include php
mt6-include nginx

PHP_VER="84"
TACHYON_WWW="/usr/local/www/tachyon"

tachyon_release_url()
{
	local _base="https://github.com/kimusan/Tachyon/releases"

	if [ "$TACHYON_VERSION" = "latest" ]; then
		echo "$_base/latest/download/tachyon-latest.tar.gz"
	else
		echo "$_base/download/v$TACHYON_VERSION/tachyon-$TACHYON_VERSION.tar.gz"
	fi
}

install_tachyon()
{
	install_php "$PHP_VER" "ctype curl dom fileinfo gd iconv intl mbstring pdo_sqlite pecl-APCu pecl-gnupg phar session simplexml sodium tidy xml zip zlib"
	install_nginx
	stage_pkg_install gnupg

	tell_status "installing tachyon $TACHYON_VERSION"
	local _tarball="$STAGE_MNT/tmp/tachyon.tar.gz"
	fetch -o "$_tarball" "$(tachyon_release_url)"
	mkdir -p "$STAGE_MNT$TACHYON_WWW"
	tar -xz --no-same-owner -C "$STAGE_MNT$TACHYON_WWW" -f "$_tarball"
	rm "$_tarball"

	# APP_DATA_FOLDER_PATH points at the persistent /data, the bundled one is unused
	rm -r "$STAGE_MNT$TACHYON_WWW/data"
}

configure_nginx_server()
{
	# shellcheck disable=SC2089
	_NGINX_SERVER='
		server_name  tachyon;
		root   /usr/local/www;

		add_header X-Content-Type-Options "nosniff" always;
		add_header X-Robots-Tag "none" always;
		add_header X-Download-Options "noopen" always;
		add_header X-Permitted-Cross-Domain-Policies "none" always;
		add_header Referrer-Policy "no-referrer" always;
		fastcgi_hide_header X-Powered-By;

		location /tachyon/ {
			index  index.php;
			try_files $uri $uri/ /tachyon/index.php;
		}

		location ~ \.php(/|$) {
			fastcgi_split_path_info ^(.+\.php)(/.*)$;
			try_files $fastcgi_script_name =404;
			fastcgi_keep_conn on;
			include        /usr/local/etc/nginx/fastcgi_params;
			fastcgi_index  index.php;
			fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
			fastcgi_param  PATH_INFO        $fastcgi_path_info;
			fastcgi_param  HTTP_PROXY       "";
			# a first CalDAV/CardDAV sync of a large account runs past 60s
			fastcgi_read_timeout 600;
			fastcgi_pass   php;
		}
'
	# shellcheck disable=SC2090
	export _NGINX_SERVER
	configure_nginx_server_d tachyon
}

set_data_path()
{
	store_config "$STAGE_MNT$TACHYON_WWW/include.php" "overwrite" <<'EO_INCLUDE'
<?php
define('APP_DATA_FOLDER_PATH', '/data/');
EO_INCLUDE
}

# Tachyon upgrades a SnappyMail data dir in place. SALT.php keys the stored
# credentials, so it must travel with _data_.
import_snappymail_data()
{
	local _tachyon_data _snappy_data
	_tachyon_data="$(get_jail_data tachyon)"
	_snappy_data="$(get_jail_data snappymail)"

	if [ -d "$_tachyon_data/_data_" ] || [ ! -d "$_snappy_data/_data_" ]; then
		return
	fi

	tell_status "importing snappymail data"
	cp -Rp "$_snappy_data/_data_" "$_tachyon_data/"
	if [ -f "$_snappy_data/SALT.php" ]; then
		cp -p "$_snappy_data/SALT.php" "$_tachyon_data/"
	fi
}

install_default_json()
{
	store_config "$(get_jail_data tachyon)/_data_/_default_/domains/default.json" <<EO_JSON
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

configure_tachyon()
{
	configure_php tachyon
	configure_nginx tachyon
	configure_nginx_server

	set_data_path
	import_snappymail_data
	install_default_json

	chown -R 80:80 "$(get_jail_data tachyon)/"
}

start_tachyon()
{
	start_php_fpm
	start_nginx
}

test_tachyon()
{
	test_nginx
	test_php_fpm

	tell_status "testing tachyon responds"
	# the first request also runs Tachyon's setup, populating /data
	if ! fetch -q -o - "http://$(get_jail_ip4 stage)/tachyon/" | grep -q 'tachyon/v/'; then
		fatal_err "tachyon did not serve its login page"
	fi
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs tachyon
start_staged_jail tachyon
install_tachyon
configure_tachyon
start_tachyon
test_tachyon
promote_staged_jail tachyon
