#!/bin/sh

# PHP-FPM can listen on a UNIX socket or a TCP port. Use 'tcp' if your web
# server will load balance to a pool of PHP-FPM servers. Else use sockets
# and avoid the TCP overhead.
PHP_LISTEN_MODE=${PHP_LISTEN_MODE:="socket"}

install_php()
{
	_version="$1"; if [ -z "$_version" ]; then _version="56"; fi

	tell_status "installing PHP $_version"

	_ports="php$_version"
	_modules="$2"

	if [ "$TOASTER_MYSQL" = "1" ]; then
		tell_status "including php mysql module"
		if [ "$_version" = "70" ]; then
			# php 70 doesn't have a plain mysql driver
			_modules="$_modules pdo_mysql"
		else
			_modules="$_modules pdo_mysql mysql"
		fi
	fi

	for m in $_modules
	do
		_ports="$_ports php$_version-$m"
	done

	# shellcheck disable=SC2086
	stage_pkg_install $_ports || exit
	install_php_newsyslog
}

install_php_newsyslog() {
	tell_status "enabling PHP-FPM log file rotation"
	tee "$STAGE_MNT/etc/newsyslog.conf.d/php-fpm" <<EO_FPM_NSL
# rotate the file after it reaches 1M
/var/log/php-fpm.log 600 7	1024	*	BCX	/var/run/php-fpm.pid 30
EO_FPM_NSL
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

	tell_status "enable syslog for PHP-FPM"
	sed -i .bak \
		-e '/^;error_log/ s/^;//' \
		-e '/^error_log/ s/= .*/= syslog/' \
		"$STAGE_MNT/usr/local/etc/php-fpm.conf"

	if [ "$PHP_LISTEN_MODE" = "tcp" ]; then
		return
	fi

	tell_status "switch PHP-FPM from TCP to unix socket"
	local _fpmconf="$STAGE_MNT/usr/local/etc/php-fpm.conf"
	if [ -f "$STAGE_MNT/usr/local/etc/php-fpm.d/www.conf" ]; then
		_fpmconf="$STAGE_MNT/usr/local/etc/php-fpm.d/www.conf"
	fi
	sed -i .bak \
		-e "/^listen =/      s/= .*/= '\/tmp\/php-cgi.socket';/" \
		-e '/^;listen.owner/ s/^;//' \
		-e '/^;listen.group/ s/^;//' \
		-e '/^;listen.mode/  s/^;//' \
		"$_fpmconf"
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
	if [ "$PHP_LISTEN_MODE" = "tcp" ]; then
		stage_listening 9000
	else
		if [ ! -S "$STAGE_MNT/tmp/php-cgi.socket" ]; then
			echo "no PHP-FPM socket found!"
			exit
		fi
	fi
}
