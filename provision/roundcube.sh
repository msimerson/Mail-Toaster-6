#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include php
mt6-include nginx
mt6-include mysql

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

install_roundcube()
{
	local _php_modules="ctype curl dom exif fileinfo filter gd iconv intl mbstring pspell session xml zip"

	if [ "$ROUNDCUBE_SQL" = "1" ]; then
		_php_modules="$_php_modules pdo_mysql"
	else
		_php_modules="$_php_modules pdo_sqlite"
	fi

	install_php 80 "$_php_modules" || exit
	install_nginx || exit

	tell_status "installing roundcube"
	case "$ROUNDCUBE_CORE_PLUGINS" in
		*enigma*)	stage_pkg_install gnupg ;;
	esac
	if [ "$ROUNDCUBE_FROM_LOCAL_PORT" = "1" ]; then
		for _port in roundcube $(printf "roundcube-%s " $ROUNDCUBE_EXTENSIONS); do
			cp -a "ports/$_port" "$STAGE_MNT/root/" || exit

			if [ "$_port" = roundcube ]; then
				tell_status "configure $_port port options"
				stage_make_conf roundcube_SET 'mail_roundcube_SET=GD PSPELL SQLITE'
				stage_make_conf roundcube_UNSET 'mail_roundcube_UNSET=DOCS EXAMPLES LDAP NSC MYSQL PGSQL'
			fi

			tell_status "install $_port"
			jexec "$SAFE_NAME" make -C "/root/$_port" showconfig build deinstall install clean BATCH=yes || exit

			rm -fr "$STAGE_MNT/root/$_port"
			pkg -j "$SAFE_NAME" lock "$_port"
		done
	else
		# shellcheck disable=2046
		stage_pkg_install roundcube-php80 $([ -z "$ROUNDCUBE_EXTENSIONS" ] || printf 'roundcube-%s-php80 ' $ROUNDCUBE_EXTENSIONS)
	fi
}

configure_nginx_server()
{
	local _datadir="$ZFS_DATA_MNT/roundcube"
	if [ -f "$_datadir/etc/nginx-server.conf" ]; then
		tell_status "preserving /data/etc/nginx-server.conf"
		return
	fi

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

	tell_status "saving /data/etc/nginx-locations.conf"
	tee "$_datadir/etc/nginx-locations.conf" <<EO_NGINX_LOCALS

	server_name  roundcube;
	root   /usr/local/www/roundcube;
	index  index.php;

	$_add_server
	location /roundcube {
		alias /usr/local/www/roundcube;
	}

	location ~ \\.php\$ {
		include        /usr/local/etc/nginx/fastcgi_params;
		fastcgi_index  index.php;
		fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
		fastcgi_pass   php;
		$_add_location
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

	local _version
	_version="$(pkg -j "$SAFE_NAME" version -qe roundcube-php80)"
	if [ "$(pkg -j "$SAFE_NAME" version -t "$_version" "roundcube-php80-1.6.0,1")" = "<" ]; then
		_imap_host="default_host"
		_smtp_host="smtp_server"
	else
		_imap_host="imap_host"
		_smtp_host="smtp_host"
	fi
	sed -i.bak \
		-e "/'$_imap_host'/  s/localhost/$_dovecot_ip/" \
		-e "/'$_smtp_host'/  s/= '.*'/= 'ssl:\/\/$TOASTER_MSA:465'/" \
		-e "/'smtp_user'/    s/'';/'%u';/" \
		-e "/'smtp_pass'/    s/'';/'%p';/" \
		-e "/'product_name'/ s/'Roundcube Webmail'/$(sed_replacement_quote "$(php_quote "$ROUNDCUBE_PRODUCT_NAME")")/" \
		-e '/^\$config..plugins/,/^];$/d' \
		"$_rcc_conf"

	local _rcc_plugins=""
	[ -z "$ROUNDCUBE_EXTENSIONS$ROUNDCUBE_CORE_PLUGINS" ] || \
		_rcc_plugins="$(printf "'%s', " $ROUNDCUBE_EXTENSIONS $ROUNDCUBE_CORE_PLUGINS | sed 's/, $//')"

	tee -a "$_rcc_conf" <<EO_RC_ADD

\$config['log_driver'] = 'syslog';
\$config['session_lifetime'] = 30;
\$config['enable_installer'] = true;
\$config['mime_types'] = '/usr/local/etc/nginx/mime.types';
\$config['use_https'] = true;
\$config['smtp_conn_options'] = array(
 'ssl'            => array(
   'verify_peer'  => false,
   'verify_peer_name' => false,
   'verify_depth' => 3,
   'cafile'       => '/etc/ssl/cert.pem',
 ),
);
\$config['plugins'] = [$_rcc_plugins];
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

	local _plugins_dir="$STAGE_MNT/usr/local/www/roundcube/plugins"

	for _plugin in $ROUNDCUBE_CORE_PLUGINS $ROUNDCUBE_EXTENSIONS; do case "$_plugin" in
		automatic_addressbook)
			tell_status "configure the $_plugin plugin"
			local _migration_dir="$_plugins_dir/automatic_addressbook/SQL"
			if [ "$ROUNDCUBE_SQL" = "1" ]; then
				mysql_query < "$_migration_dir/mysql.initial.sql" || true
			else
				stage_exec sqlite3 -bail /data/sqlite.db < "$_migration_dir/sqlite.initial.sql" || true
			fi
			;;
		enigma)
			tell_status "configure the $_plugin plugin"
			local _rcc_pgp_homedir="pgp"
			mkdir -p "$ZFS_DATA_MNT/roundcube/$_rcc_pgp_homedir"
			sed -e '/^\$config..enigma_pgp_homedir.. = /'" s,null,'/data/$_rcc_pgp_homedir'," \
				< "$_plugins_dir/enigma/config.inc.php.dist" \
				> "$_plugins_dir/enigma/config.inc.php"
			;;
		markasjunk)
			tell_status "configure the $_plugin plugin"
			sed \
				< "$_plugins_dir/markasjunk/config.inc.php.dist" \
				> "$_plugins_dir/markasjunk/config.inc.php"
			;;
		managesieve)
			tell_status "configure the $_plugin plugin"
			sed -e "/'managesieve_host'/ s/localhost/dovecot/" \
				< "$_plugins_dir/managesieve/config.inc.php.dist" \
				> "$_plugins_dir/managesieve/config.inc.php"
			;;
		newmail_notifier)
			tell_status "configure the $_plugin plugin"
			sed \
				-e '/^\$config..newmail_notifier_basic.. = / s,false,true,' \
				-e '/^\$config..newmail_notifier_sound.. = / s,false,true,' \
				-e '/^\$config..newmail_notifier_desktop.. = / s,false,true,' \
				< "$_plugins_dir/newmail_notifier/config.inc.php.dist" \
				> "$_plugins_dir/newmail_notifier/config.inc.php"
			;;
	esac; done

	tell_status "apply roundcube customizations to php.ini"
	sed -i.bak \
		-e "/^session.gc_maxlifetime/ s/= *[1-9][0-9]*/= 21600/" \
		-e "/^post_max_size/ s/= *[1-9][0-9]*M/= ${ROUNDCUBE_ATTACHMENT_SIZE_MB}M/" \
		-e "/^upload_max_filesize/ s/= *[1-9][0-9]*M/= ${ROUNDCUBE_ATTACHMENT_SIZE_MB}M/" \
		"$STAGE_MNT/usr/local/etc/php.ini"
}

fixup_url()
{
	# nasty hack for roundcube 1.6.0 bug
	# see https://github.com/roundcube/roundcubemail/issues/8738, #8170, #8770
	sed -i.bak \
		-e "/return \$prefix/    s/\./\. 'roundcube\/' \./" \
		"$STAGE_MNT/usr/local/www/roundcube/program/include/rcmail.php"
}

start_roundcube()
{
	fixup_url
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
