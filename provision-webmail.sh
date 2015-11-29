#!/bin/sh

. mail-toaster.sh || exit

install_php()
{
	stage_pkg_install php56 php56-fileinfo php56-mcrypt php56-exif php56-openssl

	cp $STAGE_MNT/usr/local/etc/php.ini-production $STAGE_MNT/usr/local/etc/php.ini
	sed -i .bak -e 's/^;date.timezone =/date.timezone = America\/Los_Angeles/' $STAGE_MNT/usr/local/etc/php.ini

	stage_rc_conf php_fpm_enable=YES
	jexec $SAFE_NAME service php-fpm start
}

install_roundcube()
{
	stage_pkg_install roundcube perl5

	# for sqlite storage
	mkdir -p $STAGE_MNT/var/db/roundcube
	chown 80:80 $STAGE_MNT/var/db/roundcube

	_rc_config=$STAGE_MNT/usr/local/www/roundcube/config/config.inc.php
	cp ${_rc_config}.sample $_rc_config

	fetch -o - http://mail-toaster.com/install/mt6-roundcube-cfg.diff \
		| patch -d $STAGE_MNT/usr/local/www/roundcube/config/
}

install_nginx()
{
	stage_pkg_install nginx dialog4ports || exit

	local _nginx_conf="$STAGE_MNT/usr/local/etc/nginx/conf.d"
	mkdir -p $_nginx_conf || exit
	fetch -o $_nginx_conf/mail-toaster.conf http://mail-toaster.com/install/mt6-webmail-nginx.txt

	fetch -o - http://mail-toaster.com/install/mt6-nginx.conf.diff \
		| patch -d $STAGE_MNT/usr/local/etc/nginx

	cat <<EONGINX >> $STAGE_MNT/etc/make.conf
www_nginx_SET=HTTP_REALIP
EONGINX

	mount_nullfs /usr/ports $STAGE_MNT/usr/ports
	jexec $SAFE_NAME make -C /usr/ports/www/nginx build deinstall install clean
	umount $STAGE_MNT/usr/ports

	stage_rc_conf nginx_enable=YES
	jexec $SAFE_NAME service nginx restart
}

install_webmail()
{
	install_php
	install_roundcube
	install_nginx
}

configure_webmail()
{
	mkdir -p $STAGE_MNT/usr/local/www/data
	fetch -o $STAGE_MNT/usr/local/www/data/index.html http://mail-toaster.com/install/mt6-index.txt

	fetch -o $STAGE_MNT/usr/local/etc/mime.types http://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types

	# local _jail_ssl="$STAGE_MNT/etc/ssl"
	# cat $_jail_ssl/private/server.key $_jail_ssl/certs/server.crt > $_jail_ssl/private/server.pem
}

start_webmail()
{
	# stage_rc_conf webmail_enable=YES
	# jexec $SAFE_NAME service webmail start
}

test_webmail()
{
	echo "testing webmail..."
	jexec $SAFE_NAME sockstat -l -4 | grep 80 || exit
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_staged_fs
sysrc -f $STAGE_MNT/etc/rc.conf hostname=webmail
start_staged_jail
install_webmail
configure_webmail
start_webmail
test_webmail
promote_staged_jail webmail
