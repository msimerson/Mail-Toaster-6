#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

# shellcheck disable=2016
#@TODO create a shared dir between nginx and php7
#export JAIL_CONF_EXTRA="
#		mount += \"$ZFS_DATA_MNT/php7 \$path/data nullfs rw 0 0\";"

install_php()
{
	tell_status "installing PHP7"
	stage_pkg_install php70 php70-bcmath php70-bz2 php70-ctype php70-curl php70-dom php70-exif \
php70-fileinfo php70-filter php70-ftp php70-gd php70-gettext php70-hash \
php70-iconv php70-json php70-mbstring php70-mcrypt php70-mysqli \
php70-opcache php70-openssl php70-pdo php70-pdo_mysql php70-pdo_sqlite \
php70-phar php70-posix php70-recode php70-session php70-simplexml php70-soap \
php70-sockets php70-sqlite3 php70-sysvmsg php70-sysvsem php70-tokenizer php70-wddx \
php70-xml php70-xmlreader php70-xmlrpc php70-xmlwriter php70-xsl \
php70-zip php70-zlib
}

configure_php()
{
	local _php_ini="$STAGE_MNT/usr/local/etc/php.ini"

	if [ -f "$ZFS_JAIL_MNT/php7/usr/local/etc/php.ini" ]; then
		tell_status "preserving php.ini"
		cp "$ZFS_JAIL_MNT/php7/usr/local/etc/php.ini" "$_php_ini"
		return
	fi

	cp "$STAGE_MNT/usr/local/etc/php.ini-production" "$_php_ini" || exit
	sed -i .bak \
		-e 's/^;date.timezone =/date.timezone = America\/Los_Angeles/' \
		-e '/^post_max_size/ s/8M/25M/' \
		-e '/^upload_max_filesize/ s/2M/25M/' \
		"$_php_ini"
}

start_php()
{
	tell_status "starting PHP"
	stage_sysrc php_fpm_enable=YES
	stage_exec service php-fpm start

}

test_php()
{
	tell_status "testing php7"
	stage_listening 9000
	echo "it worked"
    echo  "You probably need to created a shared source between Nginx and this PHP jail"
}

base_snapshot_exists || exit
create_staged_fs php7
start_staged_jail
install_php
configure_php
start_php
test_php
promote_staged_jail php7
