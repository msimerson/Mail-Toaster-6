#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
# shellcheck disable=2016
export JAIL_CONF_EXTRA=""

install_nginx()
{
	stage_pkg_install nginx || exit
}

configure_nginx()
{
	local _nginx_conf="$STAGE_MNT/usr/local/etc/nginx/conf.d"
	mkdir -p "$_nginx_conf" || exit

	patch -d "$STAGE_MNT/usr/local/etc/nginx" <<EO_NGINX_CONF
--- nginx.conf-dist     2016-01-16 16:20:58.874842000 -0800
+++ nginx.conf  2016-01-16 16:22:36.860852732 -0800
@@ -34,7 +34,10 @@
 
     server {
         listen       80;
-        server_name  localhost;
+        server_name  nginx;
+
+        set_real_ip_from $(get_jail_ip haproxy);
+        real_ip_header X-Forwarded-For;
 
         #charset koi8-r;
 
EO_NGINX_CONF
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
	stage_listening 80
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs nginx
start_staged_jail
install_nginx
configure_nginx
start_nginx
test_nginx
promote_staged_jail nginx
