#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

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
	local _zipfile
	# shellcheck disable=2012,2086
	_zipfile=$(ls -t -1 $ZFS_DATA_MNT/squirrelcart/squirrelcart*.zip | head -n1)
	if [ ! -f "$_zipfile" ]; then
		tell_status "place the latest squirrelcart zip file in $ZFS_DATA_MNT/squirrelcart"
		exit
	fi
	tell_status "found /data/$_zipfile, expanding..."
	sh -c "cd $STAGE_MNT/tmp; unzip $_zipfile" || exit

	local _verdir
	# shellcheck disable=2010
	_verdir=$(ls -t -1 "$STAGE_MNT/tmp/" | grep squirrel | head -n1)
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
	if [ -d "$STAGE_MNT/usr/local/www/squirrelcart/sc_images" ];
	then
		rm -r "$STAGE_MNT/usr/local/www/squirrelcart/sc_images"
	fi
	ln -s /data/sc_images "$STAGE_MNT/usr/local/www/squirrelcart/sc_images"
	install_nginx || exit
	install_php 73 "mysqli session ctype curl filter hash openssl gd json soap xml" || exit

	if [ -f "$ZFS_JAIL_MNT/usr/local/www/squirrelcart/squirrelcart/themes/sc_custom/images/store_logo.png" ]; then
		tell_status "preserving store logo"
		cp "$ZFS_JAIL_MNT/usr/local/www/squirrelcart/squirrelcart/themes/sc_custom/images/store_logo.png" \
			"$STAGE_MNT/usr/local/www/squirrelcart/squirrelcart/themes/sc_custom/images/store_logo.png"
	fi

	stage_pkg_install postfix || exit
}

configure_nginx_server()
{
	 _NGINX_SERVER='
		server_name         squirrelcart;

		location /cart/ {
			alias /usr/local/www/squirrelcart/;
			index store.php index.php;
			autoindex off;
		}

		location ~ ^/cart/(.+\.php)(/.*)?$ {
			alias          /usr/local/www/squirrelcart;
			fastcgi_pass   php;
			fastcgi_index  index.php;
			fastcgi_param  SCRIPT_FILENAME  $document_root/$1;
			fastcgi_param  PATH_INFO $2;
			include        /usr/local/etc/nginx/fastcgi_params;
		}
'
	export _NGINX_SERVER
	configure_nginx_server_d squirrelcart
}

configure_postfix()
{
	if [ -f "$ZFS_JAIL_MNT/squirrelcart/usr/local/etc/postfix/main.cf" ]; then
		tell_status "preserving postfix/main.cf"
		cp "$ZFS_JAIL_MNT/squirrelcart/usr/local/etc/postfix/main.cf" \
			"$STAGE_MNT/usr/local/etc/postfix/main.cf"
	else
		tell_status "LOOK AT postfix/main.cf"
		sleep 5
	fi
	stage_sysrc postfix_enable=YES
}

configure_squirrelcart_cron()
{
	store_exec "$STAGE_MNT/usr/local/etc/periodic/daily/squirrelcart" <<EO_SQ_CRON
#!/bin/sh
/usr/local/bin/php /usr/local/www/squirrelcart/squirrelcart/cron.php
EO_SQ_CRON
}

configure_squirrelcart()
{
	configure_php squirrelcart

	configure_nginx squirrelcart
	configure_nginx_server

	configure_squirrelcart_cron
	configure_postfix

	local _cf_rel="usr/local/www/squirrelcart/squirrelcart/config.php"
	local _cf_prev="$ZFS_JAIL_MNT/squirrelcart.last/$_cf_rel"
	local _cf_stage="$STAGE_MNT/$_cf_rel"

	if [ -f "$_cf_prev" ]; then
		tell_status "preserving config.php"
		cp "$_cf_prev" "$_cf_stage" || exit
	else
		tell_status "customizing config.php"
		sed -i.bak \
			-e "/^\\\$sql_host /      s/= .*/= '$(get_jail_ip mysql)';/" \
			-e "/^\\\$db /            s/= .*/= 'squirrelcart';/" \
			-e "/^\\\$sql_username /  s/= .*/= 'squirrelcart';/" \
			-e "/^\\\$sql_password /  s/= .*/= 'testing';/" \
			-e "/^\\\$sc_data_path /  s/= .*/= '..\/..\/..\/..\/data\/sc_data';/" \
			-e "/^\\\$site_www_root / s/= .*/= 'https:\/\/www.tnpi.net\/cart';/" \
			-e "/^\\\$site_secure_root / s/= .*/= 'https:\/\/www.tnpi.net\/cart';/" \
			-e "/^\\\$enc_key/        s/= .*/= '$(openssl rand -hex 18)';/" \
			"$_cf_stage" || exit
	fi

	chown www:www "$_cf_stage" || exit

	rm -r "$STAGE_MNT/usr/local/www/squirrelcart/sc_install" || exit
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
start_staged_jail squirrelcart
install_squirrelcart
configure_squirrelcart
start_squirrelcart
test_squirrelcart
promote_staged_jail squirrelcart
