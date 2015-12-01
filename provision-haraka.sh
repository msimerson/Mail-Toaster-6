#!/bin/sh

. mail-toaster.sh || exit

install_haraka()
{
	install_redis || exit

	echo "installing node & npm"
	stage_pkg_install node npm || exit

	echo "installing Haraka"
	stage_exec npm install -g Haraka ws express || exit
}

install_geoip_dbs()
{
	mkdir -p $STAGE_MNT/usr/local/share/GeoIP $STAGE_MNT/usr/local/etc/periodic/weekly
	stage_exec npm install -g maxmind-geolite-mirror
	ln -s /usr/local/bin/maxmind-geolite-mirror /usr/local/etc/periodic/weekly/999.maxmind-geolite-mirror
	stage_exec /usr/local/bin/maxmind-geolite-mirror
}

install_p0f()
{
	grep -q devfsrules_jail_bpf /etc/devfs.rules || tee -a /etc/devfs.rules <<EO_DEVFS
[devfsrules_jail_bpf=7]
add include \$devfsrules_hide_all
add include \$devfsrules_unhide_basic
add include \$devfsrules_unhide_login
add path zfs unhide
add path 'bpf*' unhide
EO_DEVFS

	stage_pkg_install p0f

	local _netif=`netstat -i | awk 'NR==2{print $1;exit}'`
	fetch -o - http://mail-toaster.org/install/mt6-p0f.txt \
		| sed -e "s/ em0 / $_netif /" \
		> $STAGE_MNT/usr/local/etc/rc.d/p0f
	chmod 555 $STAGE_MNT/usr/local/etc/rc.d/p0f

	stage_sysrc p0f_enable=YES
	stage_exec service p0f start
}

configure_haraka()
{
	stage_exec haraka -i /usr/local/haraka || exit

	local _hconf="$STAGE_MNT/usr/local/haraka/config"

	sed -i .bak -e 's/^listen=\[.*$/listen=127.0.0.9:25,127.0.0.9:465,127.0.0.9:587/' $_hconf/smtp.ini
	sed -i .bak -e 's/^daemon_log_file=.*/daemon_log_file=\/dev\/null/' $_hconf/smtp.ini
	sed -i .bak -e 's/^host=localhost/host=127.0.0.8/' $_hconf/smtp_forward.ini
	sed -i .bak -e 's/^port=2555/port=25/' $_hconf/smtp_forward.ini
	echo 'reject=0' > $_hconf/dnsbl.ini
	echo 'periodic_checks=30' >> $_hconf/dnsbl.ini
	sed -i .bak -e 's/always_ok=false/always_ok=true/' $_hconf/log.syslog.ini

	sed -i .bak -e 's/; listen=\[::\]:80/listen=127.0.0.9:80/' $_hconf/http.ini

	ln /etc/ssl/certs/server.crt $_hconf/tls_cert.pem
	ln /etc/ssl/private/server.key $_hconf/tls_key.pem

	install_p0f
	perl -pi -e 's/^dnsbl$/dnsbl\nconnect.p0f/' $_hconf/plugins

	sed -i .bak -e 's/^host=127.0.0.1/host=127.0.0.8/' $_hconf/rcpt_to.qmail_deliverable.ini
	echo 'host=127.0.0.8' > $_hconf/auth_vpopmaild.ini
	sed -i .bak -e 's/^spamd_socket=127.0.0.1:783/spamd_socket=127.0.0.6:783/' $_hconf/spamassassin.ini
	sed -i .bak -e 's/^;spamd_user=$/spamd_user=first-recipient/' $_hconf/spamassassin.ini
	echo 'clamd_socket=127.0.0.5:3310' >> $_hconf/clamd.ini
	sed -i .bak -e 's/;host.*/host = 127.0.0.14/' $_hconf/avg.ini
	sed -i .bak -e 's/;tmpdir.*/tmpdir=\/var\/tmp\/avg/' $_hconf/avg.ini
	sed -i .bak -e 's/;host.*/host = 127.0.0.13/' $_hconf/rspamd.ini

	install_geoip_dbs
}

start_haraka()
{
	fetch -o $STAGE_MNT/usr/local/etc/rc.d/haraka http://mail-toaster.org/install/mt6-rcd.txt
	chmod 555 $STAGE_MNT/usr/local/etc/rc.d/haraka
	stage_sysrc haraka_enable=YES
	stage_sysrc haraka_flags="-c /usr/local/haraka"
	mkdir -p $STAGE_MNT/usr/local/haraka/queue
	stage_exec service haraka start
}

test_haraka()
{
	echo "testing Haraka... TODO"
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_staged_fs
stage_sysrc hostname=haraka
start_staged_jail
install_haraka
configure_haraka
start_haraka
test_haraka
promote_staged_jail haraka
