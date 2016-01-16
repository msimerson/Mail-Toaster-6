#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

# shellcheck disable=2016
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/nginx \$path/data nullfs rw 0 0\";"


install_nginx()
{
	stage_pkg_install nginx dialog4ports || exit

	local _nginx_conf="$STAGE_MNT/usr/local/etc/nginx/conf.d"
	mkdir -p "$_nginx_conf" || exit

	tee "$_nginx_conf/mail-toaster.conf" <<'EO_NGINX_MT6'
set_real_ip_from $(get_jail_ip haproxy);
real_ip_header X-Forwarded-For;

location / {
   root   /usr/local/www/data;
   index  index.html index.htm;
}

EO_NGINX_MT6

	patch -d "$STAGE_MNT/usr/local/etc/nginx" <<'EO_NGINX_CONF'
--- nginx.conf-dist	2015-11-28 23:21:55.597113000 -0800
+++ nginx.conf	2015-11-28 23:43:25.508039518 -0800
@@ -34,16 +34,13 @@
 
     server {
         listen       80;
-        server_name  localhost;
+        server_name  nginx;
 
         #charset koi8-r;
 
         #access_log  logs/host.access.log  main;
 
         #error_page  404              /404.html;
 
EO_NGINX_CONF

	export BATCH=${BATCH:="1"}
	stage_make_conf www_nginx 'www_nginx_SET=HTTP_REALIP'
	stage_exec make -C /usr/ports/www/nginx build deinstall install clean

    tell_status "starting nginx"
    stage_sysrc nginx_enable=YES
    stage_exec service nginx start


}

start_nginx()
{
    tell_status "starting nginx"
    stage_sysrc nginx_enable=YES
    stage_exec service nginx start

}

test_nginx()
{
	tell_status "testing nginx"
	stage_exec sockstat -l -4 | grep :80 || exit
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs nginx
start_staged_jail
install_nginx
start_nginx
test_nginx
promote_staged_jail nginx
