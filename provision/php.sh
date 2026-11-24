#!/bin/sh

# The PHP jail: nginx and PHP-FPM for many sites (it replaces the php7 jail,
# which only ran PHP-FPM). All site state lives in /data, so a reprovision
# keeps it:
#
#   /data/etc/nginx/server.d/*.conf   vhosts, one file per site
#   /data/etc/nginx/fastcgi_site.conf include from a vhost's PHP location
#   /data/etc/php-fpm.d/*.conf        per-site PHP-FPM pools
#   /data/www/<site>                  docroots
#   /data/log/<site>.*                a site's nginx and PHP-FPM logs
#   /data/etc/newsyslog.conf.d/*.conf the rotation of a site's PHP error log
#
# How to add a site: docs/php-sites.md
#
# nginx listens on port 80 only: haproxy terminates TLS and sends
# X-Forwarded-Proto. Samples of a vhost and a pool are in /data/etc.

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

# PHP-FPM reads the pools in /data in addition to its own php-fpm.d
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

# nginx binds no port until a server block asks for it. Without a site yet,
# and for a Host nobody serves, answer 404.
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

# The default nginx logs, in /data/log, take what no site claims. A site logs
# to files of its own there, which newsyslog rotates by pattern:
#   <site>.access.log, <site>.error.log   nginx, signalled with the nginx pid
#   <site>.fpm-access.log, <site>.fpm-slow.log
#                                         its PHP-FPM pool, root writes them
# The names differ before the suffix, so no pattern catches another's files.
#
# <site>.php-error.log has no pattern. PHP writes it as the pool's user, and
# newsyslog recreates a rotated file as the user the line names, so a pattern
# can name only one. Each site has a line of its own in
# /data/etc/newsyslog.conf.d, which the jail's newsyslog includes.
configure_php_jail_logs()
{
	tell_status "rotating the per-site nginx and PHP-FPM logs"
	stage_enable_newsyslog
	store_config "$STAGE_MNT/etc/newsyslog.conf.d/php-sites.conf" "update" <<'EO_SITES_NSL'
# rotate nightly, G: the name is a shell pattern
/data/log/*.access.log		root:wheel	644	 7     *   @T00   BCGX  /var/run/nginx.pid 30
/data/log/*.error.log		root:wheel	644	 7     *   @T00   BCGX  /var/run/nginx.pid 30
/data/log/*.fpm-access.log	root:wheel	644	 7     *   @T00   BCGX  /var/run/php-fpm.pid 30
/data/log/*.fpm-slow.log	root:wheel	644	 7     *   @T00   BCGX  /var/run/php-fpm.pid 30

# a site's PHP error log, one line per site, owned by its pool's user
<include> /data/etc/newsyslog.conf.d/*.conf
EO_SITES_NSL

	store_config "$(get_jail_data php)/etc/newsyslog.conf.d/example.conf.sample" "update" <<'EO_SAMPLE_NSL'
# Rotate a site's PHP error log. Copy to <site>.conf. PHP writes the file as
# the pool's user, and newsyslog recreates it as the owner:group named here,
# so use the pool's uid:gid (www is 80:80), or PHP cannot write the new file.
/data/log/example.org.php-error.log	80:80	644	 7     *   @T00   BCX  /var/run/php-fpm.pid 30
EO_SAMPLE_NSL
}

configure_php_jail_samples()
{
	local _etc; _etc="$(get_jail_data php)/etc"

	store_config "$_etc/nginx/example.conf.sample" "update" <<'EO_SAMPLE_VHOST'
# A vhost. Copy to server.d/example.org.conf, edit, and reload nginx.
server {
	listen       80;
	server_name  example.org www.example.org;

	# a log of its own, rotated with the others (newsyslog.conf.d/php-sites.conf)
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
user = www
group = www

listen = /tmp/php-example.socket
listen.owner = www
listen.group = www
listen.mode = 0660

pm = ondemand
pm.max_children = 8
pm.process_idle_timeout = 30s

; logs of its own, rotated with the others (newsyslog.conf.d/php-sites.conf)
access.log = /data/log/example.org.fpm-access.log
slowlog = /data/log/example.org.fpm-slow.log
request_slowlog_timeout = 10s
; PHP errors: the file must be the pool's user's, and rotated as that user
; (a line in /data/etc/newsyslog.conf.d, see docs/php-sites.md)
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
