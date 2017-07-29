#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include 'php'

install_php7()
{
	install_php "70" "bcmath bz2 ctype curl dom exif fileinfo filter ftp gd gettext hash \
iconv json mbstring mcrypt mysqli opcache openssl pdo pdo_mysql pdo_sqlite \
phar posix recode session simplexml soap sockets sqlite3 sysvmsg sysvsem tokenizer wddx \
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
