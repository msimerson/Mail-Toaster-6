#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA="devfs_ruleset=7"
export JAIL_CONF_EXTRA="
		devfs_ruleset = 7;"

HARAKA_CONF="$STAGE_MNT/usr/local/haraka/config"

install_haraka()
{
	tell_status "installing node & npm"
	stage_pkg_install node npm gmake || exit

	tell_status "installing Haraka"
	stage_exec npm install -g Haraka ws express || exit

	tell_status "updating files from GitHub repo"
	local _ghi="$STAGE_MNT/usr/local/lib/node_modules/Haraka"
	local _ghu='https://raw.githubusercontent.com/haraka/Haraka/master'

	# remove after Haraka > 2.7.2 release
	for f in plugins/spamassassin.js plugins/karma.js plugins/redis.js plugins/rspamd.js plugins/watch/index.js plugins/watch/html/client.js plugins/connect.geoip.js plugins/connect.p0f.js
	do
		echo "fetching $f"
		fetch -o "$_ghi/$f" "$_ghu/$f"
	done
}

install_geoip_dbs()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/geoip"; then
		tell_status "GeoIP jail not present, SKIPPING geoip plugin"
		return
	fi

	tell_status "enabling Haraka geoip plugin"
	mkdir -p "$STAGE_MNT/usr/local/share/GeoIP"
	sed -i -e 's/^;calc_distance=false/calc_distance=true/' "$HARAKA_CONF/connect.geoip.ini"
	sed -i -e 's/^# connect.geoip/connect.geoip/' "$HARAKA_CONF/plugins"

	JAIL_CONF_EXTRA="$JAIL_CONF_EXTRA
		mount += \"$ZFS_DATA_MNT/geoip \$path/usr/local/share/GeoIP nullfs ro 0 0\";"
}

add_devfs_rule()
{
	if grep -qs devfsrules_jail_bpf /etc/devfs.rules; then
		tell_status "devfs BPF ruleset already present"
		return
	fi

	tell_status "installing devfs ruleset for p0f"
	tee -a /etc/devfs.rules <<EO_DEVFS
[devfsrules_jail_bpf=7]
add include \$devfsrules_hide_all
add include \$devfsrules_unhide_basic
add include \$devfsrules_unhide_login
add path zfs unhide
add path 'bpf*' unhide
EO_DEVFS

}

install_p0f()
{
	tell_status "install p0f"
	stage_pkg_install p0f

	tell_status "installing p0f startup file"
	mkdir -p "$STAGE_MNT/usr/local/etc/rc.d"
	local _start="$STAGE_MNT/usr/local/etc/rc.d/p0f"
	cp "$STAGE_MNT/usr/local/lib/node_modules/Haraka/contrib/bsd-rc.d/p0f" "$_start" || exit
	chmod 755 "$_start" || exit

	get_public_facing_nic
	if [ "$PUBLIC_NIC" != "bce1" ]; then
		sed -i -e "s/ bce1 / $PUBLIC_NIC /" "$_start" || exit
	fi

	stage_sysrc p0f_enable=YES
	stage_exec service p0f start
}

config_haraka_syslog()
{
	tell_status "switch Haraka logging to syslog"
	sed -i -e 's/# log.syslog$/log.syslog/' "$HARAKA_CONF/plugins"
	# sed -i -e 's/^daemon_log_file=.*/daemon_log_file=\/dev\/null/' "$HARAKA_CONF/smtp.ini"
	sed -i -e 's/always_ok=false/always_ok=true/' "$HARAKA_CONF/log.syslog.ini"
}

config_haraka_vpopmail()
{
	tell_status "configure smtp forward to vpopmail jail"
	sed -i .bak \
		-e "s/^host=localhost/host=$(get_jail_ip vpopmail)/" \
		-e 's/^port=2555/port=25/' \
		"$HARAKA_CONF/smtp_forward.ini"

	tell_status "config SMTP AUTH using vpopmaild"
	echo "host=$(get_jail_ip vpopmail)" > "$HARAKA_CONF/auth_vpopmaild.ini"

	# shellcheck disable=1004
	sed -i -e '/^# auth\/auth_ldap$/a\
auth\/auth_vpopmaild
' "$HARAKA_CONF/plugins"
}

config_haraka_qmail_deliverable()
{
	tell_status "config recipient validation with Qmail::Deliverable"
	sed -i -e "s/^host=127.0.0.1/host=$(get_jail_ip vpopmail)/" "$HARAKA_CONF/rcpt_to.qmail_deliverable.ini"
	sed -i .bak \
		-e 's/^#rcpt_to.qmail_deliverable/rcpt_to.qmail_deliverable/' \
		-e 's/^rcpt_to.in_host_list/# rcpt_to.in_host_list/' \
		"$HARAKA_CONF/plugins"
}

config_haraka_p0f()
{
	install_p0f

	tell_status "enable Haraka p0f plugin"
	sed -i -e 's/^# connect.p0f/connect.p0f/' "$HARAKA_CONF/plugins"
}

config_haraka_spamassassin()
{
	if [ ! -d "$ZFS_JAIL_MNT/spamassassin" ]; then
		tell_status "skipping spamassassin setup, no jail exists"
		return
	fi

	tell_status "configuring Haraka spamassassin plugin"
	sed -i.bak \
		-e "/^spamd_socket/ s/127.0.0.1:/$(get_jail_ip spamassassin):/" \
		-e 's/^;spamd_user=$/spamd_user=first-recipient/' \
		-e '/^; reject_threshold/ s/^; //' \
		-e 's/^; relay_reject_threshold$/relay_reject_threshold/' \
		"$HARAKA_CONF/spamassassin.ini"

	sed -i -e 's/^#spamassassin$/spamassassin/' "$HARAKA_CONF/plugins"
}

config_haraka_avg()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/avg"; then
		echo "AVG not installed, skipping"
		return
	fi

	tell_status "configuring Haraka avg plugin"
	mkdir -p "$STAGE_MNT/data/avg" || exit

	JAIL_CONF_EXTRA="$JAIL_CONF_EXTRA
		mount += \"$ZFS_DATA_MNT/avg \$path/data/avg nullfs rw 0 0\";"

	sed -i .bak \
		-e "s/;host.*/host = $(get_jail_ip avg)/" \
		-e 's/;tmpdir.*/tmpdir=\/data\/avg/' \
		"$HARAKA_CONF/avg.ini"

	# shellcheck disable=1004
	sed -i -e '/clamd$/a\
avg
' "$HARAKA_CONF/plugins"
}

config_haraka_clamav()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/clamav"; then
		tell_status "WARNING: skipping clamav plugin, no clamav jail exists"
		return
	fi

	tell_status "configure Haraka clamav plugin"
	echo "clamd_socket=$(get_jail_ip clamav):3310" >> "$HARAKA_CONF/clamd.ini"
	sed -i -e 's/^#clamd$/clamd/' "$HARAKA_CONF/plugins"
}

config_haraka_tls() {	
	tell_status "enable TLS encryption"
	sed -i -e 's/^# tls$/tls/' "$HARAKA_CONF/plugins"
	cp /etc/ssl/certs/server.crt "$HARAKA_CONF/tls_cert.pem"
	cp /etc/ssl/private/server.key "$HARAKA_CONF/tls_key.pem"
}

config_haraka_dnsbl()
{
	tell_status "configuring dnsbls"
	echo 'reject=0' > "$HARAKA_CONF/dnsbl.ini"
	echo 'periodic_checks=30' >> "$HARAKA_CONF/dnsbl.ini"

	echo "; zen.spamhaus.org
b.barracudacentral.org
truncate.gbudb.net
cbl.abuseat.org
psbl.surriel.com
bl.spamcop.net
dnsbl-1.uceprotect.net
pbl.spamhaus.org
xbl.spamhaus.org
" | tee "$HARAKA_CONF/dnsbl.zones"
}

cleanup_deprecated_haraka()
{
	rm "$HARAKA_CONF/lookup_rdns.strict.ini"
	rm "$HARAKA_CONF/lookup_rdns.strict.timeout"
	rm "$HARAKA_CONF/lookup_rdns.strict.whitelist"
	rm "$HARAKA_CONF/lookup_rdns.strict.whitelist_regex"
	rm "$HARAKA_CONF/mail_from.access.blacklist_regex"
	rm "$HARAKA_CONF/rcpt_to.blocklist"
	rm "$HARAKA_CONF/rdns.allow_regexps"
	rm "$HARAKA_CONF/rdns.deny_regexps"
}

config_haraka_rspamd()
{
	if [ ! -d "$ZFS_JAIL_MNT/rspamd" ]; then
		tell_status "skipping rspamd, no jail exists"
		return
	fi

	tell_status "configure Haraka rspamd plugin"
	sed -i .bak \
		-e "s/;host.*/host = $(get_jail_ip rspamd)/" \
		-e 's/;always_add_headers = false/always_add_headers = true/' \
		"$HARAKA_CONF/rspamd.ini" || exit

	# shellcheck disable=1004
	sed -i -e '/spamassassin$/a\
rspamd
' "$HARAKA_CONF/plugins" || exit
}

config_haraka_watch()
{
	echo 'watch' >> "$HARAKA_CONF/plugins" || exit

	local _libdir="$STAGE_MNT/usr/local/lib/node_modules/Haraka/plugins/watch"
	sed -i .bak \
		-e '/^var rcpt_to_plugins/ s/in_host_list/qmail_deliverable/' \
		-e "/^var data_plugins/ s/uribl/uribl', 'limit/; s/clamd/clamd', 'avg/" \
		"$_libdir/html/client.js"
}

config_haraka_smtp_ini()
{
	sed -i .bak \
		-e 's/^;listen=\[.*$/listen=0.0.0.0:25,0.0.0.0:465,0.0.0.0:587/' \
		-e 's/^;nodes=cpus/nodes=2/' \
		-e 's/^;daemonize=true/daemonize=true/' \
		-e 's/^;daemon_pid_file/daemon_pid_file/' \
		-e 's/^;daemon_log_file/daemon_log_file/' \
		"$HARAKA_CONF/smtp.ini" || exit
}

config_haraka_plugins()
{
	# enable a bunch of plugins
	sed -i .bak \
		-e 's/^#process_title$/process_title/' \
		-e 's/^#spf$/spf/' \
		-e 's/^#bounce$/bounce/' \
		-e 's/^#data.uribl$/data.uribl/' \
		-e 's/^#attachment$/attachment/' \
		-e 's/^#dkim_sign$/dkim_sign/' \
		-e 's/^#karma$/karma/' \
		-e 's/^# connect.fcrdns/connect.fcrdns/' \
		"$HARAKA_CONF/plugins"
}

config_haraka_limit()
{
	tell_status "configuring limit plugin"
	sed -i .bak \
		-e 's/^max_unrecognized_commands/limit/' \
		"$HARAKA_CONF/plugins"

	sed -i .bak \
		-e 's/^; max/max/' \
		-e 's/^; history/history/' \
		-e 's/^; backend=ram/backend=redis/' \
		-e 's/^; discon/discon/' \
		"$HARAKA_CONF/limit.ini"
}

config_haraka_dkim()
{
	sed -i .bak -e 's/^disabled = true/disabled = false/' \
		"$HARAKA_CONF/dkim_sign.ini"

	_dkim_dir="$ZFS_JAIL_MNT/haraka/usr/local/haraka/config/dkim/$TOASTER_MAIL_DOMAIN"
	if [ -d "$_dkim_dir" ]; then
		tell_status "copying active DKIM keys"
		cp -R "$_dkim_dir/" "$HARAKA_CONF/dkim/"
		return
	else
		tell_status "generating DKIM keys"
		cd "$HARAKA_CONF/dkim" || exit
		sh dkim_key_gen.sh "$TOASTER_MAIL_DOMAIN"
		cat "$HARAKA_CONF/dkim/$TOASTER_MAIL_DOMAIN/dns"

		tell_status "NOTICE: action required for DKIM validation. See message ^^^"
		sleep 5
	fi
}

config_haraka_karma()
{
	sed -i .bak \
		-e '/^dbid/ s/= 0/= 1/' \
		-e "/^server_ip/ s/127.0.0.1/$(get_jail_ip redis)/" \
		-e '/^plugins=/ s/clamd, //' \
		"$HARAKA_CONF/karma.ini"
}

config_haraka_redis()
{
	tell_status "configuring redis plugin"
	echo 'redis' | tee -a "$HARAKA_CONF/plugins"
	tee "$HARAKA_CONF/redis.ini" <<EO_REDIS_CONF
[server]
host=$(get_jail_ip redis)
; port=6379
db=3
EO_REDIS_CONF
}

config_haraka_geoip() {
	sed -i .bak \
		-e '/^;[asn]/ s/^;//' \
		-e '/^;report_as=/ s/^;//' \
		"$HARAKA_CONF/connect.geoip.ini"
}

config_haraka_http()
{
	tell_status "enable Haraka HTTP server"
	sed -i -e 's/; listen=\[::\]:80/listen=0.0.0.0:80/' "$HARAKA_CONF/http.ini"
}

configure_haraka()
{
	tell_status "installing Haraka, stage 2"
	stage_exec haraka -i /usr/local/haraka || exit

	tell_status "configuring Haraka"
	echo 'LOGINFO' > "$HARAKA_CONF/loglevel"
	echo '3' > "$HARAKA_CONF/tarpit.timeout"

	config_haraka_smtp_ini
	config_haraka_plugins
	config_haraka_limit
	config_haraka_syslog
	config_haraka_vpopmail
	config_haraka_qmail_deliverable
	config_haraka_dnsbl

	sed -i -e 's/^; reject=.*/reject=no/' "$HARAKA_CONF/data.headers.ini"

	config_haraka_http
	config_haraka_tls
	config_haraka_dkim
	config_haraka_p0f
	config_haraka_spamassassin
	config_haraka_rspamd
	config_haraka_clamav
	config_haraka_avg
	config_haraka_watch
	config_haraka_karma
	config_haraka_redis
	config_haraka_geoip

	install_geoip_dbs
	cleanup_deprecated_haraka
}

start_haraka()
{
	tell_status "starting haraka"
	cp "$STAGE_MNT/usr/local/lib/node_modules/Haraka/contrib/bsd-rc.d/haraka" \
		"$STAGE_MNT/usr/local/etc/rc.d/haraka"
	chmod 555 "$STAGE_MNT/usr/local/etc/rc.d/haraka"
	stage_sysrc haraka_enable=YES
	sysrc -f "$STAGE_MNT/etc/rc.conf" haraka_flags='-c /usr/local/haraka'
	mkdir -p "$STAGE_MNT/usr/local/haraka/queue" || exit
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

preinstall_checks() {
	base_snapshot_exists || exit

	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/redis"; then
		tell_status "FATAL: redis jail required but not provisioned."
		exit
	fi
}

preinstall_checks
create_staged_fs haraka
add_devfs_rule
start_staged_jail haraka
install_haraka
configure_haraka
start_haraka
test_haraka
promote_staged_jail haraka
