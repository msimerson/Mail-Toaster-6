#!/bin/sh

install_nginx()
{
	tell_status "installing nginx"
	stage_pkg_install nginx

	if [ -z "$1" ]; then
		tell_status "no jail name, skipping options checks"
		return
	fi

	if [ ! -f "$ZFS_JAIL_MNT/$1/var/db/ports/www_nginx/options" ]; then
		return
	fi

	if [ ! -d "$STAGE_MNT/var/db/ports/www_nginx" ]; then
		tell_status "creating /var/db/ports/www_nginx"
		mkdir -p  "$STAGE_MNT/var/db/ports/www_nginx" || exit
	fi

	tell_status "copying www_nginx/options"
	cp "$ZFS_JAIL_MNT/$1/var/db/ports/www_nginx/options" \
		"$STAGE_MNT/var/db/ports/www_nginx/options" || exit

	tell_status "installing nginx port with localized options"
	stage_pkg_install GeoIP dialog4ports gettext
	stage_exec make -C /usr/ports/www/nginx build deinstall install clean
}

configure_nginx()
{
	if [ -z "$1" ]; then
		tell_status "missing jail name!"
		exit 1
	fi

	local _datadir="$ZFS_DATA_MNT/$1"
	if [ ! -d "$_datadir/etc" ]; then mkdir "$_datadir/etc"; fi

	stage_sysrc nginx_flags='-c /data/etc/nginx.conf'

	local _installed="$_datadir/etc/nginx.conf"
	if [ -f "$_installed" ]; then
		tell_status "preserving /data/etc/nginx.conf"
		return
	fi

	tell_status "saving /data/etc/nginx.conf"
	tee "$_installed" <<EO_NGINX_CONF
load_module /usr/local/libexec/nginx/ngx_mail_module.so;
load_module /usr/local/libexec/nginx/ngx_stream_module.so;

worker_processes  1;

events {
	worker_connections  256;
}

http {
	include       /usr/local/etc/nginx/mime.types;
	default_type  application/octet-stream;

	sendfile        on;

	keepalive_timeout  65;

	include         nginx-server.conf;
}

EO_NGINX_CONF
}

start_nginx()
{
	tell_status "starting nginx"
	stage_sysrc nginx_enable=YES
	stage_exec service nginx start || service nginx restart
}

test_nginx() {
	tell_status "testing nginx is running"
	stage_test_running nginx

	tell_status "testing nginx is listening"
	stage_listening 80
}
