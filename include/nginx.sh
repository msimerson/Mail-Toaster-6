#!/bin/sh

install_nginx()
{
	tell_status "installing nginx"
	stage_pkg_install nginx

	install_nginx_newsyslog

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
	if [ "$TLS_LIBRARY" = "libressl" ]; then
		echo 'DEFAULT_VERSIONS+=ssl=libressl' >> "$STAGE_MNT/etc/make.conf"
	else
		echo 'DEFAULT_VERSIONS+=ssl=openssl' >> "$STAGE_MNT/etc/make.conf"
	fi
	stage_port_install www/nginx || exit 1
}

install_nginx_newsyslog()
{
	tell_status "enabling nginx log file rotation"
	tee "$STAGE_MNT/etc/newsyslog.conf.d/nginx" <<EO_NG_NSL
# rotate nightly (default)
/var/log/nginx-*.log		root:wheel	644	 7     *   @T00   BCGX  /var/run/nginx.pid 30

# rotate when file size reaches 1M
#/var/log/nginx-*.log		root:wheel	644	 7     1024	 *   BCGX  /var/run/nginx.pid 30
EO_NG_NSL

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
		tell_status "preserving $_datadir/etc/nginx.conf"
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
	gzip on;

	keepalive_timeout  65;

	set_real_ip_from haproxy;
	set_real_ip_from haproxy6;
	real_ip_header   proxy_protocol;
	real_ip_recursive on;
	client_max_body_size 25m;

	upstream php {
		server unix:/tmp/php-cgi.socket;
		#server 127.0.0.1:9000;
	}

	server {
		listen       80 proxy_protocol;
		listen  [::]:80 proxy_protocol;
		listen       81 http2 proxy_protocol;
		listen  [::]:81 http2 proxy_protocol;

		# serve all Let's Encrypt requests from /data
		location /.well-known/acme-challenge {
			root /data;
			try_files \$uri =404;
		}

		include      nginx-locations.conf;

		error_page   500 502 503 504  /50x.html;
		location = /50x.html {
			root   /usr/local/www/nginx-dist;
		}
	}
}

EO_NGINX_CONF

	sed -i .bak \
		-e "s/haproxy;/$(get_jail_ip haproxy);/" \
		-e "s/haproxy6;/$(get_jail_ip6 haproxy);/" \
		"$_installed" || exit
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
