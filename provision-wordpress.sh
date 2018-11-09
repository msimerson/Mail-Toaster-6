#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include php
mt6-include nginx

install_wordpress()
{
	assure_jail mysql

	install_nginx
	install_php 72 "ctype curl ftp gd hash mysqli session tokenizer xml zip zlib"

	stage_pkg_install dialog4ports

	# stage_pkg_install wordpress
	stage_port_install www/wordpress
}

configure_nginx_standalone()
{
	if [ -f "$STAGE_MNT/data/etc/nginx-locations.conf" ]; then
		tell_status "preserving /data/etc/nginx-locations.conf"
		return
	fi

	tee "$STAGE_MNT/data/etc/nginx-locations.conf" <<'EO_WP_NGINX'

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
		# include "?$args" so non-default permalinks don't break
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

EO_WP_NGINX

}

configure_nginx_with_path()
{
	if [ -f "$STAGE_MNT/data/etc/nginx-locations.conf" ]; then
		tell_status "preserving /data/etc/nginx-locations.conf"
		return
	fi

	local _uri_path="$1"
	if [ -z "$_uri_path" ]; then
		tell_status "using /wpn (wordpress network) for WP url path"
		_uri_path="/wpn"
	fi

	tee "$STAGE_MNT/data/etc/nginx-locations.conf" <<'EO_WP_NGINX'

	server_name     wordpress;
	index		index.php;
	root		/usr/local/www/wordpress;

	# all PHP scripts, optionally within /wpn/
	location ~ ^/(?:wpn/)?(?<script>.+\.php)(?<path_info>.*)$ {

		include        /usr/local/etc/nginx/fastcgi_params;
		fastcgi_index  index.php;
		fastcgi_intercept_errors on;

		fastcgi_param SCRIPT_FILENAME $document_root/$script;
		fastcgi_param SCRIPT_NAME $script;
		fastcgi_param PATH_INFO $path_info;

		fastcgi_pass   php;
	}

	# wordpress served with URL path
	location /wpn/ {
		alias          /usr/local/www/wordpress/;

		# say "yes we can" to permalinks
		try_files $uri $uri/ /index.php?q=$uri&$args;
	}

	location ~* \.(?:css|gif|htc|ico|js|jpe?g|png|swf)$ {
		expires max;
		log_not_found off;
	}

EO_WP_NGINX

}

configure_wp_config()
{
	local _local_content="$ZFS_DATA_MNT/wordpress/content"
	local _wp_install="$ZFS_JAIL_MNT/wordpress/usr/local/www/wordpress"
	local _wp_stage="$STAGE_MNT/usr/local/www/wordpress"

	if [ ! -d "$_local_content" ]; then
		tell_status "copying wp-content to /data"
		cp -r "$_wp_stage/wp-content" "$_local_content"
		chown -R 80:80 "$_local_content"
	else
		chown -R 80:80 "$_wp_stage/wp-content"
	fi

	if [ ! -d "$_local_content/uploads" ]; then
		mkdir "$_local_content/uploads"
		chown 80:80 "$_local_content/uploads"
	fi

	local _installed_config="$_wp_install/wp-config.php"
	if [ -f "$_installed_config" ]; then
		tell_status "installing local wp-config.php"
		cp "$_installed_config" "$STAGE_MNT/usr/local/www/wordpress/" || exit
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

	configure_nginx_standalone
	# configure_nginx_with_path /wpn

	configure_wp_config

	stage_sysrc nginx_flags='-c /data/etc/nginx.conf'
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
