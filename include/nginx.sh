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
/var/log/nginx/*.log		root:wheel	644	 7     *   @T00   BCGX  /var/run/nginx.pid 30

# rotate when file size reaches 20M
#/var/log/nginx/*.log		root:wheel	644	 7     20480	 *   BCGX  /var/run/nginx.pid 30
EO_NG_NSL

}

contains() {
	string="$1"
	substring="$2"
	if [ "${string#*"$substring"}" != "$string" ]; then return 0; fi
	return 1
}

configure_nginx_server_d()
{
	# $1 is jail name, $2 is 'server' name, defaults to $1
	local _server_d="$ZFS_DATA_MNT/$1/etc/nginx/server.d"
	if [ ! -d "$_server_d" ]; then mkdir -p "$_server_d" || exit 1; fi

	# shellcheck disable=2155
	local _server_conf="$_server_d/$([ -z "$2" ] && echo "$1" || echo "$2").conf"
	if [ -f "$_server_conf" ]; then
		tell_status "preserving $_server_conf"
		return
	fi

	# most calls get enclosing server block
	local _prefix='	server {
		listen       80 proxy_protocol;
		listen  [::]:80 proxy_protocol;
'
	local _suffix='location ~ /\.ht {
			deny  all;
		}

		error_page   500 502 503 504  /50x.html;
		location = /50x.html {
			root   /usr/local/www/nginx-dist;
		}
	}'

	# for when caller sets custom server block
	if contains "$_NGINX_SERVER" "listen"; then
		_prefix=''
		_suffix=''
	fi

	tell_status "creating $_server_conf"
	tee "$_server_conf" <<EO_NGINX_SERVER_CONF
		$_prefix
		$_NGINX_SERVER
		$_suffix
EO_NGINX_SERVER_CONF
}

configure_nginx()
{
	if [ -z "$1" ]; then
		tell_status "missing jail name!"
		exit 1
	fi

	local _etcdir="$ZFS_DATA_MNT/$1/etc/nginx"
	if [ ! -d "$_etcdir" ]; then mkdir -p "$_etcdir" || exit 1; fi

	stage_sysrc nginx_flags='-c /data/etc/nginx/nginx.conf'

	local _installed="$_etcdir/nginx.conf"
	if [ -f "$_installed" ]; then
		tell_status "preserving $_installed"
		return
	fi

	tell_status "saving $_installed"
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

	set_real_ip_from $(get_jail_ip haproxy);
	set_real_ip_from $(get_jail_ip6 haproxy);
	real_ip_header   proxy_protocol;
	real_ip_recursive on;
	client_max_body_size 25m;

	upstream php {
		server unix:/tmp/php-cgi.socket;
		#server 127.0.0.1:9000;
	}

	include /data/etc/nginx/server.d/*.conf;
}
EO_NGINX_CONF
}

start_nginx()
{
	tell_status "starting nginx"
	stage_sysrc nginx_enable=YES
	stage_exec service nginx start || stage_exec service nginx restart
}

test_nginx() {
	tell_status "testing nginx is running"
	stage_test_running nginx

	tell_status "testing nginx is listening"
	stage_listening 80
}
