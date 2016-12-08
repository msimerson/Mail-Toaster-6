#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
# shellcheck disable=2016
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/squirrelmail \$path/data nullfs rw 0 0\";"

install_php()
{
	tell_status "installing PHP"
	stage_pkg_install php56 php56-fileinfo php56-mcrypt php56-exif php56-openssl

	if [ "$TOASTER_MYSQL" = "1" ]; then
		tell_status "install php mysql module"
		stage_pkg_install php56-mysql
	fi

	local _php_ini="$STAGE_MNT/usr/local/etc/php.ini"
	cp "$STAGE_MNT/usr/local/etc/php.ini-production" "$_php_ini" || exit
	sed -i .bak \
		-e 's/^;date.timezone =/date.timezone = America\/Los_Angeles/' \
		-e '/^post_max_size/ s/8M/25M/' \
		-e '/^upload_max_filesize/ s/2M/25M/' \
		"$_php_ini"
}

install_squirrelmail_mysql()
{
	if [ "$TOASTER_MYSQL" != "1" ]; then return; fi

	local _init_db=0
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
	install_php || exit
	install_nginx || exit

	tell_status "installing squirrelmail"
	stage_pkg_install squirrelmail squirrelmail-sasql-plugin \
		squirrelmail-quota_usage-plugin || exit

	_sq_dir="$STAGE_MNT/usr/local/www/squirrelmail/config"

	local _active_cfg; _active_cfg="$_sq_dir/config.inc.php"
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

install_nginx()
{
	stage_pkg_install nginx || exit

	patch -d "$STAGE_MNT/usr/local/etc/nginx" <<'EO_NGINX_CONF'
--- nginx.conf-dist	2016-11-03 05:11:28.000000000 -0700
+++ nginx.conf	2016-12-07 16:23:22.184892048 -0800
@@ -41,17 +41,26 @@
 
     server {
         listen       80;
-        server_name  localhost;
+        server_name  squirrelmail;
 
         #charset koi8-r;
 
         #access_log  logs/host.access.log  main;
 
         location / {
-            root   /usr/local/www/nginx;
-            index  index.html index.htm;
+            root   /usr/local/www/squirrelmail;
+            index  index.php;
         }
 
+        location /squirrelmail/ {
+            root /usr/local/www;
+            index  index.php;
+        }
+
+        set_real_ip_from 172.16.15.12;
+        real_ip_header X-Forwarded-For;
+        client_max_body_size 25m;
+
         #error_page  404              /404.html;
 
         # redirect server error pages to the static page /50x.html
@@ -69,13 +78,13 @@
 
         # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
         #
-        #location ~ \.php$ {
-        #    root           html;
-        #    fastcgi_pass   127.0.0.1:9000;
-        #    fastcgi_index  index.php;
-        #    fastcgi_param  SCRIPT_FILENAME  /scripts$fastcgi_script_name;
-        #    include        fastcgi_params;
-        #}
+        location ~ \.php$ {
+            alias          /usr/local/www;
+            fastcgi_pass   127.0.0.1:9000;
+            fastcgi_index  index.php;
+            fastcgi_param  SCRIPT_FILENAME  $document_root/$fastcgi_script_name;
+            include        fastcgi_params;
+        }
 
         # deny access to .htaccess files, if Apache's document root
         # concurs with nginx's one
EO_NGINX_CONF

}

configure_squirrelmail()
{
	_htdocs="$ZFS_DATA_MNT/squirrelmail/htdocs"
	if [ ! -d "$_htdocs" ]; then
	   mkdir -p "$_htdocs"
	fi
}

start_squirrelmail()
{
	tell_status "starting PHP"
	stage_sysrc php_fpm_enable=YES
	stage_exec service php-fpm start

	tell_status "starting nginx"
	stage_sysrc nginx_enable=YES
	stage_exec service nginx start
}

test_squirrelmail()
{
	tell_status "testing squirrelmail httpd"
	stage_listening 80

	tell_status "testing squirrelmail php"
	stage_listening 9000
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
