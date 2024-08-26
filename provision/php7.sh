#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

mt6-include php

install_php7()
{
	install_php "74" "bcmath bz2 ctype curl dom exif fileinfo filter ftp gd gettext \
iconv json mbstring mysqli opcache openssl pdo pdo_mysql pdo_sqlite \
phar posix session simplexml soap sockets sqlite3 sysvmsg sysvsem tokenizer \
xml xmlreader xmlrpc xmlwriter xsl zip zlib"
}

start_php()
{
	start_php_fpm
}

test_php()
{
	test_php_fpm || exit 1

	echo "it worked"
	echo "You probably need to created a shared source between Nginx and this PHP jail"
}

base_snapshot_exists || exit 1
create_staged_fs php7
start_staged_jail php7
install_php7
configure_php php7
start_php
test_php
promote_staged_jail php7
