#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

mt6-include php
mt6-include nginx

PHP_VER="84"

# Override AFTERLOGIC_URL in mail-toaster.conf to pin a specific version.
# Find releases at https://github.com/afterlogic/webmail-lite-8/releases
AFTERLOGIC_URL="${AFTERLOGIC_URL:="https://afterlogic.org/download/webmail-lite-8"}"

install_afterlogic()
{
	local _php_modules="curl dom fileinfo gd iconv mbstring pdo_sqlite xml zip"

	install_php $PHP_VER "$_php_modules"
	install_nginx

	local _www="$STAGE_MNT/usr/local/www/afterlogic"

	if [ -f "$ZFS_JAIL_MNT/afterlogic/usr/local/www/afterlogic/index.php" ]; then
		tell_status "preserving existing afterlogic installation"
		cp -a "$ZFS_JAIL_MNT/afterlogic/usr/local/www/afterlogic" \
			"$STAGE_MNT/usr/local/www/"
		return
	fi

	tell_status "downloading AfterLogic WebMail Lite 8"
	fetch -o "$STAGE_MNT/tmp/afterlogic.zip" "$AFTERLOGIC_URL"

	tell_status "extracting AfterLogic WebMail Lite 8"
	mkdir -p "$_www"
	bsdtar -xf "$STAGE_MNT/tmp/afterlogic.zip" -C "$_www"
	rm -f "$STAGE_MNT/tmp/afterlogic.zip"

	chown -R 80:80 "$_www"
}

configure_nginx_server()
{
	_NGINX_SERVER='
		server_name  afterlogic;

		root   /usr/local/www/afterlogic;
		index  index.php;

		add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
		add_header X-Content-Type-Options "nosniff" always;
		add_header X-XSS-Protection "1; mode=block" always;
		add_header X-Frame-Options "SAMEORIGIN" always;
		add_header Referrer-Policy "no-referrer" always;

		location / {
			try_files $uri $uri/ /index.php?$query_string;
		}

		location ~ \.php$ {
			include        /usr/local/etc/nginx/fastcgi_params;
			fastcgi_index  index.php;
			fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
			fastcgi_pass   php;
		}

		location ^~ /data {
			deny all;
		}

		location ~* \.(?:css|gif|ico|js|jpe?g|png|svg|webp|woff2?)$ {
			expires       max;
			access_log    off;
			log_not_found off;
		}
'
	export _NGINX_SERVER
	configure_nginx_server_d afterlogic
}

configure_afterlogic_data()
{
	local _data="$ZFS_DATA_MNT/afterlogic"

	for _dir in temp logs cache settings; do
		if [ ! -d "$_data/$_dir" ]; then
			mkdir -p "$_data/$_dir"
		fi
	done

	local _web_data="$STAGE_MNT/usr/local/www/afterlogic/data"
	if [ -d "$_web_data" ] && [ ! -L "$_web_data" ]; then
		tell_status "moving existing data to persistent storage"
		cp -a "$_web_data/." "$_data/"
		rm -rf "$_web_data"
	fi

	stage_exec ln -sf /data /usr/local/www/afterlogic/data

	chown -R 80:80 "$_data"
}

configure_afterlogic()
{
	configure_php afterlogic
	configure_nginx afterlogic
	configure_nginx_server
	configure_afterlogic_data

	tell_status "AfterLogic admin panel: http://afterlogic/adminpanel/"
	echo "  Default login: admin / 12345  (change this immediately)"
	echo "  Configure IMAP server: $(get_jail_ip dovecot):143"
	echo "  Configure SMTP server: $TOASTER_MSA:465"
}

start_afterlogic()
{
	start_php_fpm
	start_nginx
}

test_afterlogic()
{
	test_php_fpm
	test_nginx
	echo "it worked"
}

tell_settings AFTERLOGIC
base_snapshot_exists || exit
create_staged_fs afterlogic
start_staged_jail afterlogic
install_afterlogic
configure_afterlogic
start_afterlogic
test_afterlogic
promote_staged_jail afterlogic
