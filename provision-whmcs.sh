#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include php
mt6-include nginx

install_whmcs()
{
	install_php 70 "ctype curl filter gd iconv imap json mbstring mcrypt openssl pdo_mysql session soap xml xmlrpc zip zlib"
	install_nginx whmcs

	stage_pkg_install sudo
}

configure_whmcs()
{
	configure_php
	configure_nginx whmcs

	mkdir -p "$STAGE_MNT/vendor/whmcs/whmcs"
	chown -R www:www "$STAGE_MNT/vendor"

	tee -a "$STAGE_MNT/etc/crontab" <<'EO_CRONTAB'
*/5     *       *       *       *       root    /usr/local/bin/php -q /data/secure/crons-7/cron.php
15      9       *       *       0       root    /usr/local/bin/php -q /data/secure/crons-7/domainsync.php
EO_CRONTAB

}

start_whmcs()
{
	php_fpm_start
	start_nginx
}

test_whmcs()
{
	test_nginx
	php_fpm_test
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs whmcs
start_staged_jail
install_whmcs
configure_whmcs
start_whmcs
test_whmcs
promote_staged_jail whmcs
