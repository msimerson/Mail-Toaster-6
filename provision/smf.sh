#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include php
mt6-include nginx

install_smf()
{
	install_nginx
	install_php 74 "filter gd mysqli pdo_mysql session zlib"

	if [ ! -d "$STAGE_MNT/usr/local/www/smf" ]; then
		mkdir -p "$STAGE_MNT/usr/local/www/smf" || exit
	fi

	fetch -m -o "$STAGE_MNT/data/smf.tar.bz2" \
		http://download.simplemachines.org/index.php/smf_2-0-15_install.tar.bz2 || exit

	stage_exec sh -c 'cd /usr/local/www/smf; bunzip2 -c /data/smf.tar.bz2 | tar -xf -' || exit
	stage_exec sh -c 'cd /usr/local/www/smf; chown www:www attachments avatars cache Packages Packages/installed.list Smileys Themes agreement.txt Settings.php Settings_bak.php' || exit

	stage_pkg_install aspell
}

configure_nginx_server()
{
	if [ -f "$STAGE_MNT/data/etc/nginx-locations.conf" ]; then
		tell_status "preserving /data/etc/nginx-locations.conf"
		return
	fi

	tee "$STAGE_MNT/data/etc/nginx-locations.conf" <<'EO_SMF_NGINX'

	server_name         smf;

	location /forum/images/custom_avatars/ {
		alias /data/custom_avatars/;
		index index.php;
		expires max;
		try_files $uri =404;
	}

	location ~ ^/forum/(.+\.php)(/.*)?$ {
		alias          /usr/local/www/smf;
		include        /usr/local/etc/nginx/fastcgi_params;
		fastcgi_pass   php;
		fastcgi_index  index.php;
		fastcgi_param  SCRIPT_FILENAME  $document_root/$1;
		fastcgi_param  PATH_INFO $2;
	}

	location /forum/ {
		alias /usr/local/www/smf/;
		index index.php;
		try_files $uri $uri/ =404;
	}

EO_SMF_NGINX

}

configure_smf()
{
	configure_php smf
	configure_nginx smf
	configure_nginx_server

	if [ -f "ZFS_DATA_MNT/smf/Settings.php" ]; then
		tell_status "installing localized Settings.php"
		cp "ZFS_DATA_MNT/smf/Settings.php" "$STAGE_MNT/usr/local/www/smf/" || exit
	else
		tell_status "post-install configuration will be required"
		sleep 2
	fi

	stage_sysrc nginx_flags='-c /data/etc/nginx.conf'
}

start_smf()
{
	start_php_fpm
	start_nginx
}

test_smf()
{
	test_php_fpm
	test_nginx
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs smf
start_staged_jail smf
install_smf
configure_smf
start_smf
test_smf
promote_staged_jail smf
