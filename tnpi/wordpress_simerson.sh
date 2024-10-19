#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

mt6-include php
mt6-include nginx

install_wordpress()
{
	assure_jail mysql

	install_nginx
	install_php 82 "ctype curl exif fileinfo ftp gd mysqli pecl-imagick session tokenizer xml zip zlib"

	# stage_pkg_install wordpress
	stage_port_install www/wordpress
}

configure_nginx_server()
{
	# shellcheck disable=2089
	_NGINX_SERVER='
		server_name     wordpress;
		index		index.php;
		root		/usr/local/www;

		location = /favicon.ico {
			log_not_found off;
			access_log off;
		}

		location = /robots.txt {
			allow all;
			log_not_found off;
			access_log off;
		}

		location / {
			# include "?$args" so non-default permalinks do not break
			try_files $uri $uri/ /index.php?$args;
		}

		location ~ \.php$ {
			include        /usr/local/etc/nginx/fastcgi_params;
			fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
			fastcgi_intercept_errors on;
			fastcgi_pass php;
		}

		location ~* \.(?:css|gif|htc|ico|js|jpe?g|png|swf)$ {
			expires max;
			log_not_found off;
		}

'
	# shellcheck disable=2090
	export _NGINX_SERVER
	configure_nginx_server_d wordpress
}

configure_wp_config()
{
	local _local_content="$ZFS_DATA_MNT/wordpress/content"
	local _wp_install="$ZFS_JAIL_MNT/wordpress/usr/local/www/wordpress"
	local _wp_stage="$STAGE_MNT/usr/local/www/wordpress"

	if [ -d "$_local_content" ]; then
		tell_status "linking wp-content to $_local_content"
		rm -r "$STAGE_MNT/usr/local/www/wordpress/wp-content"
		stage_exec ln -s /data/content "/usr/local/www/wordpress/wp-content"
	else
		tell_status "copying wp-content to /data"
		mv "$_wp_stage/wp-content" "$_local_content"
		chown -R 80:80 "$_local_content"
	fi

	if [ ! -d "$_local_content/uploads" ]; then
		tell_status "creating $_local_content/uploads"
		mkdir "$_local_content/uploads"
		chown 80:80 "$_local_content/uploads"
	fi

	local _installed_config="$_wp_install/wp-config.php"
	if [ -f "$_installed_config" ]; then
		tell_status "preserving wp-config.php"
		cp "$_installed_config" "$STAGE_MNT/usr/local/www/wordpress/"
		return
	else
		tell_status "post-install configuration will be required"
		sleep 2
	fi

	tell_status "don't forget to add these to wp-config.php!"
	tee /dev/null <<'EO_WP_NGINX'

// define('WP_CONTENT_DIR', '/data/content');
// define('WP_CONTENT_URL', '//www.example.org/wpn/content');

// Proxy settings
if ($_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https') $_SERVER['HTTPS']='on';

if ( isset($_SERVER['HTTP_X_FORWARDED_FOR']) && !empty($_SERVER['HTTP_X_FORWARDED_FOR']) ) {
	$ips = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']);
	$_SERVER['REMOTE_ADDR'] = trim($ips[0]);
} elseif ( isset($_SERVER['HTTP_X_REAL_IP']) && !empty($_SERVER['HTTP_X_REAL_IP']) ) {
	$_SERVER['REMOTE_ADDR'] = $_SERVER['HTTP_X_REAL_IP'];
} elseif ( isset($_SERVER['HTTP_CLIENT_IP']) && !empty($_SERVER['HTTP_CLIENT_IP']) ) {
	$_SERVER['REMOTE_ADDR'] = $_SERVER['HTTP_CLIENT_IP'];
}

define('WP_ALLOW_MULTISITE', true);
define('MULTISITE', true);
define('SUBDOMAIN_INSTALL', true);
define('DOMAIN_CURRENT_SITE', 'example.org');
define('PATH_CURRENT_SITE', '/');
define('SITE_ID_CURRENT_SITE', 1);
define('BLOG_ID_CURRENT_SITE', 1);
EO_WP_NGINX
}

configure_wordpress()
{
	configure_php wordpress
	configure_nginx wordpress

	configure_nginx_server

	configure_wp_config
}

start_wordpress()
{
	start_php_fpm
	start_nginx
}

test_wordpress()
{
	test_php_fpm
	test_nginx
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs wordpress
start_staged_jail wordpress
install_wordpress
configure_wordpress
start_wordpress
test_wordpress
promote_staged_jail wordpress
