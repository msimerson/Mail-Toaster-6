#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
# shellcheck disable=2016
export JAIL_CONF_EXTRA=""

mt6-include php
mt6-include nginx

install_joomla()
{
	assure_jail mysql

	# curl so that Joomla updater works
	install_php 72 "curl mysqli" || exit

	tell_status "installing Joomla 3"
	stage_pkg_install joomla3

	install_nginx || exit
}

configure_nginx_server()
{
	if [ -f "$ZFS_JAIL_MNT/joomla/usr/local/etc/nginx/nginx.conf" ]; then
		tell_status "preserving nginx.conf"
		cp "$ZFS_JAIL_MNT/joomla/usr/local/etc/nginx/nginx.conf" \
			"$STAGE_MNT/usr/local/etc/nginx/nginx.conf"
		return
	fi

	local _nginx_conf="$STAGE_MNT/usr/local/etc/nginx/conf.d"
	mkdir -p "$_nginx_conf" || exit

	tee "$_nginx_conf/joomla.conf" <<EO_NGINX
server {
    listen       80;
    server_name  joomla;

	set_real_ip_from $(get_jail_ip haproxy);
	real_ip_header X-Forwarded-For;
	client_max_body_size 25m;

	location / {
	   root   /usr/local/www/joomla3;
	   index  index.php;
	}

	location ~  ^/(.+\.php)\$ {
	   include        /usr/local/etc/nginx/fastcgi_params;
	   fastcgi_index  index.php;
	   fastcgi_param  SCRIPT_FILENAME  \$document_root/\$1/\$2;
	   fastcgi_pass   php;
	}
}

EO_NGINX

}

configure_joomla()
{
	configure_php joomla
	configure_nginx joomla
	configure_nginx_server

	_htdocs="$STAGE_MNT/usr/local/www/joomla3"

	if [ -f "$ZFS_JAIL_MNT/joomla/usr/local/www/joomla3/configuration.php" ]; then
		echo "preserving joomla3 configuration.php"
		cp "$ZFS_JAIL_MNT/joomla/usr/local/www/joomla3/configuration.php" "$_htdocs/"
		return
	fi

	if [ ! -f "$_htdocs/robots.txt" ]; then
		tell_status "installing robots.txt"
		tee "$_htdocs/robots.txt" <<EO_ROBOTS_TXT
User-agent: *
Disallow: /
EO_ROBOTS_TXT
	fi
}

start_joomla()
{
	start_php_fpm
	start_nginx
}

test_joomla()
{
	test_php_fpm
	test_nginx
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs joomla
start_staged_jail joomla
install_joomla
configure_joomla
start_joomla
test_joomla
promote_staged_jail joomla
