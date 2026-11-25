#!/bin/sh

# nginx and PHP-FPM for many sites, site state in /data: docs/php-sites.md

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

mt6-include php
mt6-include nginx

PHP_VER="85"
PHP_MODULES="bcmath bz2 composer ctype curl dom exif fileinfo filter ftp gd gettext iconv intl mbstring mysqli pdo pdo_mysql pdo_sqlite pecl-APCu xmlrpc phar posix session simplexml soap sockets sqlite3 sysvmsg sysvsem tidy tokenizer xml xmlreader xmlwriter xsl zip zlib"

install_php_jail()
{
	install_nginx
	install_php "$PHP_VER" "$PHP_MODULES"
}

configure_php_jail_dirs()
{
	local _data; _data="$(get_jail_data php)"

	local _d
	for _d in etc/nginx/server.d etc/php-fpm.d etc/newsyslog.conf.d www log; do
		mkdir -p "$_data/$_d" || exit 1
	done
}

configure_php_jail_pools()
{
	local _fpmconf="$STAGE_MNT/usr/local/etc/php-fpm.conf"

	if grep -q '^include=/data/etc/php-fpm.d/' "$_fpmconf"; then
		return
	fi

	tell_status "loading the PHP-FPM pools in /data/etc/php-fpm.d"
	printf '\n; per-site pools, kept in /data\ninclude=/data/etc/php-fpm.d/*.conf\n' >> "$_fpmconf"
}

configure_php_jail_fastcgi()
{
	local _etc; _etc="$(get_jail_data php)/etc/nginx"

	# A map is only valid in the http context, which server.d is included in.
	store_config "$_etc/server.d/00-fastcgi-https.conf" "update" <<'EO_FCGI_MAP'
# haproxy terminates TLS and talks plain HTTP to nginx. Tell PHP the client
# used HTTPS, or $_SERVER['HTTPS'] stays empty and sites build http:// URLs.
map $http_x_forwarded_proto $fastcgi_https {
	default  "";
	https    on;
}
EO_FCGI_MAP

	store_config "$_etc/fastcgi_site.conf" "update" <<'EO_FCGI_SITE'
# include this in a vhost's PHP location, before fastcgi_pass
include        /usr/local/etc/nginx/fastcgi_params;
fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
fastcgi_param  HTTPS            $fastcgi_https if_not_empty;
fastcgi_param  HTTP_PROXY       "";
fastcgi_intercept_errors on;
EO_FCGI_SITE
}

# nginx binds port 80 only for a server block: before the first site, and for
# hosts no site serves
configure_nginx_default_server()
{
	_NGINX_SERVER="server {
$(nginx_listen 80 default_server)
		server_name  _;
		return       404;
	}"
	export _NGINX_SERVER
	configure_nginx_server_d php 00-default
}

# <site>.php-error.log has no pattern: PHP writes it as the pool's uid, and a
# newsyslog line names one owner
configure_php_jail_logs()
{
	tell_status "rotating the per-site nginx and PHP-FPM logs"
	stage_enable_newsyslog
	store_config "$STAGE_MNT/etc/newsyslog.conf.d/php-sites.conf" "update" <<'EO_SITES_NSL'
# 600: the slow log holds stack traces
/data/log/*.access.log		root:wheel	644	 7     *   @T00   BCGX  /var/run/nginx.pid 30
/data/log/*.error.log		root:wheel	644	 7     *   @T00   BCGX  /var/run/nginx.pid 30
/data/log/*.fpm-access.log	root:wheel	600	 7     *   @T00   BCGX  /var/run/php-fpm.pid 30
/data/log/*.fpm-slow.log	root:wheel	600	 7     *   @T00   BCGX  /var/run/php-fpm.pid 30

# each site's PHP error log
<include> /data/etc/newsyslog.conf.d/*.conf
EO_SITES_NSL

	store_config "$(get_jail_data php)/etc/newsyslog.conf.d/example.conf.sample" "update" <<'EO_SAMPLE_NSL'
# Copy to <site>.conf. The owner is the pool's uid:gid.
/data/log/example.org.php-error.log	2001:2001	644	 7     *   @T00   BCX  /var/run/php-fpm.pid 30
EO_SAMPLE_NSL
}

configure_php_jail_samples()
{
	local _etc; _etc="$(get_jail_data php)/etc"

	store_config "$_etc/nginx/example.conf.sample" "update" <<'EO_SAMPLE_VHOST'
# A vhost. Copy to server.d/example.org.conf, edit, and reload nginx.
server {
	listen       80;
	#listen      [::]:80;   # when the jail has IPv6
	server_name  example.org www.example.org;

	access_log  /data/log/example.org.access.log;
	error_log   /data/log/example.org.error.log;

	root   /data/www/example.org;
	index  index.php index.html;

	location / {
		try_files $uri $uri/ /index.php?$args;
	}

	location ~ \.php$ {
		include        /data/etc/nginx/fastcgi_site.conf;
		fastcgi_pass   unix:/tmp/php-example.socket;
	}

	location ~ /\.ht {
		deny  all;
	}
}
EO_SAMPLE_VHOST

	store_config "$_etc/php-fpm.d/example.conf.sample" "update" <<'EO_SAMPLE_POOL'
; A pool. Copy to example.conf, edit, and restart php-fpm.
[example]
; a uid:gid per site, numeric: a reprovision rebuilds the jail's /etc/passwd
user = 2001
group = 2001

listen = /tmp/php-example.socket
listen.owner = www
listen.group = www
listen.mode = 0660

pm = ondemand
pm.max_children = 8
pm.process_idle_timeout = 30s

access.log = /data/log/example.org.fpm-access.log
slowlog = /data/log/example.org.fpm-slow.log
request_slowlog_timeout = 10s
php_admin_flag[log_errors] = on
php_admin_value[error_log] = /data/log/example.org.php-error.log

php_admin_value[open_basedir] = /data/www/example.org:/tmp
EO_SAMPLE_POOL
}

configure_php_jail()
{
	configure_php_jail_dirs

	configure_php php
	configure_php_jail_pools

	configure_nginx php
	configure_php_jail_fastcgi
	configure_nginx_default_server
	configure_php_jail_logs
	configure_php_jail_samples
}

start_php_jail()
{
	start_php_fpm
	start_nginx
}

test_php_jail()
{
	test_php_fpm
	test_nginx

	tell_status "testing the nginx and PHP-FPM configuration"
	stage_exec nginx -t -c /data/etc/nginx/nginx.conf || exit 1
	stage_exec php-fpm -t || exit 1

	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs php
start_staged_jail php
install_php_jail
configure_php_jail
start_php_jail
test_php_jail
promote_staged_jail php
