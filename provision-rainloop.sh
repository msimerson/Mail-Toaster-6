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
		stage_pkg_install php56-pdo_mysql
	fi
}

install_rainloop()
{
	install_php || exit
	install_nginx || exit

	tell_status "installing rainloop"
	stage_pkg_install rainloop-community
}

install_nginx()
{
	stage_pkg_install nginx || exit

	patch -d "$STAGE_MNT/usr/local/etc/nginx" <<'EO_NGINX_CONF'
--- nginx.conf-dist	2016-11-03 05:11:28.000000000 -0700
+++ nginx.conf	2016-12-08 11:20:33.255330697 -0800
@@ -41,17 +41,22 @@
 
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
+            try_files $uri $uri/ /index.php?$query_string;
         }
 
+        set_real_ip_from 172.16.15.12;
+        real_ip_header X-Forwarded-For;
+        client_max_body_size 25m;
+
         #error_page  404              /404.html;
 
         # redirect server error pages to the static page /50x.html
@@ -69,20 +74,27 @@
 
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
+            root   /usr/local/www/rainloop;
+            try_files $uri $uri/ /index.php?$query_string;
+            fastcgi_split_path_info ^(.+\.php)(.*)$;
+            fastcgi_keep_conn on;
+            fastcgi_pass   127.0.0.1:9000;
+            fastcgi_index  index.php;
+            fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;
+            include        fastcgi_params;
+        }
 
         # deny access to .htaccess files, if Apache's document root
         # concurs with nginx's one
         #
-        #location ~ /\.ht {
-        #    deny  all;
-        #}
+        location ~ /\.ht {
+            deny  all;
+        }
+
+        location ^~ /data {
+            deny all;
+        }
     }
 
 
EO_NGINX_CONF
}

configure_rainloop()
{
	# for persistent data storage
	chown 80:80 "$ZFS_DATA_MNT/rainloop/"

	local _rl_ver;
    _rl_ver="$(pkg -j stage info rainloop-community | grep Version | awk '{ print $3 }')"
	local _rl_root="$STAGE_MNT/usr/local/www/rainloop/rainloop/v/$_rl_ver"
	tee -a "$_rl_root/include.php" <<'EO_INCLUDE'

    function __get_custom_data_full_path()
    {
	    return '/data/'; // custom data folder path
    }
EO_INCLUDE

	if [ ! -f "$ZFS_DATA_MNT/rainloop/_data_/_default_/domains/default.ini" ]; then
		tell_status "installing domains/default.ini"
		tee -a "$ZFS_DATA_MNT/rainloop/_data_/_default_/domains/default.ini" <<EO_INI
imap_host = "dovecot"
imap_port = 143
imap_secure = "None"
imap_short_login = Off
sieve_use = Off
sieve_allow_raw = Off
sieve_host = ""
sieve_port = 4190
sieve_secure = "None"
smtp_host = "haraka"
smtp_port = 587
smtp_secure = "TLS"
smtp_short_login = Off
smtp_auth = On
smtp_php_mail = Off
white_list = ""
EO_INI
	fi
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
