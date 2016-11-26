#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
# shellcheck disable=2016
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/joomla \$path/data nullfs rw 0 0\";"

install_php()
{
	tell_status "installing PHP"
	# curl so that Joomla updater works
	stage_pkg_install php56 php56-curl php56-mysql
}

install_nginx()
{
	stage_pkg_install nginx dialog4ports || exit

	export BATCH=${BATCH:="1"}
	stage_make_conf www_nginx 'www_nginx_SET=HTTP_REALIP'
	stage_exec make -C /usr/ports/www/nginx build deinstall install clean
}

install_joomla()
{
	install_php || exit

	tell_status "installing Joomla 3"
	stage_pkg_install joomla3

	install_nginx || exit
}

configure_nginx()
{
	if [ -f "$ZFS_JAIL_MNT/joomla/usr/local/etc/nginx/nginx.conf" ]; then
		tell_status "preserving nginx.conf"
		cp "$ZFS_JAIL_MNT/joomla/usr/local/etc/nginx/nginx.conf" \
			"$STAGE_MNT/usr/local/etc/nginx/nginx.conf"
		return
	fi

	local _nginx_conf="$STAGE_MNT/usr/local/etc/nginx/conf.d"
	mkdir -p "$_nginx_conf" || exit

	tee "$_nginx_conf/joomla.conf" <<EO_NGINX
set_real_ip_from $(get_jail_ip haproxy);
real_ip_header X-Forwarded-For;
client_max_body_size 25m;

location / {
   root   /usr/local/www/joomla3;
   index  index.php;
}

location ~  ^/(.+\.php)\$ {
   fastcgi_pass   127.0.0.1:9000;
   fastcgi_index  index.php;
   fastcgi_param  SCRIPT_FILENAME  \$document_root/\$1/\$2;
   include        fastcgi_params;
}

EO_NGINX

	patch -d "$STAGE_MNT/usr/local/etc/nginx" <<'EO_NGINX_CONF'
--- nginx.conf-dist	2015-11-28 23:21:55.597113000 -0800
+++ nginx.conf	2015-11-28 23:43:25.508039518 -0800
@@ -34,16 +34,13 @@
 
     server {
         listen       80;
-        server_name  localhost;
+        server_name  joomla;
 
         #charset koi8-r;
 
         #access_log  logs/host.access.log  main;
 
-        location / {
-            root   /usr/local/www/nginx;
-            index  index.html index.htm;
-        }
+        include conf.d/joomla.conf;
 
         #error_page  404              /404.html;
 
EO_NGINX_CONF
}

configure_php()
{
	local _php_ini="$STAGE_MNT/usr/local/etc/php.ini"

	if [ -f "$ZFS_JAIL_MNT/joomla/usr/local/etc/php.ini" ]; then
		tell_status "preserving php.ini"
		cp "$ZFS_JAIL_MNT/joomla/usr/local/etc/php.ini" "$_php_ini"
		return
	fi

	cp "$STAGE_MNT/usr/local/etc/php.ini-production" "$_php_ini" || exit
	sed -i .bak \
		-e 's/^;date.timezone =/date.timezone = America\/Los_Angeles/' \
		-e '/^post_max_size/ s/8M/25M/' \
		-e '/^upload_max_filesize/ s/2M/25M/' \
		"$_php_ini"
}

configure_joomla()
{
	configure_nginx
	configure_php

	_htdocs="$STAGE_MNT/usr/local/www/joomla3"

	if [ -f "$ZFS_JAIL_MNT/joomla/usr/local/www/joomla3/configuration.php" ]; then
		echo "preserving joomla3 configuration.php"
		cp "$ZFS_JAIL_MNT/joomla/usr/local/www/joomla3/configuration.php" "$_htdocs/"
		return
	fi

	if [ ! -f "$_htdocs/robots.txt" ]; then
		tell_status "installing robots.txt"
		tee "$_htdocs/robots.txt" <<EO_ROBOTS_TXT
User-agent: *
Disallow: /
EO_ROBOTS_TXT
	fi
}

start_joomla()
{
	tell_status "starting PHP"
	stage_sysrc php_fpm_enable=YES
	stage_exec service php-fpm start

	tell_status "starting nginx"
	stage_sysrc nginx_enable=YES
	stage_exec service nginx start
}

test_joomla()
{
	tell_status "testing joomla"
	stage_listening 80
	echo "httpd is listening"

	stage_listening 9000
	echo "php fpm is listening"
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs joomla
start_staged_jail
install_joomla
configure_joomla
start_joomla
test_joomla
promote_staged_jail joomla
