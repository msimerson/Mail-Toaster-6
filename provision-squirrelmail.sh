#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
# shellcheck disable=2016
export JAIL_CONF_EXTRA=""

mt6-include 'php'
mt6-include nginx

install_squirrelmail_mysql()
{
	if [ "$SQUIRREL_SQL" != "1" ]; then return; fi

	if ! mysql_db_exists squirrelmail; then
		tell_status "creating squirrelmail database"
		echo "CREATE DATABASE squirrelmail;" | jexec mysql /usr/local/bin/mysql || exit
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
);" | jexec mysql /usr/local/bin/mysql squirrelmail || exit

	fi

	tee -a "$_sq_dir/config_local.php" <<EO_SQUIRREL_SQL
\$prefs_dsn = 'mysql://squirrelmail:${_sqpass}@$(get_jail_ip mysql)/squirrelmail';
\$addrbook_dsn = 'mysql://squirrelmail:${_sqpass}@$(get_jail_ip mysql)/squirrelmail';
EO_SQUIRREL_SQL

	local _grant='GRANT ALL PRIVILEGES ON squirrelmail.* to'

	echo "$_grant 'squirrelmail'@'$(get_jail_ip squirrelmail)' IDENTIFIED BY '${_sqpass}';" \
		| jexec mysql /usr/local/bin/mysql || exit

	echo "$_grant 'squirrelmail'@'$(get_jail_ip stage)' IDENTIFIED BY '${_sqpass}';" \
		| jexec mysql /usr/local/bin/mysql || exit
}

install_squirrelmail()
{
	install_php 56 "fileinfo mcrypt exif openssl"
	install_nginx || exit

	tell_status "installing squirrelmail"
	stage_pkg_install squirrelmail squirrelmail-sasql-plugin \
		squirrelmail-quota_usage-plugin || exit

	_sq_dir="$STAGE_MNT/usr/local/www/squirrelmail/config"

	local _active_cfg; _active_cfg="$_sq_dir/config_local.php"
	if [ -f "$_active_cfg" ]; then
		_sqpass=$(grep '//squirrelmail:' "$_active_cfg" | cut -f3 -d: | cut -f1 -d@)
		echo "preserving existing squirrelmail mysql password: $_sqpass"
	else
		_sqpass=$(openssl rand -hex 18)
	fi

	cp "$_sq_dir/config_local.php.sample" "$_sq_dir/config_local.php"
	cp "$_sq_dir/config_default.php" "$_sq_dir/config.php"
	cp "$_sq_dir/../plugins/sasql/sasql_conf.php.dist" \
	   "$_sq_dir/../plugins/sasql/sasql_conf.php"
	cp "$_sq_dir/../plugins/quota_usage/config.php.sample" \
	   "$_sq_dir/../plugins/quota_usage/config.php"

	tee -a "$_sq_dir/config_local.php" <<EO_SQUIRREL
\$signout_page = 'https://$TOASTER_HOSTNAME/';
\$domain = '$TOASTER_MAIL_DOMAIN';

\$smtpServerAddress = '$(get_jail_ip haraka)';
\$smtpPort = 465;
\$use_smtp_tls = true;
// PHP 5.6 enables verify_peer by default, which is good but in this context,
// unnecessary. Setting smtp_stream_options *should* disable that, but doesn't.
// Leave squirrelmail disabled until squirrelmail gets this sorted out.
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

\$data_dir = '/data/data';
\$attachment_dir = '/data/attach';
// \$check_referrer = '$TOASTER_MAIL_DOMAIN';
\$check_mail_mechanism = 'advanced';

EO_SQUIRREL

	mkdir -p "$STAGE_MNT/data/attach" "$STAGE_MNT/data/data"
	cp "$_sq_dir/../data/default_pref" "$STAGE_MNT/data/data/"
	chown -R www:www "$STAGE_MNT/data"
	chmod 733 "$STAGE_MNT/data/attach"

	install_squirrelmail_mysql
}

configure_squirrelmail()
{
	configure_php squirrelmail
	config_nginx squirrelmail

	local _datadir="$ZFS_DATA_MNT/squirrelmail"
	if [ ! -f "$_datadir/etc/nginx-server.conf" ]; then
		tell_status "saving /data/etc/nginx-server.conf"
		tee "$_datadir/etc/nginx-server.conf" <<'EO_NGINX_SERVER'

server {
    listen       80;
    server_name  squirrelmail;

    set_real_ip_from haproxy;
    real_ip_header X-Forwarded-For;
    client_max_body_size 25m;

    location / {
        root   /usr/local/www/squirrelmail;
        index  index.php;
    }

    location /squirrelmail/ {
        root /usr/local/www;
        index  index.php;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/local/www/nginx-dist;
    }

    location ~ \.php$ {
        alias          /usr/local/www;
        fastcgi_pass   127.0.0.1:9000;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  $document_root/$fastcgi_script_name;
        include        /usr/local/www/nginx/fastcgi_params;
    }
}

EO_NGINX_SERVER

		sed -i .bak \
			-e "s/haproxy/$(get_jail_ip haproxy)/" \
			"$_datadir/etc/nginx-server.conf"
	fi
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
start_staged_jail
install_squirrelmail
configure_squirrelmail
start_squirrelmail
test_squirrelmail
promote_staged_jail squirrelmail
