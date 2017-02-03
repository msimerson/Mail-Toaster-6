#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
	mount += \"$ZFS_DATA_MNT/whmcs \$path/data nullfs rw 0 0\";
	mount += \"$ZFS_DATA_MNT/geoip \$path/usr/local/share/GeoIP nullfs ro 0 0\";"

mt6-include php
mt6-include nginx

install_whmcs()
{
	install_php 70 "ctype curl filter gd iconv imap json mbstring mcrypt openssl session soap xml xmlrpc zip zlib"
	install_nginx whmcs

	stage_pkg_install sudo
	stage_exec make -C /usr/ports/devel/ioncube clean build install clean
}

configure_whmcs()
{
	configure_php whmcs
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
	start_php_fpm
	start_nginx
}

test_whmcs()
{
	test_nginx
	test_php_fpm
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
