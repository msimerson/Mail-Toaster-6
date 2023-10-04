#!/bin/sh

. mail-toaster.sh || exit

export JAIL_FSTAB="$ZFS_DATA_MNT/geoip/db $ZFS_JAIL_MNT/whmcs/usr/local/share/GeoIP nullfs rw 0 0"

mt6-include php
mt6-include nginx

install_whmcs()
{
	stage_pkg_install sudo libmaxminddb
	install_php 81 "ctype curl filter gd iconv imap mbstring session soap xml zip zlib"
	install_nginx whmcs

	stage_port_install devel/ioncube || exit
}

configure_whmcs_nginx()
{
	_NGINX_SERVER='
		server_name  theartfarm.com www.theartfarm.com;

		if ($request_method !~ ^(GET|HEAD|POST)$ ) {
			return 444;
		}

		if ($http_user_agent ~* LWP::Simple|BBBike|wget|Baiduspider|Jullo) {
			return 403;
		}

		# https://docs.whmcs.com/Nginx_Directory_Access_Restriction
		location ^~ /vendor/ {
			deny all;
			return 403;
		}

		root /data/whmcs/;
		index  index.php;

		location /.well-known {
			alias /data/html/.well-known;
			try_files $uri $uri/ =404;
		}

		location ~ ^/(.+\.php)$ {
			include        /usr/local/etc/nginx/fastcgi_params;
			fastcgi_index  index.php;
			fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
			fastcgi_param  HTTPS On;
			fastcgi_pass   php;
		}

		location / {
			try_files $uri $uri/ =404;
		}

		error_page  404              /404.html;
		location = /404.html {
			root   /data/html/;
		}
'
	export _NGINX_SERVER
	configure_nginx_server_d whmcs
}

configure_whmcs()
{
	configure_php whmcs
	configure_nginx whmcs

	mkdir -p "$STAGE_MNT/vendor/whmcs/whmcs"
	chown -R www:www "$STAGE_MNT/vendor"

	tee -a "$STAGE_MNT/etc/crontab" <<'EO_CRONTAB'
*/5     *       *       *       *       root    /usr/local/bin/php -q /data/secure/crons-7/cron.php
15      9       *       *       0       root    /usr/local/bin/php -q /data/secure/crons-7/domainsync.php
EO_CRONTAB

	configure_whmcs_nginx
}

start_whmcs()
{
	start_php_fpm
	start_nginx
}

test_whmcs()
{
	test_nginx
	test_php_fpm
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs whmcs
mkdir -p "$STAGE_MNT/usr/local/share/GeoIP"
start_staged_jail
install_whmcs
configure_whmcs
start_whmcs
test_whmcs
promote_staged_jail whmcs
