#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA="devfs_ruleset=7"
export JAIL_CONF_EXTRA='
		devfs_ruleset = 7;'

HARAKA_CONF="$STAGE_MNT/usr/local/haraka/config"

install_haraka()
{
	install_redis || exit

	tell_status "installing node & npm"
	stage_pkg_install node npm gmake || exit

	tell_status "installing Haraka"
	stage_exec npm install -g Haraka ws express || exit
}

install_geoip_dbs()
{
	tell_status "install GeoIP databases & updater"
	mkdir -p $STAGE_MNT/usr/local/share/GeoIP $STAGE_MNT/usr/local/etc/periodic/weekly
	stage_exec npm install -g maxmind-geolite-mirror  || exit
	ln -s /usr/local/bin/maxmind-geolite-mirror /usr/local/etc/periodic/weekly/999.maxmind-geolite-mirror
	stage_exec /usr/local/bin/maxmind-geolite-mirror

	tell_status "enabling Haraka geoip plugin"
	sed -i -e 's/^;calc_distance=false/calc_distance=true/' $HARAKA_CONF/connect.geoip.ini
	sed -i -e 's/^# connect.geoip/connect.geoip/' $HARAKA_CONF/plugins
}

add_devfs_rule()
{
	if ! grep -q devfsrules_jail_bpf /etc/devfs.rules; then
		tell_status "installing devfs ruleset for p0f"
		tee -a /etc/devfs.rules <<EO_DEVFS
[devfsrules_jail_bpf=7]
add include \$devfsrules_hide_all
add include \$devfsrules_unhide_basic
add include \$devfsrules_unhide_login
add path zfs unhide
add path 'bpf*' unhide
EO_DEVFS
	fi
}

install_p0f()
{
	tell_status "install p0f"
	stage_pkg_install p0f

	tell_status "installing p0f startup file"
	local _start="$STAGE_MNT/usr/local/etc/rc.d/p0f"
	cp $STAGE_MNT/usr/local/lib/node_modules/Haraka/contrib/bsd-rc.d/p0f $_start || exit
	chmod 755 $_start || exit

	get_public_facing_nic
	if [ "$PUBLIC_NIC" != "bce1" ]; then
		sed -i -e "s/ bce1 / $PUBLIC_NIC /" $_start || exit
	fi

	stage_sysrc p0f_enable=YES
	stage_exec service p0f start
}

config_haraka_syslog()
{
	tell_status "switch Haraka logging to syslog"
	sed -i -e 's/# log.syslog$/log.syslog/' $HARAKA_CONF/plugins
	# sed -i -e 's/^daemon_log_file=.*/daemon_log_file=\/dev\/null/' $HARAKA_CONF/smtp.ini
	sed -i -e 's/always_ok=false/always_ok=true/' $HARAKA_CONF/log.syslog.ini
}

config_haraka_vpopmail()
{
	tell_status "configure smtp forward to vpopmail jail"
	sed -i -e "s/^host=localhost/host=$JAIL_NET_PREFIX.8/" $HARAKA_CONF/smtp_forward.ini
	sed -i -e 's/^port=2555/port=25/' $HARAKA_CONF/smtp_forward.ini

	tell_status "config SMTP AUTH using vpopmaild"
	echo "host=$JAIL_NET_PREFIX.8" > $HARAKA_CONF/auth_vpopmaild.ini
	sed -i -e '/^# auth\/auth_ldap$/a\
auth\/auth_vpopmaild
' $HARAKA_CONF/plugins
}

config_haraka_qmail_deliverable()
{
	tell_status "config recipient validation with Qmail::Deliverable"
	sed -i -e "s/^host=127.0.0.1/host=$JAIL_NET_PREFIX.8/" $HARAKA_CONF/rcpt_to.qmail_deliverable.ini
	sed -i -e 's/^#rcpt_to.qmail_deliverable/rcpt_to.qmail_deliverable/' $HARAKA_CONF/plugins
	sed -i -e 's/^rcpt_to.in_host_list/# rcpt_to.in_host_list/' $HARAKA_CONF/plugins
}

config_haraka_p0f()
{
	install_p0f

	tell_status "enable Haraka p0f plugin"
	sed -i -e 's/^# connect.p0f/connect.p0f/' $HARAKA_CONF/plugins
}

config_haraka_spamassassin()
{
	tell_status "configuring Haraka spamassassin plugin"
	sed -i -e "s/^spamd_socket=127.0.0.1:783/spamd_socket=$JAIL_NET_PREFIX.6:783/" $HARAKA_CONF/spamassassin.ini
	sed -i -e 's/^;spamd_user=$/spamd_user=first-recipient/' $HARAKA_CONF/spamassassin.ini
	sed -i -e 's/^; reject_threshold$/reject_threshold/' $HARAKA_CONF/spamassassin.ini
	sed -i -e 's/^; relay_reject_threshold$/relay_reject_threshold/' $HARAKA_CONF/spamassassin.ini

	sed -i -e 's/^#spamassassin$/spamassassin/' $HARAKA_CONF/plugins
}

config_haraka_avg()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/avg"; then
		echo "AVG not installed, skipping"
		return
	fi

	tell_status "configuring Haraka avg plugin"
	mkdir -p $STAGE_MNT/data/avg || exit

	JAIL_CONF_EXTRA="$JAIL_CONF_EXTRA
		mount += \"$ZFS_DATA_MNT/avg \$path/data/avg nullfs rw 0 0\";
"
	sed -i -e "s/;host.*/host = $JAIL_NET_PREFIX.14/" $HARAKA_CONF/avg.ini
	sed -i -e 's/;tmpdir.*/tmpdir=\/data\/avg/' $HARAKA_CONF/avg.ini
	sed -i -e '/clamd$/a\
avg
' $HARAKA_CONF/plugins
}

config_haraka_clamav()
{
	tell_status "configure Haraka clamav plugin"
	echo "clamd_socket=$JAIL_NET_PREFIX.5:3310" >> $HARAKA_CONF/clamd.ini
	sed -i -e 's/^#clamd$/clamd/' $HARAKA_CONF/plugins
}

config_haraka_tls() {	
	tell_status "enable TLS encryption"
	sed -i -e 's/^# tls$/tls/' $HARAKA_CONF/plugins
	ln $STAGE_MNT/etc/ssl/certs/server.crt $HARAKA_CONF/tls_cert.pem
	ln $STAGE_MNT/etc/ssl/private/server.key $HARAKA_CONF/tls_key.pem
}

config_haraka_dnsbl()
{
	tell_status "configuring dnsbls"
	echo 'reject=0' > $HARAKA_CONF/dnsbl.ini
	echo 'periodic_checks=30' >> $HARAKA_CONF/dnsbl.ini

	echo "; zen.spamhaus.org
b.barracudacentral.org
truncate.gbudb.net
cbl.abuseat.org
psbl.surriel.com
bl.spamcop.net
dnsbl-1.uceprotect.net
pbl.spamhaus.org
xbl.spamhaus.org
" | tee $HARAKA_CONF/dnsbl.zones
}

cleanup_deprecated_haraka()
{
	rm $HARAKA_CONF/lookup_rdns.strict.ini
	rm $HARAKA_CONF/lookup_rdns.strict.timeout
	rm $HARAKA_CONF/lookup_rdns.strict.whitelist
	rm $HARAKA_CONF/lookup_rdns.strict.whitelist_regex
	rm $HARAKA_CONF/mail_from.access.blacklist_regex
	rm $HARAKA_CONF/rcpt_to.blocklist
	rm $HARAKA_CONF/rdns.allow_regexps
	rm $HARAKA_CONF/rdns.deny_regexps
}

config_haraka_rspamd()
{
	tell_status "configure Haraka rspamd plugin"
	sed -i -e "s/;host.*/host = $JAIL_NET_PREFIX.13/" $HARAKA_CONF/rspamd.ini
	sed -i -e '/spamassassin$/a\
rspamd
' $HARAKA_CONF/plugins
	sed -i -e 's/;always_add_headers = false/always_add_headers = true/' $HARAKA_CONF/rspamd.ini
}

configure_haraka()
{
	tell_status "installing Haraka, stage 2"
	stage_exec haraka -i /usr/local/haraka || exit

	tell_status "configuring Haraka"
	sed -i -e 's/^;listen=\[.*$/listen=0.0.0.0:25,0.0.0.0:465,0.0.0.0:587/' $HARAKA_CONF/smtp.ini
	sed -i -e 's/^;nodes=cpus/nodes=2/' $HARAKA_CONF/smtp.ini
	sed -i -e 's/^;daemonize=true/daemonize=true/' $HARAKA_CONF/smtp.ini
	sed -i -e 's/^;daemon_pid_file/daemon_pid_file/' $HARAKA_CONF/smtp.ini
	sed -i -e 's/^;daemon_log_file/daemon_log_file/' $HARAKA_CONF/smtp.ini
	echo 'LOGINFO' > $HARAKA_CONF/loglevel

	echo '3' > $HARAKA_CONF/tarpit.timeout

	sed -i -e 's/^#process_title$/process_title/' $HARAKA_CONF/plugins
	sed -i -e 's/^#spf$/spf/' $HARAKA_CONF/plugins
	sed -i -e 's/^#bounce$/bounce/' $HARAKA_CONF/plugins
	sed -i -e 's/^#data.uribl$/data.uribl/' $HARAKA_CONF/plugins
	sed -i -e 's/^#attachment$/attachment/' $HARAKA_CONF/plugins
	sed -i -e 's/^#dkim_sign$/dkim_sign/' $HARAKA_CONF/plugins
	sed -i -e 's/^#karma$/karma/' $HARAKA_CONF/plugins
	sed -i -e 's/^# connect.fcrdns/connect.fcrdns/' $HARAKA_CONF/plugins

	config_haraka_syslog
	config_haraka_vpopmail
	config_haraka_qmail_deliverable
	config_haraka_dnsbl

	sed -i -e 's/^; reject=.*/reject=no/' $HARAKA_CONF/data.headers.ini
	sed -i -e 's/^disabled = true/disabled = false/' $HARAKA_CONF/dkim_sign.ini

	tell_status "enable Haraka HTTP server"
	sed -i -e 's/; listen=\[::\]:80/listen=0.0.0.0:80/' $HARAKA_CONF/http.ini

	config_haraka_tls
	config_haraka_p0f
	config_haraka_spamassassin
	config_haraka_avg
	config_haraka_clamav
	config_haraka_rspamd

	install_geoip_dbs
	cleanup_deprecated_haraka
}

start_haraka()
{
	tell_status "starting haraka"
	cp $STAGE_MNT/usr/local/lib/node_modules/Haraka/contrib/bsd-rc.d/haraka $STAGE_MNT/usr/local/etc/rc.d/haraka
	chmod 555 $STAGE_MNT/usr/local/etc/rc.d/haraka
	stage_sysrc haraka_enable=YES
	sysrc -f $STAGE_MNT/etc/rc.conf haraka_flags='-c /usr/local/haraka'
	mkdir -p $STAGE_MNT/usr/local/haraka/queue || exit
	stage_exec service haraka start || exit
}

test_haraka()
{
	tell_status "waiting for Haraka to start listeners"
	sleep 3

	tell_status "testing Haraka"
	stage_exec sockstat -l -4 | grep :25 || exit
	echo "it worked"
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_staged_fs haraka
stage_sysrc hostname=haraka
add_devfs_rule
start_staged_jail
install_haraka
configure_haraka
start_haraka
test_haraka
promote_staged_jail haraka
