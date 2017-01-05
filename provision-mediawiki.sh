#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_php()
{
	tell_status "installing PHP"
 	_ports="php56" 
#	for p in ctype curl filter gd iconv imap json mbstring mcrypt pdo_mysql session soap xml xmlrpc zip zlib
 	for p in gd openssl
 	do
 		_ports="$_ports php56-$p"
 	done

	stage_pkg_install $_ports
	#stage_exec make -C /usr/ports/devel/ioncube build install clean

	local _php_ini="$STAGE_MNT/usr/local/etc/php.ini"
	cp "$STAGE_MNT/usr/local/etc/php.ini-production" "$_php_ini" || exit
	sed -i .bak \
		-e 's/^;date.timezone =/date.timezone = America\/Los_Angeles/' \
		-e '/^post_max_size/ s/8M/25M/' \
		-e '/^upload_max_filesize/ s/2M/25M/' \
		"$_php_ini"
}

install_nginx()
{
	tell_status "installing nginx"
	stage_pkg_install nginx

	if [ ! -f "$ZFS_JAIL_MNT/mediawiki/var/db/ports/www_nginx/options" ]; then
		return
	fi

#	if [ ! -d "$STAGE_MNT/var/db/ports/www_nginx" ]; then
#		tell_status "creating /var/db/ports/www_nginx" 
#		mkdir -p  "$STAGE_MNT/var/db/ports/www_nginx" || exit
#	fi
#
#	tell_status "copying www_nginx/options"
#	cp "$ZFS_JAIL_MNT/mediawiki/var/db/ports/www_nginx/options" \
#		"$STAGE_MNT/var/db/ports/www_nginx/options" || exit
#
#	tell_status "installing nginx port with localized options"
#	stage_pkg_install GeoIP dialog4ports gettext
#	stage_exec make -C /usr/ports/www/nginx build deinstall install clean
}

install_mediawiki()
{
	install_php
	install_nginx

	stage_pkg_install mediawiki128 xcache
}

configure_mediawiki()
{
	stage_sysrc php_fpm_enable=YES
	stage_sysrc nginx_enable=YES
#	stage_sysrc nginx_flags='-c /data/etc/nginx.conf'

	mkdir -p "$STAGE_MNT/var/log/http"
	chown www:www "$STAGE_MNT/var/log/http"
}

start_mediawiki()
{
	stage_exec service php-fpm start
	stage_exec service nginx start
}

test_mediawiki()
{
	tell_status "testing httpd"
	stage_listening 80

	tell_status "testing php-fpm"
	stage_listening 9000
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs mediawiki
start_staged_jail
install_mediawiki
configure_mediawiki
start_mediawiki
test_mediawiki
promote_staged_jail mediawiki
