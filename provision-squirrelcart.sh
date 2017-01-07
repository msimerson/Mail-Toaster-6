#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include php
mt6-include nginx

install_squirrelcart()
{
	local _docroot="$STAGE_MNT/usr/local/www"
	if [ ! -d "$_docroot" ]; then
		tell_status "creating /usr/local/www"
		mkdir -p "$_docroot" || exit
	fi

	# find and unzip the newest squirrelcart zip file
	local _zipfile=$(ls -t -1 $ZFS_DATA_MNT/squirrelcart/squirrelcart*.zip | head -n1)
	if [ ! -f "$_zipfile" ]; then
		tell_status "place the latest squirrelcart zip file in $ZFS_DATA_MNT/squirrelcart"
		exit
	fi
	tell_status "found /data/$_zipfile, expanding..."
	sh -c "cd $STAGE_MNT/tmp; unzip $_zipfile" || exit

	local _verdir=$(ls -t -1 "$STAGE_MNT/tmp/" | grep squirrel | head -n1)
	if [ ! -d "$STAGE_MNT/tmp/$_verdir" ]; then
		tell_status "failed to find unzipped squirrelcart"
		exit
	fi
	tell_status "found $_verdir"

	for d in sc_data sc_images
	do
		if [ ! -d "$ZFS_DATA_MNT/squirrelcart/$d" ]; then
			tell_status "moving default $d to /data"
			mv "$STAGE_MNT/tmp/$_verdir/upload/$d" \
				"$ZFS_DATA_MNT/squirrelcart/" || exit
			chown -R 80:80 "$ZFS_DATA_MNT/squirrelcart/$d" || exit
		fi
	done

	mv "$STAGE_MNT/tmp/$_verdir/upload" "$STAGE_MNT/usr/local/www/squirrelcart" || exit
	ln -s /data/sc_images "$STAGE_MNT/usr/local/www/squirrelcart/sc_images"
	install_nginx
	install_php 56 "mysql session curl openssl gd"
}

configure_nginx_server()
{
	if [ -f "$STAGE_MNT/data/etc/nginx-locations.conf" ]; then
		tell_status "preserving /data/etc/nginx-locations.conf"
		return
	fi

	tell_status "saving /data/etc/nginx-locations.conf"
	tee "$STAGE_MNT/data/etc/nginx-locations.conf" <<'EO_SMF_NGINX'

		servername         squirrelcart;

		location ~ ^/cart/(.+\.php)$ {
			alias          /usr/local/www/squirrelcart;
			fastcgi_pass   127.0.0.1:9000;
			fastcgi_index  index.php;
			fastcgi_param  SCRIPT_FILENAME  $document_root/$1;
			include        /usr/local/etc/nginx/fastcgi_params;
		}

		location /cart/ {
			alias /usr/local/www/squirrelcart/;
			index index.php;
			try_files $uri $uri/ =404;
		}

EO_SMF_NGINX
}

configure_squirrelcart()
{
	configure_php squirrelcart
	configure_nginx squirrelcart
	configure_nginx_server

	local _cf="$STAGE_MNT/usr/local/www/squirrelcart/squirrelcart/config.php"
	chown www:www "$_cf" || exit
	sed -i .bak \
		-e "/^\\\$sql_host /      s/= .*/= '172.16.15.4';/" \
		-e "/^\\\$db /            s/= .*/= 'squirrelcart';/" \
		-e "/^\\\$sql_username /  s/= .*/= 'squirrelcart';/" \
		-e "/^\\\$sql_password /  s/= .*/= 'testing';/" \
		-e "/^\\\$sc_data_path /  s/= .*/= '..\/..\/..\/..\/data\/sc_data';/" \
		-e "/^\\\$site_www_root / s/= .*/= 'https:\/\/10.0.1.59\/cart';/" \
		-e "/^\\\$site_secure_root / s/= .*/= 'https:\/\/10.0.1.59\/cart';/" \
		-e "/^\\\$enc_key/        s/= .*/= '$(openssl rand -hex 18)';/" \
		"$_cf" || exit

	rm -r "$STAGE_MNT/usr/local/www/squirrelcart/sc_install" || exit
	stage_sysrc nginx_flags='-c /data/etc/nginx.conf'
}

start_squirrelcart()
{
	start_php_fpm
	start_nginx
}

test_squirrelcart()
{
	test_php_fpm
	test_nginx
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs squirrelcart
start_staged_jail
install_squirrelcart
configure_squirrelcart
start_squirrelcart
test_squirrelcart
promote_staged_jail squirrelcart
