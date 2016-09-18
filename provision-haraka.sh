#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA="devfs_ruleset=7"
export JAIL_CONF_EXTRA="
		devfs_ruleset = 7;
		mount += \"$ZFS_DATA_MNT/haraka \$path/data nullfs rw 0 0\";"

HARAKA_CONF="$ZFS_DATA_MNT/haraka/config"

haraka_github_updates() {
	tell_status "updating files from GitHub repo"
	local _ghi="$STAGE_MNT/usr/local/lib/node_modules/Haraka"
	local _ghu='https://raw.githubusercontent.com/haraka/Haraka/master'

	# remove after Haraka v2.8.0 release
	for f in plugins.js plugins/watch/index.js plugins/watch/package.json plugins/dkim_verify.js outbound.js
	do
		echo "fetching $f"
		fetch -o "$_ghi/$f" "$_ghu/$f"
	done
}

install_haraka()
{
	tell_status "installing node & npm"
	stage_pkg_install node npm gmake || exit
	#stage_exec make -C /usr/ports/www/npm install clean

	tell_status "installing Haraka"
	stage_exec pkg install -y git

	#stage_exec npm install -g Haraka ws express || exit

	# install modern-syslog from github until a npm release > 1.1.3 is published
	stage_exec npm install -g strongloop/modern-syslog Haraka ws express || exit

	#haraka_github_updates
}

install_geoip_dbs()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/geoip"; then
		tell_status "GeoIP jail not present, SKIPPING geoip plugin"
		return
	fi

	if ! grep -qs ^connect.geoip "$HARAKA_CONF/plugins"; then
		tell_status "enabling Haraka geoip plugin"
		sed -i .bak -e 's/^# connect.geoip/connect.geoip/' "$HARAKA_CONF/plugins"
	fi

	mkdir -p "$STAGE_MNT/usr/local/share/GeoIP"
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
		sed -i '' -e "s/ bce1 / $PUBLIC_NIC /" "$_start" || exit
	fi

	stage_sysrc p0f_enable=YES
	stage_exec service p0f start
}

config_haraka_syslog()
{
	if ! grep -qs ^log.syslog "$HARAKA_CONF/plugins"; then
		tell_status "enable logging to syslog"
		sed -i '' -e 's/# log.syslog$/log.syslog/' "$HARAKA_CONF/plugins"
	fi

	if ! grep -qs daemon_log_file "$HARAKA_CONF/smtp.ini"; then
		if [ ! -f "$HARAKA_CONF/smtp.ini" ]; then
			tee "$HARAKA_CONF/smtp.ini" <<EO_DLF
daemon_log_file=/dev/null/
EO_DLF
		else
			# send haraka logs to /dev/null
			sed -i '' -e 's/^daemon_log_file=.*/daemon_log_file=\/dev\/null/' "$HARAKA_CONF/smtp.ini"
		fi
	fi

	# TODO: enable this after modern-syslog works with node v6
# 	if ! grep  -qs always_ok "$HARAKA_CONF/log.syslog.ini"; then
# 		# don't write to daemon_log_file if syslog write was successful
# 		echo "[general]
# always_ok=true" | tee -a "$HARAKA_CONF/log.syslog.ini"
# 	fi
}

config_haraka_smtp_forward()
{
	if [ ! -f "$HARAKA_CONF/smtp_forward.ini" ]; then
		tell_status "configure smtp forward to vpopmail jail"
		echo "host=$(get_jail_ip vpopmail)
port=25
" | tee -a "$HARAKA_CONF/smtp_forward.ini"
	fi
}

config_haraka_vpopmail()
{
	if [ ! -f "$HARAKA_CONF/auth_vpopmaild.ini" ]; then
		tell_status "config SMTP AUTH using vpopmaild"
		echo "host=$(get_jail_ip vpopmail)" > "$HARAKA_CONF/auth_vpopmaild.ini"
	fi

	if ! grep -qs ^auth_vpopmaild "$HARAKA_CONF/plugins"; then
		tell_status "enabling vpopmaild plugin"
"$HARAKA_CONF/plugins"
		# shellcheck disable=1004
		sed -i '.bak' \
		    -e '/^# auth\/auth_ldap$/a\
auth\/auth_vpopmaild
' "$HARAKA_CONF/plugins"
	fi
}

config_haraka_qmail_deliverable()
{
	if [ ! -f "$HARAKA_CONF/rcpt_to.qmail_deliverable.ini" ]; then
		tell_status "config recipient validation with Qmail::Deliverable"
		echo "check_outbound=true
host=$(get_jail_ip vpopmail)" | \
		tee -a "$HARAKA_CONF/rcpt_to.qmail_deliverable.ini"
	fi

	sed -i .bak \
		-e 's/^#rcpt_to.qmail_deliverable/rcpt_to.qmail_deliverable/' \
		-e 's/^rcpt_to.in_host_list/# rcpt_to.in_host_list/' \
		"$HARAKA_CONF/plugins"
}

config_haraka_p0f()
{
	install_p0f

	if ! grep -qs ^connect.p0f "$HARAKA_CONF/plugins"; then
		tell_status "enable Haraka p0f plugin"
		sed -i '' -e 's/^# connect.p0f/connect.p0f/' "$HARAKA_CONF/plugins"
	fi
}

config_haraka_spamassassin()
{
	if [ ! -d "$ZFS_JAIL_MNT/spamassassin" ]; then
		tell_status "skipping spamassassin setup, no jail exists"
		return
	fi

	tell_status "enabling Haraka spamassassin plugin"
	sed -i '' -e 's/^#spamassassin$/spamassassin/' "$HARAKA_CONF/plugins"

	if [ ! -f "$HARAKA_CONF/spamassassin.ini" ]; then
		tell_status "configuring Haraka spamassassin plugin"
		echo "spamd_socket=$(get_jail_ip spamassassin):783
old_headers_action=rename
spamd_user=first-recipient
reject_threshold=10
relay_reject_threshold=7
" | tee -a "$HARAKA_CONF/spamassassin.ini"
	fi
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

	if ! grep -qs ^host "$HARAKA_CONF/avg.ini"; then
		echo "host = $(get_jail_ip avg)
tmpdir=/data/avg
" | tee -a "$HARAKA_CONF/avg.ini"
	fi

	if ! grep -q ^avg "$HARAKA_CONF/plugins"; then
		tell_status "enabling avg plugin"
		# shellcheck disable=1004
		sed -i '' -e '/clamd$/a\
avg
' "$HARAKA_CONF/plugins"
	fi
}

config_haraka_clamav()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/clamav"; then
		tell_status "WARNING: skipping clamav plugin, no clamav jail exists"
		return
	fi

	if ! grep -qs ^clamd "$HARAKA_CONF/plugins"; then
		tell_status "enabling Haraka clamav plugin"
		sed -i '' -e 's/^#clamd$/clamd/' "$HARAKA_CONF/plugins"
	fi

	if ! grep -qs ^clamd_socket "$HARAKA_CONF/clamd.ini"; then
		tell_status "configure Haraka clamav plugin"
		echo "clamd_socket=$(get_jail_ip clamav):3310

[reject]
virus=true
error=false
DetectBrokenExecutables=false
Structured=false
ArchiveBlockEncrypted=false
PUA=false
OLE2=false
Safebrowsing=false
UNOFFICIAL=false
Phishing=false
" | tee -a "$HARAKA_CONF/clamd.ini"
	fi
}

config_haraka_tls() {
	if ! grep -qs ^tls "$HARAKA_CONF/plugins"; then
		tell_status "enable TLS encryption"
		sed -i '' -e 's/^# tls$/tls/' "$HARAKA_CONF/plugins"
	fi

	if [ ! -f "$HARAKA_CONF/tls_cert.pem" ]; then
		tell_status "installing TLS certificate"
		cp /etc/ssl/certs/server.crt "$HARAKA_CONF/tls_cert.pem"
		cp /etc/ssl/private/server.key "$HARAKA_CONF/tls_key.pem"
	fi
}

config_haraka_dnsbl()
{
	if ! grep -qs ^reject "$HARAKA_CONF/dnsbl.ini"; then
		tell_status "configuring dnsbls"
		echo 'reject=false
search=all
enable_stats=false
zones=b.barracudacentral.org, truncate.gbudb.net, psbl.surriel.com, bl.spamcop.net, dnsbl-1.uceprotect.net, zen.spamhaus.org, dnsbl.sorbs.net, dnsbl.justspam.org, bad.psky.me
' | tee -a "$HARAKA_CONF/dnsbl.ini"
	fi
}

config_haraka_rspamd()
{
	if [ ! -d "$ZFS_JAIL_MNT/rspamd" ]; then
		tell_status "skipping rspamd, no jail exists"
		return
	fi

	if ! grep -qs ^host "$HARAKA_CONF/rspamd.ini"; then
		tell_status "configure Haraka rspamd plugin"
		echo "host = $(get_jail_ip rspamd)
always_add_headers = true
" | tee -a "$HARAKA_CONF/rspamd.ini" || exit
	fi

	if ! grep -qs ^rspamd "$HARAKA_CONF/plugins"; then
		tell_status "enabling rspamd plugin"
		# shellcheck disable=1004
		sed -i '' -e '/spamassassin$/a\
rspamd
' "$HARAKA_CONF/plugins" || exit
	fi
}

config_haraka_watch()
{
	if ! grep -qs ^watch "$HARAKA_CONF/plugins"; then
		tell_status "enabling watch plugin"
		echo 'watch' >> "$HARAKA_CONF/plugins" || exit
	fi

	if [ ! -f "$HARAKA_CONF/watch.ini" ]; then
		echo '[wss]' > "$HARAKA_CONF/watch.ini"
	fi

	local _libdir="$STAGE_MNT/usr/local/lib/node_modules/Haraka/plugins/watch"
	sed -i .bak \
		-e '/^var rcpt_to_plugins/ s/in_host_list/qmail_deliverable/' \
		-e "/^var data_plugins/ s/uribl/uribl', 'limit/; s/clamd/clamd', 'avg/" \
		"$_libdir/html/client.js"
}

config_haraka_smtp_ini()
{
	if [ ! -f "$HARAKA_CONF/smtp.ini" ]; then
		config_install_default smtp.ini
	fi

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
	if [ ! -f "$HARAKA_CONF/plugins" ]; then
		config_install_default plugins
	fi

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

config_install_default()
{
	local _source="$STAGE_MNT/usr/local/lib/node_modules/Haraka/config"
	echo "cp $_source/$1 $HARAKA_CONF/$1"
	cp "$_source/$1" "$HARAKA_CONF/$1"
}

config_haraka_limit()
{
	if ! grep -qs ^limit "$HARAKA_CONF/plugins"; then
		tell_status "enabling limit plugin"
		sed -i .bak \
			-e 's/^max_unrecognized_commands/limit/' \
			"$HARAKA_CONF/plugins"
	fi

	if [ ! -f "$HARAKA_CONF/limit.ini" ]; then
		config_install_default limit.ini
		sed -i .bak \
			-e 's/^; max/max/' \
			-e 's/^; history/history/' \
			-e 's/^; backend=ram/backend=redis/' \
			-e 's/^; discon/discon/' \
			"$HARAKA_CONF/limit.ini"
	fi
}

config_haraka_dkim()
{
	if [ ! -f "$HARAKA_CONF/dkim_sign.ini" ]; then
		tell_status "enabling dkim_sign plugin"
		echo 'disabled=false' | tee -a "$HARAKA_CONF/dkim_sign.ini"
	fi

	if [ ! -d "$HARAKA_CONF/dkim" ]; then
		mkdir -p "$HARAKA_CONF/dkim"
	fi

	if [ ! -f "$HARAKA_CONF/dkim/dkim_key_gen.sh" ]; then
		config_install_default "dkim/dkim_key_gen.sh"
	fi

	if [ ! -d "$HARAKA_CONF/dkim/$TOASTER_MAIL_DOMAIN" ]; then
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
	if [ -f "$HARAKA_CONF/karma.ini" ]; then
		return
	fi

	tell_status "configuring karma plugin"
	echo "
[redis]
dbid=1
server_ip=$(get_jail_ip redis)

[deny_excludes]
plugins=send_email, access, helo.checks, data.headers, mail_from.is_resolvable, avg, limit, attachment, tls
" | tee -a "$HARAKA_CONF/karma.ini"

}

config_haraka_redis()
{
	if ! grep -qs ^redis "$HARAKA_CONF/plugins"; then
		tell_status "enabling redis plugin"
		echo 'redis' | tee -a "$HARAKA_CONF/plugins"
	fi

	if [ ! -f "$HARAKA_CONF/redis.ini" ]; then
		echo "configuring redis plugin"
		tee "$HARAKA_CONF/redis.ini" <<EO_REDIS_CONF
[server]
host=$(get_jail_ip redis)
; port=6379
db=3
EO_REDIS_CONF
	fi
}

config_haraka_geoip() {
	if ! grep -qs ^calc_distance "$HARAKA_CONF/connect.geoip.ini"; then
		tell_status "enabling geoip distance"
		echo "calc_distance=true
[asn]
report_as=connect.asn
" | tee -a "$HARAKA_CONF/connect.geoip.ini"
	fi
}

config_haraka_http()
{
	if [ ! -f "$HARAKA_CONF/http.ini" ]; then
		tell_status "enable Haraka HTTP server"
		echo "listen=0.0.0.0:80" | tee -a "$HARAKA_CONF/http.ini"
	fi
}

configure_haraka()
{
	tell_status "installing Haraka, stage 2"
	stage_exec haraka -i /data || exit

	tell_status "configuring Haraka"
	echo 'LOGINFO' > "$HARAKA_CONF/loglevel"
	if [ ! -f "$HARAKA_CONF/tarpit.timeout" ]; then
		echo '3' > "$HARAKA_CONF/tarpit.timeout"
	fi

	if [ ! -f "$HARAKA_CONF/plugins" ]; then
		config_install_default plugins
	fi
	config_haraka_smtp_ini
	config_haraka_plugins
	config_haraka_limit
	config_haraka_syslog
	config_haraka_vpopmail
	config_haraka_smtp_forward
	config_haraka_qmail_deliverable
	config_haraka_dnsbl

	if [ ! -f "$HARAKA_CONF/data.headers.ini" ]; then
		echo "reject=no" | tee -a "$HARAKA_CONF/data.headers.ini"
	fi

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
}

start_haraka()
{
	tell_status "starting haraka"
	cp "$STAGE_MNT/usr/local/lib/node_modules/Haraka/contrib/bsd-rc.d/haraka" \
		"$STAGE_MNT/usr/local/etc/rc.d/haraka"
	chmod 555 "$STAGE_MNT/usr/local/etc/rc.d/haraka"
	stage_sysrc haraka_enable=YES
	sysrc -f "$STAGE_MNT/etc/rc.conf" haraka_flags='-c /data'

	if [ ! -d "$HARAKA_CONF/queue" ]; then
		mkdir -p "$HARAKA_CONF/queue" || exit
	fi

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
