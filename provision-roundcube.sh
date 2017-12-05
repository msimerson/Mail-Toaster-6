#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
# shellcheck disable=2016
export JAIL_CONF_EXTRA=""

mt6-include 'php'
mt6-include nginx

install_roundcube_mysql()
{
	assure_jail mysql

	local _init_db=0
	if ! mysql_db_exists roundcubemail; then
		tell_status "creating roundcube mysql db"
		echo "CREATE DATABASE roundcubemail;" | jexec mysql /usr/local/bin/mysql || exit
		_init_db=1
	fi

	local _active_cfg="$ZFS_JAIL_MNT/roundcube/usr/local/www/roundcube/config/config.inc.php"
	if [ -f "$_active_cfg" ]; then
		local _rcpass
		# shellcheck disable=2086
		_rcpass=$(grep '//roundcube:' $_active_cfg | grep ^\$config | cut -f3 -d: | cut -f1 -d@)
		if [ -n "$_rcpass" ] && [ "$_rcpass" != "pass" ]; then
			echo "preserving roundcube password $_rcpass"
		fi
	else
		_rcpass=$(openssl rand -hex 18)
	fi

	local _rcc_dir="$STAGE_MNT/usr/local/www/roundcube/config"
	sed -i .bak \
		-e "s/roundcube:pass@/roundcube:${_rcpass}@/" \
		-e "s/@localhost\//@$(get_jail_ip mysql)\//" \
		"$_rcc_dir/config.inc.php" || exit

	if [ "$_init_db" = "1" ]; then
		tell_status "configuring roundcube mysql permissions"

		for _jail in roundcube stage; do
			for _ip in $(get_jail_ip "$_jail") $(get_jail_ip6 "$_jail");
			do
				echo "GRANT ALL PRIVILEGES ON roundcubemail.* to 'roundcube'@'${_ip}' IDENTIFIED BY '${_rcpass}';" \
					| jexec mysql /usr/local/bin/mysql || exit
			done
		done

		roundcube_init_db
	fi
}

roundcube_init_db()
{
	tell_status "initializating roundcube db"
	pkg install -y curl || exit
	start_roundcube
	curl -i -F initdb='Initialize database' -XPOST \
		"http://$(get_jail_ip stage)/installer/index.php?_step=3" || exit
}

install_roundcube()
{
	local _php_modules="fileinfo mcrypt exif openssl"
	if [ "$TOASTER_MYSQL" != "1" ]; then
		tell_status "install php sqlite module"
		_php_modules="$_php_modules pdo_sqlite"
	fi

	install_php 56 "$_php_modules" || exit
	install_nginx || exit

	tell_status "installing roundcube"
	stage_pkg_install roundcube
}

configure_nginx_server()
{
	local _datadir="$ZFS_DATA_MNT/roundcube"
	if [ -f "$_datadir/etc/nginx-server.conf" ]; then
		tell_status "preserving /data/etc/nginx-server.conf"
		return
	fi

	tell_status "saving /data/etc/nginx-locations.conf"
	tee "$_datadir/etc/nginx-locations.conf" <<'EO_NGINX_LOCALS'

	server_name  roundcube;
	root   /usr/local/www/roundcube;
	index  index.php;

	location /roundcube {
		alias /usr/local/www/roundcube;
	}

	location ~ \.php$ {
		include        /usr/local/etc/nginx/fastcgi_params;
		fastcgi_index  index.php;
		fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
		fastcgi_pass   php;
	}

EO_NGINX_LOCALS

}

configure_roundcube()
{
	configure_php roundcube
	configure_nginx roundcube
	configure_nginx_server

	tell_status "installing mime.types"
	fetch -o "$STAGE_MNT/usr/local/etc/mime.types" \
		http://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types

	local _local_path="/usr/local/www/roundcube/config/config.inc.php"
	local _rcc_conf="$STAGE_MNT/$_local_path"
	if [ -f "$ZFS_JAIL_MNT/roundcube.last/$_local_path" ]; then
		tell_status "preserving $_rcc_conf"
		cp "$ZFS_JAIL_MNT/roundcube.last/$_local_path" "$_rcc_conf" || exit
		return
	fi

	tell_status "installing default $_rcc_conf"
	cp "$_rcc_conf.sample" "$_rcc_conf" || exit

	tell_status "customizing $_rcc_conf"
	local _dovecot_ip; _dovecot_ip=$(get_jail_ip dovecot)
	sed -i .bak \
		-e "/'default_host'/ s/'localhost'/'$_dovecot_ip'/" \
		-e "/'smtp_server'/  s/'.*';/'tls:\/\/haraka';/" \
		-e "/'smtp_port'/    s/25;/587;/" \
		-e "/'smtp_user'/    s/'';/'%u';/" \
		-e "/'smtp_pass'/    s/'';/'%p';/" \
		"$_rcc_conf"

	tee -a "$_rcc_conf" <<'EO_RC_ADD'

$config['log_driver'] = 'syslog';
$config['session_lifetime'] = 30;
$config['enable_installer'] = true;
$config['mime_types'] = '/usr/local/etc/mime.types';
$config['smtp_conn_options'] = array(
 'ssl'            => array(
   'verify_peer'  => false,
   'verify_peer_name' => false,
   'verify_depth' => 3,
   'cafile'       => '/etc/ssl/cert.pem',
 ),
);
EO_RC_ADD

	if [ "$ROUNDCUBE_SQL" = "1" ]; then
		install_roundcube_mysql
	else
		sed -i.bak \
			-e "/^\$config\['db_dsnw'/ s/= .*/= 'sqlite:\/\/\/\/data\/sqlite.db?mode=0646';/" \
			"$_rcc_conf"

		if [ ! -f "$ZFS_DATA_MNT/roundcube/sqlite.db" ]; then
			mkdir -p "$STAGE_MNT/data"
			chown 80:80 "$STAGE_MNT/data"
			roundcube_init_db
		fi
	fi

	sed -i.bak \
		-e "/enable_installer/ s/true/false/" \
		"$_rcc_conf"
}

start_roundcube()
{
	start_php_fpm
	start_nginx
}

test_roundcube()
{
	test_php_fpm
	test_nginx
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs roundcube
start_staged_jail roundcube
install_roundcube
configure_roundcube
start_roundcube
test_roundcube
promote_staged_jail roundcube
