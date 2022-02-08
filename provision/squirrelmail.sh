#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include php
mt6-include nginx
mt6-include mysql

SQ_DIR="$STAGE_MNT/usr/local/www/squirrelmail"

install_squirrelmail_mysql()
{
	if [ "$TOASTER_MYSQL" != "1" ]; then return; fi
	if [ "$SQUIRREL_SQL" != "1" ]; then return; fi

	if ! mysql_db_exists squirrelmail; then
		tell_status "creating squirrelmail database"
		mysql_create_db squirrelmail || exit
		echo "
CREATE TABLE address (
  owner varchar(128) DEFAULT '' NOT NULL,
  nickname varchar(16) DEFAULT '' NOT NULL,
  firstname varchar(128) DEFAULT '' NOT NULL,
  lastname varchar(128) DEFAULT '' NOT NULL,
  email varchar(128) DEFAULT '' NOT NULL,
  label varchar(255),
  PRIMARY KEY (owner,nickname),
  KEY firstname (firstname,lastname)
);

CREATE TABLE global_abook (
  owner varchar(128) DEFAULT '' NOT NULL,
  nickname varchar(16) DEFAULT '' NOT NULL,
  firstname varchar(128) DEFAULT '' NOT NULL,
  lastname varchar(128) DEFAULT '' NOT NULL,
  email varchar(128) DEFAULT '' NOT NULL,
  label varchar(255),
  PRIMARY KEY (owner,nickname),
  KEY firstname (firstname,lastname)
);

CREATE TABLE userprefs (
  user varchar(128) DEFAULT '' NOT NULL,
  prefkey varchar(64) DEFAULT '' NOT NULL,
  prefval BLOB NOT NULL,
  PRIMARY KEY (user,prefkey)
);" | mysql_query squirrelmail || exit

	fi

	if [ -z "$sqpass" ]; then
		echo "Oops, squirrelmail db password not set"
		exit
	fi

	tee -a "$SQ_DIR/config/config_local.php" <<EO_SQUIRREL_SQL
\$prefs_dsn = 'mysql://squirrelmail:${sqpass}@$(get_jail_ip mysql)/squirrelmail';
\$addrbook_dsn = 'mysql://squirrelmail:${sqpass}@$(get_jail_ip mysql)/squirrelmail';
EO_SQUIRREL_SQL


	for _jail in squirrelmail stage; do
		for _ip in $(get_jail_ip "$_jail") $(get_jail_ip6 "$_jail");
		do
			echo "GRANT ALL PRIVILEGES ON squirrelmail.* to 'squirrelmail'@'${_ip}' IDENTIFIED BY '${sqpass}';" \
				| mysql_query || exit
		done
	done
}

install_squirrelmail()
{
	install_php 74 "fileinfo pecl-mcrypt exif openssl"
	install_nginx || exit

	tell_status "installing squirrelmail"
	stage_pkg_install squirrelmail-php74 \
		squirrelmail-sasql-plugin-php74 \
		squirrelmail-quota_usage-plugin-php74 \
		squirrelmail-abook_import_export-plugin-php74 || exit

	configure_squirrelmail_local

	cp "$SQ_DIR/config/config_default.php" "$SQ_DIR/config/config.php"
	cp "$SQ_DIR/plugins/sasql/sasql_conf.php.dist" \
	   "$SQ_DIR/plugins/sasql/sasql_conf.php"
	cp "$SQ_DIR/plugins/quota_usage/config.php.sample" \
	   "$SQ_DIR/plugins/quota_usage/config.php"

	mkdir -p "$STAGE_MNT/data/attach" "$STAGE_MNT/data/data" "$STAGE_MNT/data/pref"
	cp "$SQ_DIR/data/default_pref" "$STAGE_MNT/data/data/"
	chown -R www:www "$STAGE_MNT/data" "$STAGE_MNT/data/pref"
	chmod 733 "$STAGE_MNT/data/attach"

	install_squirrelmail_mysql
}

configure_nginx_server()
{
	local _datadir="$ZFS_DATA_MNT/squirrelmail"
	local _conf="etc/nginx-locations.conf"
	if [ -f "$_datadir/$_conf" ]; then
		tell_status "preserving /data/$_conf"
		return
	fi

	tell_status "saving /data/$_conf"
	tee "$_datadir/$_conf" <<'EO_NGINX_SERVER'

	server_name  squirrelmail;
	root   /usr/local/www;
	index  index.php;

	location / {
		try_files $uri $uri/ /index.php?$args;
	}

	location ~ \.php$ {
		include        /usr/local/etc/nginx/fastcgi_params;
		fastcgi_index  index.php;
		fastcgi_param  SCRIPT_FILENAME  $document_root/$fastcgi_script_name;
		fastcgi_pass   php;
	}

	location ~* \.(?:css|gif|htc|ico|js|jpe?g|png|swf)$ {
		expires max;
		log_not_found off;
	}

EO_NGINX_SERVER

}

configure_squirrelmail_local()
{
	local _active_cfg; _active_cfg="$SQ_DIR/config/config_local.php"

	if [ -f "$_active_cfg" ]; then
		sqpass=$(grep '//squirrelmail:' "$_active_cfg" | cut -f3 -d: | cut -f1 -d@)
	fi

	if [ -n "$sqpass" ]; then
		tell_status "preserving squirrelmail mysql password: $sqpass"
	else
		sqpass=$(openssl rand -hex 18)
		tell_status "generating squirremail mysql password: $sqpass"
	fi

	cp "$SQ_DIR/config/config_local.php.sample" "$SQ_DIR/config/config_local.php"

	tee -a "$SQ_DIR/config/config_local.php" <<EO_SQUIRREL
\$signout_page = 'https://$TOASTER_HOSTNAME/';
\$domain = '$TOASTER_MAIL_DOMAIN';

\$smtpServerAddress = '$(get_jail_ip "$TOASTER_MSA")';
\$smtpPort = 465;
\$use_smtp_tls = true;
// PHP 5.6 enables verify_peer by default, which is good but in this context,
// unnecessary. Setting smtp_stream_options *should* disable that, but doesn't.
// Leave verify_peer disabled until squirrelmail gets this sorted out.
\$smtp_stream_options = [
	'ssl' => [
		'verify_peer'      => false,
		'verify_peer_name' => false,
		'verify_depth' => 3,
		'cafile' => '/etc/ssl/cert.pem',
		// 'allow_self_signed' => true,
	],
];
\$smtp_auth_mech = 'login';

\$imapServerAddress = '$(get_jail_ip dovecot)';
\$imap_server_type = 'dovecot';
\$use_imap_tls     = false;

\$data_dir = '/data/pref';
\$attachment_dir = '/data/attach';
// \$check_referrer = '$TOASTER_MAIL_DOMAIN';
\$check_mail_mechanism = 'advanced';

EO_SQUIRREL
}

configure_squirrelmail()
{
	configure_php squirrelmail
	configure_nginx squirrelmail
	configure_nginx_server
}

start_squirrelmail()
{
	start_php_fpm
	start_nginx
}

test_squirrelmail()
{
	test_nginx
	test_php_fpm

	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs squirrelmail
start_staged_jail squirrelmail
install_squirrelmail
configure_squirrelmail
start_squirrelmail
test_squirrelmail
promote_staged_jail squirrelmail
