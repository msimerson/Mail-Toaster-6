#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include php
mt6-include nginx
mt6-include mysql

PHP_VER="81"

mysql_error_warning()
{
    echo; echo "-----------------"
    echo "WARNING: could not connect to MySQL. (Is it password protected?) If"
    echo "this is a new install, manually set up MySQL for roundcube."
    echo "-----------------"; echo
    sleep 5
}

install_roundcube_mysql()
{
	assure_jail mysql

	local _init_db=0
	if ! mysql_db_exists roundcubemail; then
		tell_status "creating roundcube mysql db"
		mysql_create_db roundcubemail || mysql_error_warning

		if mysql_db_exists roundcubemail; then
			_init_db=1
		fi
	fi

	local _active_cfg="$ZFS_JAIL_MNT/roundcube/usr/local/www/roundcube/config/config.inc.php"
	if [ -f "$_active_cfg" ]; then
		local _rcpass
		_rcpass=$(grep '//roundcube:' $_active_cfg | grep ^\$config | cut -f3 -d: | cut -f1 -d@)
		if [ -n "$_rcpass" ] && [ "$_rcpass" != "pass" ]; then
			echo "preserving roundcube password $_rcpass"
		fi
	else
		_rcpass=$(openssl rand -hex 18)
	fi

	local _rcc_dir="$STAGE_MNT/usr/local/www/roundcube/config"
	sed -i.bak \
		-e "s/roundcube:pass@/roundcube:${_rcpass}@/" \
		-e "s/@localhost\//@$(get_jail_ip mysql)\//" \
		"$_rcc_dir/config.inc.php" || exit

	if [ "$_init_db" = "1" ]; then
		tell_status "configuring roundcube mysql permissions"

		for _jail in roundcube stage; do
			for _ip in $(get_jail_ip "$_jail") $(get_jail_ip6 "$_jail");
			do
				echo "GRANT ALL PRIVILEGES ON roundcubemail.* to 'roundcube'@'${_ip}' IDENTIFIED BY '${_rcpass}';" \
					| mysql_query || exit
			done
		done

		roundcube_init_db
	fi
}

roundcube_init_db()
{
	tell_status "initializing roundcube db"
	pkg install -y curl || exit
	start_roundcube
	curl -i --haproxy-protocol -F initdb='Initialize database' -XPOST \
		"http://$(get_jail_ip stage)/installer/index.php?_step=3" || exit
}

install_roundcube_plugins()
{
	local _rc_plugins="contextmenu html5_notifier larry"
	if [ -d "$ZFS_DATA_MNT/spamassassin/etc" ]; then
		_rc_plugins="$_rc_plugins sauserprefs"
	fi

	for _pi in $_rc_plugins; do
		tell_status "installing roundcube plugin $_pi"
		stage_pkg_install roundcube-${_pi}-php${PHP_VER}
	done
}

install_roundcube()
{
	local _php_modules="ctype curl dom exif fileinfo filter gd iconv intl mbstring pspell session xml zip"

	if [ "$ROUNDCUBE_SQL" = "1" ]; then
		_php_modules="$_php_modules pdo_mysql"
	else
		_php_modules="$_php_modules pdo_sqlite"
	fi

	install_php $PHP_VER "$_php_modules" || exit
	install_nginx || exit

	tell_status "installing roundcube"
	stage_pkg_install roundcube-php${PHP_VER} || exit 1

	install_roundcube_plugins
}

configure_nginx_server()
{
	local _add_server="" _add_location=""

	if [ "$TOASTER_USE_TMPFS" = "1" ]; then
		tee -a $STAGE_MNT/etc/rc.local <<'EO_RC_LOCAL'
TEMPDIRS="/tmp/nginx/fastcgi_temp /tmp/nginx/client_body_temp"
mkdir -p $TEMPDIRS
chown www:www $TEMPDIRS
chmod 0700 $TEMPDIRS
EO_RC_LOCAL
		stage_exec service local start
		_add_server="client_body_temp_path /tmp/nginx/client_body_temp;"
		_add_location="fastcgi_temp_path /tmp/nginx/fastcgi_temp;"
	fi

	_NGINX_SERVER="
		server_name  roundcube;

		root   /usr/local/www/roundcube;
		index  index.php;

		$_add_server
		location /roundcube {
			alias /usr/local/www/roundcube;
		}

		location ~ ^/(bin|SQL|config|temp|logs)$ {
			deny all;
		}

		location ~ \\.php\$ {
			include        /usr/local/etc/nginx/fastcgi_params;
			fastcgi_index  index.php;
			fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
			fastcgi_pass   php;
			$_add_location
		}

		location ~* \.(?:css|gif|htc|ico|js|jpe?g|png|swf|webp|ttf)$ {
			expires       max;
			access_log    off;
			log_not_found off;
		}
"
	export _NGINX_SERVER
	configure_nginx_server_d roundcube
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
	local _rcc_conf="${STAGE_MNT}${_local_path}"
	if [ -f "$ZFS_JAIL_MNT/roundcube.last/$_local_path" ]; then
		tell_status "preserving $_rcc_conf"
		cp "$ZFS_JAIL_MNT/roundcube.last/$_local_path" "$_rcc_conf" || exit
		return
	fi

	tell_status "installing default $_rcc_conf"
	cp "$_rcc_conf.sample" "$_rcc_conf" || exit

	tell_status "customizing $_rcc_conf"
	local _dovecot_ip
	if  [ -z "$ROUNDCUBE_DEFAULT_HOST" ];
	then
		_dovecot_ip=$(get_jail_ip dovecot)
	else
		_dovecot_ip="$ROUNDCUBE_DEFAULT_HOST"
	fi

	sed -i.bak \
		-e "/'default_host'/ s/'localhost'/'$_dovecot_ip'/" \
		-e "/'smtp_server'/  s/= '.*'/= 'ssl:\/\/$TOASTER_MSA'/" \
		-e "/'smtp_port'/    s/25;/465;/ ; s/587;/465;/" \
		-e "/'imap_host'/    s/localhost/$_dovecot_ip/" \
		-e "/'smtp_host'/    s/localhost:587/= ssl:\/\/$TOASTER_MSA:465/" \
		-e "/'smtp_user'/    s/'';/'%u';/" \
		-e "/'smtp_pass'/    s/'';/'%p';/" \
		-e "/'archive',/     s/,$/, 'managesieve',/" \
		-e "/'product_name'/ s|'Roundcube Webmail'|'$ROUNDCUBE_PRODUCT_NAME'|" \
		"$_rcc_conf" || exit

	tee -a "$_rcc_conf" <<'EO_RC_ADD'

$config['log_driver'] = 'syslog';
$config['session_lifetime'] = 30;
$config['enable_installer'] = true;
$config['mime_types'] = '/usr/local/etc/nginx/mime.types';
$config['use_https'] = true;
$config['smtp_conn_options'] = array(
 'ssl'            => array(
   'verify_peer'  => false,
   'verify_peer_name' => false,
   'verify_depth' => 3,
   'cafile'       => '/etc/ssl/cert.pem',
 ),
);
$config['request_path'] = '/roundcube';
EO_RC_ADD

	if [ "$ROUNDCUBE_SQL" = "1" ]; then
		install_roundcube_mysql
	else
		sed -i.bak \
			-e "/^\$config\['db_dsnw'/ s/= .*/= 'sqlite:\/\/\/\/data\/sqlite.db?mode=0646';/" \
			"$_rcc_conf" || exit

		if [ ! -f "$ZFS_DATA_MNT/roundcube/sqlite.db" ]; then
			mkdir -p "$STAGE_MNT/data"
			chown 80:80 "$STAGE_MNT/data"
			roundcube_init_db
		fi
	fi

	sed -i.bak \
		-e "/enable_installer/ s/true/false/" \
		"$_rcc_conf"

	tell_status "configure the managesieve plugin"
	cp "$STAGE_MNT/usr/local/www/roundcube/plugins/managesieve/config.inc.php.dist" \
		"$STAGE_MNT/usr/local/www/roundcube/plugins/managesieve/config.inc.php"

	sed -i.bak \
		-e "/'managesieve_host'/ s/localhost/dovecot/" \
		"$STAGE_MNT/usr/local/www/roundcube/plugins/managesieve/config.inc.php"

	tell_status "apply roundcube customizations to php.ini"
	sed -i.bak \
		-e "/^session.gc_maxlifetime/ s/= *[1-9][0-9]*/= 21600/" \
		-e "/^post_max_size/ s/= *[1-9][0-9]*M/= ${ROUNDCUBE_ATTACHMENT_SIZE_MB}M/" \
		-e "/^upload_max_filesize/ s/= *[1-9][0-9]*M/= ${ROUNDCUBE_ATTACHMENT_SIZE_MB}M/" \
		"$STAGE_MNT/usr/local/etc/php.ini" || exit
}

fixup_url()
{
	# hack for roundcube 1.6.0 bug
	# see https://github.com/roundcube/roundcubemail/issues/8738, #8170, #8770
	sed -i.bak \
		-e "/return \$prefix/    s/\./\. 'roundcube\/' \./" \
		"$STAGE_MNT/usr/local/www/roundcube/program/include/rcmail.php"
}

start_roundcube()
{
	# fixup_url
	start_php_fpm
	start_nginx
}

test_roundcube()
{
	test_php_fpm
	test_nginx
	echo "it worked"
}

tell_settings ROUNDCUBE
base_snapshot_exists || exit
create_staged_fs roundcube
start_staged_jail roundcube
install_roundcube
configure_roundcube
start_roundcube
test_roundcube
promote_staged_jail roundcube
