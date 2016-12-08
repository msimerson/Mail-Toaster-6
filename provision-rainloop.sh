#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
# shellcheck disable=2016
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/rainloop \$path/data nullfs rw 0 0\";"

install_php()
{
	tell_status "installing PHP"
	stage_pkg_install php56

	local _php_ini="$STAGE_MNT/usr/local/etc/php.ini"
	cp "$STAGE_MNT/usr/local/etc/php.ini-production" "$_php_ini" || exit
	sed -i .bak \
		-e 's/^;date.timezone =/date.timezone = America\/Los_Angeles/' \
		-e '/^post_max_size/ s/8M/25M/' \
		-e '/^upload_max_filesize/ s/2M/25M/' \
		"$_php_ini"

	if [ "$TOASTER_MYSQL" = "1" ]; then
		tell_status "install php mysql module"
		stage_pkg_install php56-mysql
	fi
}

install_rainloop_mysql()
{
	local _init_db=0
	if ! mysql_db_exists rainloopmail; then
		tell_status "creating rainloop mysql db"
		echo "CREATE DATABASE rainloopmail;" | jexec mysql /usr/local/bin/mysql || exit
		_init_db=1
	fi

	local _active_cfg="$ZFS_JAIL_MNT/rainloop/usr/local/www/rainloop/config/config.inc.php"
	if [ -f "$_active_cfg" ]; then
		local _rcpass
		# shellcheck disable=2086
		_rcpass=$(grep '//rainloop:' $_active_cfg | grep ^\$config | cut -f3 -d: | cut -f1 -d@)
		if [ -n "$_rcpass" ] && [ "$_rcpass" != "pass" ]; then
			echo "preserving rainloop password $_rcpass"
		fi
	else
		_rcpass=$(openssl rand -hex 18)
	fi

	local _rcc_dir="$STAGE_MNT/usr/local/www/rainloop/config"
	sed -i .bak \
		-e "s/rainloop:pass@/rainloop:${_rcpass}@/" \
		-e "s/@localhost\//@$(get_jail_ip mysql)\//" \
		"$_rcc_dir/config.inc.php" || exit

	if [ "$_init_db" = "1" ]; then
		tell_status "configuring rainloop mysql permissions"
		local _grant='GRANT ALL PRIVILEGES ON rainloopmail.* to'

		echo "$_grant 'rainloop'@'$(get_jail_ip rainloop)' IDENTIFIED BY '${_rcpass}';" \
			| jexec mysql /usr/local/bin/mysql || exit

		echo "$_grant 'rainloop'@'$(get_jail_ip stage)' IDENTIFIED BY '${_rcpass}';" \
			| jexec mysql /usr/local/bin/mysql || exit

		rainloop_init_db
	fi
}

rainloop_init_db()
{
	tell_status "initializating rainloop db"
	pkg install -y curl || exit
	stage_exec service php-fpm restart
	curl -i -F initdb='Initialize database' -XPOST \
		"http://$(get_jail_ip stage)/rainloop/installer/index.php?_step=3" || exit
}

install_rainloop()
{
	install_php || exit
	install_nginx || exit

	tell_status "installing rainloop"
	stage_pkg_install rainloop-community

	# for sqlite storage
	# mkdir -p "$STAGE_MNT/data"
	# chown 80:80 "$STAGE_MNT/data"

	# local _rcc_conf="$STAGE_MNT/usr/local/www/rainloop/config/config.inc.php"
	# cp "$_rcc_conf.sample" "$_rcc_conf" || exit

	# local _dovecot_ip; _dovecot_ip=$(get_jail_ip dovecot)
	# sed -i .bak \
	# 	-e "/'default_host'/ s/'localhost'/'$_dovecot_ip'/" \
	# 	-e "/'smtp_server'/  s/'';/'tls:\/\/haraka';/" \
	# 	-e "/'smtp_port'/    s/25;/587;/" \
	# 	-e "/'smtp_user'/    s/'';/'%u';/" \
	# 	-e "/'smtp_pass'/    s/'';/'%p';/" \
	# 	"$_rcc_conf"

# 	tee -a "$_rcc_conf" <<'EO_RC_ADD'

# $config['log_driver'] = 'syslog';
# $config['session_lifetime'] = 30;
# $config['enable_installer'] = true;
# $config['mime_types'] = '/usr/local/etc/mime.types';
# $config['smtp_conn_options'] = array(
#  'ssl'            => array(
#    'verify_peer'  => false,
#    'verify_peer_name' => false,
#    'verify_depth' => 3,
#    'cafile'       => '/etc/ssl/cert.pem',
#  ),
# );
# EO_RC_ADD

	if [ "$TOASTER_MYSQL" = "1" ]; then
		# install_rainloop_mysql
	else
		# stage_pkg_install php56-pdo_sqlite
		# sed -i.bak \
		# 	-e "/^\$config\['db_dsnw'/ s/= .*/= 'sqlite:\/\/\/\/data\/sqlite.db?mode=0646';/" \
		# 	"$_rcc_conf"

		# if [ ! -f "$ZFS_DATA_MNT/rainloop/sqlite.db" ]; then
		# 	rainloop_init_db
		# fi
	fi

	# sed -i.bak \
	# 	-e "s/enable_installer'] = true;/enable_installer'] = false;/" \
	# 	"$_rcc_conf"
}

install_nginx()
{
	stage_pkg_install nginx || exit

	patch -d "$STAGE_MNT/usr/local/etc/nginx" <<'EO_NGINX_CONF'
--- nginx.conf-dist	2016-11-03 05:11:28.000000000 -0700
+++ nginx.conf	2016-12-07 16:29:52.835309001 -0800
@@ -41,17 +41,26 @@
 
     server {
         listen       80;
-        server_name  localhost;
+        server_name  rainloop;
 
         #charset koi8-r;
 
         #access_log  logs/host.access.log  main;
 
         location / {
-            root   /usr/local/www/nginx;
-            index  index.html index.htm;
+            root   /usr/local/www/rainloop;
+            index  index.php;
         }
 
+        location /rainloop/ {
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
+            root           /usr/local/www/rainloop;
+            fastcgi_pass   127.0.0.1:9000;
+            fastcgi_index  index.php;
+            fastcgi_param  SCRIPT_FILENAME  $document_root/$fastcgi_script_name;
+            include        fastcgi_params;
+        }
 
         # deny access to .htaccess files, if Apache's document root
         # concurs with nginx's one
EO_NGINX_CONF
}

configure_rainloop()
{
	tell_status "installing mime.types"
	fetch -o "$STAGE_MNT/usr/local/etc/mime.types" \
		http://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types
}

start_rainloop()
{
	tell_status "starting PHP"
	stage_sysrc php_fpm_enable=YES
	stage_exec service php-fpm start

	tell_status "starting nginx"
	stage_sysrc nginx_enable=YES
	stage_exec service nginx start
}

test_rainloop()
{
	tell_status "testing rainloop httpd"
	stage_listening 80

	tell_status "testing rainloop php"
	stage_listening 9000
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs rainloop
start_staged_jail
install_rainloop
configure_rainloop
start_rainloop
test_rainloop
promote_staged_jail rainloop
