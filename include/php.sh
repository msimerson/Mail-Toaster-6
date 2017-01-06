#!/bin/sh

install_php()
{
	_version="$1"; if [ -z "$_version" ]; then _version="56"; fi

	tell_status "installing PHP $_version"

	_ports="php$_version"
	_modules="$2"

	if [ "$TOASTER_MYSQL" = "1" ]; then
		tell_status "including php mysql module"
		_modules="$_modules pdo_mysql mysql"
	fi

	for m in $_modules
	do
		_ports="$_ports php$_version-$m"
	done

	# shellcheck disable=SC2086
	stage_pkg_install $_ports
}

configure_php_ini()
{
	local _php_ini="$STAGE_MNT/usr/local/etc/php.ini"

	if [ ! -z "$1" ]; then
		if [ -f "$ZFS_JAIL_MNT/$1/usr/local/etc/php.ini" ]; then
			tell_status "preserving php.ini"
			cp "$ZFS_JAIL_MNT/$1/usr/local/etc/php.ini" "$_php_ini"
			return
		fi
	fi

	cp "$STAGE_MNT/usr/local/etc/php.ini-production" "$_php_ini" || exit
	sed -i .bak \
		-e 's/^;date.timezone =/date.timezone = America\/Los_Angeles/' \
		-e '/^post_max_size/ s/8M/25M/' \
		-e '/^upload_max_filesize/ s/2M/25M/' \
		"$_php_ini"
}

configure_php_fpm() {
	sed -i .bak \
		-e '/;error_log/ s/= .*/syslog/' \
		"$STAGE_MNT/usr/local/etc/php-fpm.conf"
}

configure_php()
{
	configure_php_ini "$1"
	configure_php_fpm "$1"
}

start_php_fpm()
{
	tell_status "starting PHP FPM"
	stage_sysrc php_fpm_enable=YES
	stage_exec service php-fpm start || service php-fpm restart
}

test_php_fpm() {
	tell_status "testing PHP FPM (FastCGI Process Manager) is running"
	stage_test_running php-fpm

	tell_status "testing PHP FPM is listening"
	stage_listening 9000
}
