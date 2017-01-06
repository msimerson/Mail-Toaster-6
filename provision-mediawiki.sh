#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include php

install_nginx()
{
	tell_status "installing nginx"
	stage_pkg_install nginx
}

install_mediawiki()
{
	install_php 56 "ctype iconv gd json mbstring mcrypt openssl session xml zlib"
	install_nginx

	stage_pkg_install mediawiki128 xcache
}

configure_mediawiki()
{
	configure_php mediawiki

	local _datadir="$ZFS_DATA_MNT/mediawiki"
	if [ ! -d "$_datadir/etc" ]; then
		mkdir "$_datadir/etc"
	fi

	local _installed="$_datadir/etc/nginx.conf"
	if [ ! -f "$_installed" ]; then
		tell_status "saving /data/etc/nginx.conf"
		tee "$_installed" <<EO_NGINX_CONF
load_module /usr/local/libexec/nginx/ngx_mail_module.so;
load_module /usr/local/libexec/nginx/ngx_stream_module.so;

worker_processes  1;

#error_log  /var/log/nginx/error.log;

events {
    worker_connections  1024;
}

http {
    include       /usr/local/etc/nginx/mime.types;
    default_type  application/octet-stream;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    include         nginx-mediawiki.conf;
}

EO_NGINX_CONF
	fi

	if [ ! -f "$_datadir/etc/nginx-mediawiki.conf" ]; then
		tell_status "saving /data/etc/nginx-mediawiki.conf"
		tee "$_datadir/etc/nginx-mediawiki.conf" <<'EO_WIKI'

server {
        listen       80;
        server_name  mediawiki;

		set_real_ip_from haproxy;
		real_ip_header X-Forwarded-For;
		client_max_body_size 25m;

		location = /wiki {
		    rewrite ^/wiki$ /w/index.php?title=Main_Page;
		}
		location = /wiki/ {
		    rewrite ^/wiki/$ /w/index.php?title=Main_Page;
		}

		location /wiki/ {
		    alias /usr/local/www/mediawiki;
		    index index.php;
		    try_files $uri $uri/ @mw_rewrite;
		}

		location @mw_rewrite {
		    rewrite ^/wiki/$ /w/index.php?title=Main_Page;
		    rewrite ^/wiki/+(.*)$ /w/index.php?title=$1&$args;
		}

		location ~ ^/w/(.+\.php)$ {
		    alias  /usr/local/www/mediawiki/;
		    fastcgi_pass   127.0.0.1:9000;
		    fastcgi_index  index.php;
		    fastcgi_param  SCRIPT_FILENAME  $document_root$1;
		    include        /usr/local/etc/nginx/fastcgi_params;
		}

		location ^~ /(?:w|wiki)/maintenance/ {
		    return 403;
		}

		location ~* ^/w/(.+\.(?:js|css|png|jpg|jpeg|gif|ico))$ {
		    alias  /usr/local/www/mediawiki/;
		    try_files $1 =404;
		    expires max;
		    log_not_found off;
		}

		location ~* ^/(?:w|wiki)/.+\.(js|css|png|jpg|jpeg|gif|ico)$ {
		    try_files $uri /w/index.php;
		    expires max;
		    log_not_found off;
		}

		location = /_.gif {
		    expires max;
		    empty_gif;
		}

		location ^~ ^/(?:wiki|w)/cache/ {
		    deny all;
		}

		location / {
		    try_files $uri $uri/ @rewrite;
		}

		error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   /usr/local/www/nginx-dist;
        }
    }

EO_WIKI

		sed -i .bak \
			-e "s/haproxy/$(get_jail_ip haproxy)/" \
			"$_datadir/etc/nginx-mediawiki.conf"
	fi

	stage_sysrc nginx_flags='-c /data/etc/nginx.conf'

	if [ -f "$ZFS_DATA_MNT/mediawiki/LocalSettings.php" ]; then
		tell_status "installing LocalSettings.php"
		cp "$ZFS_DATA_MNT/mediawiki/LocalSettings.php" \
			"$STAGE_MNT/usr/local/www/mediawiki/" || exit
	else
		tell_status "no LocalSettings.php found in /data"
		echo "Configure mediawiki and then copy LocalSettings.php"
		echo "to /data so it gets installed automatically in the future."
	fi
}

start_mediawiki()
{
	start_php_fpm

	stage_sysrc nginx_enable=YES
	stage_exec service nginx start
}

test_mediawiki()
{
	tell_status "testing httpd"
	stage_listening 80

	test_php_fpm || exit
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs mediawiki
start_staged_jail
install_mediawiki
configure_mediawiki
start_mediawiki
test_mediawiki
promote_staged_jail mediawiki
