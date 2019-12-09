#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include php
mt6-include nginx

install_nagios()
{
	tell_status "installing nagios"
	stage_pkg_install nagios4 npre3 || exit

	tell_status "installing web services"
	install_nginx
	install_php 72
	stage_pkg_install fcgiwrap || exit
}

configure_nginx_server()
{
	local _datadir="$ZFS_DATA_MNT/nagios"
	if [ -f "$_datadir/etc/nginx-locations.conf" ]; then
		tell_status "preserving /data/etc/nginx-locations.conf"
		return
	fi

	tell_status "saving /data/etc/nginx-locations.conf"
	tee "$_datadir/etc/nginx-locations.conf" <<'EO_NGINX_SERVER'

    server_name         nagios;

    auth_basic "Private";
    auth_basic_user_file /data/etc/.htpasswds;

    location / {
        index  index.php;
        try_files $uri $uri/ /index.php?$query_string /nagios;
    }

    location /nagios {
        alias /usr/local/www/nagios;
        index  index.php;
        location ~ \.php$ {
            include /usr/local/etc/nginx/fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $request_filename;
            fastcgi_param AUTH_USER $remote_user;
            fastcgi_param REMOTE_USER $remote_user;
            fastcgi_pass php;
        }
        location ~ \.cgi$ {
            root /usr/local/www/nagios/cgi-bin;
            rewrite ^/nagios/cgi-bin/(.*)\.cgi /$1.cgi break;
            include /usr/local/etc/nginx/fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $request_filename;
            fastcgi_param AUTH_USER $remote_user;
            fastcgi_param REMOTE_USER $remote_user;
            fastcgi_pass unix:/var/run/fcgiwrap/fcgiwrap.sock;
        }
    }

EO_NGINX_SERVER
}

configure_fcgiwrap()
{
	stage_sysrc fcgiwrap_enable="YES"
	stage_sysrc fcgiwrap_user="www"
	stage_sysrc fcgiwrap_group="www"
	stage_sysrc fcgiwrap_socket_owner="www"
	stage_sysrc fcgiwrap_socket_group="www"
}

configure_nagios()
{
	echo "configuring nagios"
	stage_sysrc nagios_enable="YES"
	stage_sysrc nagios_configfile="/data/etc/nagios/nagios.cfg"

	if [ -d "$STAGE_MNT/data/spool" ]; then
		echo "/data/spool exists"
		rm -r "$STAGE_MNT/var/spool/nagios"
	else
		echo "moving nagios spool to /data/spool"
		mv "$STAGE_MNT/var/spool/nagios" "$STAGE_MNT/data/spool"
	fi
	echo "linking to /data/spool"
	stage_exec ln -s /data/spool /var/spool/nagios

	configure_nginx nagios
	configure_php
	configure_nginx_server
	configure_fcgiwrap
}

start_nagios()
{
	echo "starting"
	start_php_fpm
	start_nginx
	stage_exec service nagios start
	stage_exec service fcgiwrap start
}

test_nagios()
{
	echo "testing"
	test_nginx
	test_php_fpm
}

base_snapshot_exists || exit
create_staged_fs nagios
start_staged_jail nagios
install_nagios
configure_nagios
start_nagios
test_nagios
promote_staged_jail nagios
