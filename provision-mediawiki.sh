#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include 'php'
mt6-include nginx

install_mediawiki()
{
	assure_jail mysql

	install_php 72 "ctype dom fileinfo hash iconv intl gd json mbstring mysqli openssl readline session sockets xml xmlreader zlib"
	install_nginx

	stage_pkg_install dialog4ports mysql57-client
	stage_port_install www/mediawiki131-php72

	mkdir -p "$STAGE_MNT/var/cache/mediawiki"
	chown 80:80 "$STAGE_MNT/var/cache/mediawiki"
}

configure_nginx_server()
{
	local _datadir="$ZFS_DATA_MNT/mediawiki"
	if [ ! -d "$_datadir/etc" ]; then mkdir "$_datadir/etc"; fi

	if [ -f "$_datadir/etc/nginx-locations.conf" ]; then
		tell_status "preserving /data/etc/nginx-locations.conf"
		return
	fi

	tell_status "saving /data/etc/nginx-locations.conf"
	tee "$_datadir/etc/nginx-locations.conf" <<'EO_WIKI'

	server_name  mediawiki;

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
	    include        /usr/local/etc/nginx/fastcgi_params;
	    fastcgi_index  index.php;
	    fastcgi_param  SCRIPT_FILENAME  $document_root$1;
	    fastcgi_pass   php;
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

EO_WIKI

}

configure_mediawiki()
{
	configure_php mediawiki
	configure_nginx mediawiki
	configure_nginx_server

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
	start_nginx
}

test_mediawiki()
{
	test_nginx || exit
	test_php_fpm || exit
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs mediawiki
start_staged_jail mediawiki
install_mediawiki
configure_mediawiki
start_mediawiki
test_mediawiki
promote_staged_jail mediawiki
