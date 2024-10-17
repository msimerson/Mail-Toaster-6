#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA="devfs_ruleset=7"
export JAIL_CONF_EXTRA="
		devfs_ruleset = 7;"
export JAIL_FSTAB=""

HARAKA_CONF="$ZFS_DATA_MNT/haraka/config"

install_haraka()
{
	tell_status "installing node & npm"
	stage_pkg_install npm-node20 gmake pkgconf git-tiny
	if [ "$BOURNE_SHELL" != "bash" ]; then
		tell_status "Install bash since not in base"
		stage_pkg_install bash
	fi
	# export PYTHON=/usr/local/bin/python3
	# stage_exec ln -s /usr/local/bin/python3 /usr/local/bin/python
	# stage_exec npm install -g --omit=dev node-gyp

	# Workaround for NPM bug https://github.com/npm/cli/issues/2610
	stage_exec bash -c 'git config --global url."https://github.com/".insteadOf git@github.com:'
	stage_exec bash -c 'git config --global url."https://".insteadOf git://'

	tell_status "installing Haraka"
	stage_exec bash -c "npm install -g --omit=dev https://github.com/haraka/Haraka.git"

	local _plugins="ws express"
	for _p in log-reader dmarc-perl; do
		_plugins="$_plugins haraka-plugin-$_p"
	done
	stage_exec bash -c "if [ -f /data/package.json ]; then rm /data/package.json; fi"
	stage_exec bash -c "cd /data && npm install --omit=dev $_plugins"
}

install_geoip_dbs()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/geoip"; then
		tell_status "GeoIP jail not present, SKIPPING geoip plugin"
		return
	fi

	local _fstab="$ZFS_DATA_MNT/haraka/etc/fstab"
	for _f in "$_fstab" "$_fstab}.stage"; do
		if ! grep -qs GeoIP "$_f"; then
			tell_status "adding GeoIP volume to $_f"
			tee -a "$_f" <<EO_GEOIP
$ZFS_DATA_MNT/geoip/db $ZFS_JAIL_MNT/haraka/usr/local/share/GeoIP nullfs rw 0 0"
EO_GEOIP
		fi
	done

	if ! grep -qs ^geoip "$HARAKA_CONF/plugins"; then
		tell_status "enabling Haraka geoip plugin"
		sed -i.bak -e '/^# geoip/ s/# //' "$HARAKA_CONF/plugins"
	fi
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
	cp "$STAGE_MNT/usr/local/lib/node_modules/Haraka/node_modules/haraka-plugin-p0f/contrib/bsd-rc.d/p0f" "$_start"
	chmod 755 "$_start"

	get_public_facing_nic
	if [ "$PUBLIC_NIC" != "bce1" ]; then
		sed -i '' -e "s/ bce1 / $PUBLIC_NIC /" "$_start"
	fi

	stage_sysrc p0f_enable=YES
	stage_exec service p0f start
}

configure_haraka_syslog()
{
	if ! grep -qs ^syslog "$HARAKA_CONF/plugins"; then
		tell_status "enable logging to syslog"
		sed -i '' -e '/^# syslog$/ s/# //' "$HARAKA_CONF/plugins"
	fi

	if ! grep -qs daemon_log_file "$HARAKA_CONF/smtp.ini"; then
		if [ ! -f "$HARAKA_CONF/smtp.ini" ]; then
			store_config "$HARAKA_CONF/smtp.ini" <<EO_DLF
daemon_log_file=/dev/null
EO_DLF
		else
			# send haraka logs to /dev/null
			sed -i '' -e 's/^daemon_log_file=.*/daemon_log_file=\/dev\/null/' "$HARAKA_CONF/smtp.ini"
		fi
	fi

	store_config "$HARAKA_CONF/log.reader.ini" "overwrite" <<EO_LRC
[log]
file=/var/log/maillog
EO_LRC

	# absense of mailogs in jail prevents log-reader from working
	if ! grep -qs always_ok "$HARAKA_CONF/syslog.ini"; then
		# don't write to daemon_log_file if syslog write was successful
		echo "[general]
always_ok=true" | tee -a "$HARAKA_CONF/syslog.ini"
	fi

	# send Haraka logs to haraka's /var/log so log-reader can access them
	store_config "$STAGE_MNT/etc/syslog.conf" "overwrite" <<EO_SYSLOG
mail.info					/var/log/maillog
#*.*			@syslog
EO_SYSLOG

	touch "$STAGE_MNT/var/log/maillog"
}

configure_haraka_smtp_forward()
{
	if [ ! -f "$HARAKA_CONF/smtp_forward.ini" ]; then
		tell_status "configure smtp forward to vpopmail jail"
		echo "host=$(get_jail_ip vpopmail)
port=25
" | tee -a "$HARAKA_CONF/smtp_forward.ini"
	fi
}

configure_haraka_vpopmail()
{
	if [ ! -f "$HARAKA_CONF/auth_vpopmaild.ini" ]; then
		tell_status "config SMTP AUTH using vpopmaild"
		echo "host=$(get_jail_ip vpopmail)" > "$HARAKA_CONF/auth_vpopmaild.ini"
	fi

	if ! grep -qs ^auth/auth_vpopmaild "$HARAKA_CONF/plugins"; then
		tell_status "enabling vpopmaild plugin"

		# shellcheck disable=1004
		sed -i.bak \
			-e '/^# auth\/auth_ldap$/a\
auth\/auth_vpopmaild
' "$HARAKA_CONF/plugins"
	fi
}

configure_haraka_qmail_deliverable()
{
	if [ ! -f "$HARAKA_CONF/qmail-deliverable.ini" ]; then
		tell_status "config recipient validation with Qmail::Deliverable"
		echo "check_outbound=true
host=$(get_jail_ip vpopmail)
queue=smtp_forward" | \
			tee -a "$HARAKA_CONF/qmail-deliverable.ini"
	fi

	if ! grep -qs ^qmail-deliverable "$HARAKA_CONF/plugins"; then
		tell_status "enabling qmail-deliverable plugin"
		sed -i.bak \
			-e '/^#qmail-deliverable/ s/#//' \
			-e '/^#rcpt_to.qmail_deliverable/ s/#.*/qmail-deliverable/' \
			-e 's/^rcpt_to.in_host_list/# rcpt_to.in_host_list/' \
			"$HARAKA_CONF/plugins"
	fi
}

configure_haraka_p0f()
{
	install_p0f

	if ! grep -qs ^socket_path "$HARAKA_CONF/p0f.ini"; then
		store_config "$HARAKA_CONF/p0f.ini" "overwrite" <<EO_P0F
[main]
socket_path=/tmp/.p0f_socket
EO_P0F
	fi

	if ! grep -qs ^p0f "$HARAKA_CONF/plugins"; then
		tell_status "enable Haraka p0f plugin"
		sed -i '' \
			-e '/^# p0f/ s/# //' \
			"$HARAKA_CONF/plugins"
	fi
}

configure_haraka_spamassassin()
{
	if [ ! -d "$ZFS_JAIL_MNT/spamassassin" ]; then
		tell_status "skipping spamassassin setup, no jail exists"
		return
	fi

	if ! grep -qs ^spamassasssin "$HARAKA_CONF/plugins"; then
		tell_status "enabling Haraka spamassassin plugin"
		sed -i '' -e '/^#spamassassin/ s/#//' "$HARAKA_CONF/plugins"
	fi

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

configure_haraka_avg()
{
	mkdir -p "$STAGE_MNT/data/avg/spool"

	tell_status "configuring Haraka avg plugin"
	if ! grep -qs ^host "$HARAKA_CONF/avg.ini"; then
		echo "host = $(get_jail_ip avg)
tmpdir=/data/avg/spool
" | tee -a "$HARAKA_CONF/avg.ini"
	fi

	if zfs_filesystem_exists "$ZFS_DATA_VOL/avg"; then
		tell_status "adding avg data FS to Haraka jail"
		JAIL_FSTAB="$JAIL_FSTAB
$ZFS_DATA_MNT/avg   $ZFS_JAIL_MNT/haraka/data/avg nullfs rw 0 0"

		if ! grep -qs spool "$HARAKA_CONF/avg.ini"; then
			tell_status "update tmpdir in avg.ini"
			sed -i.bak -e \
				'/^tmpdir/ s/avg$/avg\/spool/g' \
				"$HARAKA_CONF/avg.ini"
		fi
	else
		echo "AVG data FS missing, not enabling"
		return
	fi

	if ! grep -q ^avg "$HARAKA_CONF/plugins"; then
		if ! jls -j avg | grep -qs avg; then
			echo "AVG not running, not enabling"
			return
		fi

		tell_status "enabling avg plugin"
		# shellcheck disable=1004
		sed -i '' -e '/clamd$/a\
avg
' "$HARAKA_CONF/plugins"
	fi
}

configure_haraka_clamav()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/clamav"; then
		tell_status "WARNING: skipping clamav plugin, no clamav jail exists"
		return
	fi

	if ! grep -qs ^clamd "$HARAKA_CONF/plugins"; then
		tell_status "enabling Haraka clamav plugin"
		sed -i '' -e '/^#clamd/ s/#//' "$HARAKA_CONF/plugins"
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

configure_haraka_tls() {
	if ! grep -qs ^tls "$HARAKA_CONF/plugins"; then
		tell_status "enable TLS encryption"
		sed -i '' -e '/^# tls$/ s/# //' "$HARAKA_CONF/plugins"
	fi

	if [ -d "$HARAKA_CONF/tls" ]; then
		local _installed="$HARAKA_CONF/tls/${TOASTER_HOSTNAME}.pem"
	else
		local _installed="$HARAKA_CONF/tls_cert.pem"
	fi

	if [ -f "$_installed" ]; then
		return
	fi

	if [ ! -f /etc/ssl/private/server.key ]; then
		return
	fi
	if [ ! -f /etc/ssl/certs/server.crt ]; then
		return
	fi

	tell_status "installing TLS certificate"
	if [ -d "$HARAKA_CONF/tls" ]; then
		cat /etc/ssl/private/server.key > "$_installed"
		cat /etc/ssl/certs/server.crt >> "$_installed"
	else
		cp /etc/ssl/certs/server.crt "$_installed"
		cp /etc/ssl/private/server.key "$HARAKA_CONF/tls_key.pem"
	fi
}

configure_haraka_dnsbl()
{
	if ! grep -qs ^reject "$HARAKA_CONF/dnsbl.ini"; then
		tell_status "configuring dnsbls"
		echo 'reject=false
search=all
enable_stats=false
zones=b.barracudacentral.org, truncate.gbudb.net, psbl.surriel.com, bl.spamcop.net, dnsbl-1.uceprotect.net, zen.spamhaus.org, dnsbl.sorbs.net, dnsbl.justspam.org
' | tee -a "$HARAKA_CONF/dnsbl.ini"
	fi
}

configure_haraka_rspamd()
{
	if [ ! -d "$ZFS_JAIL_MNT/rspamd" ]; then
		tell_status "skipping rspamd, no jail exists"
		return
	fi

	if ! grep -qs ^host "$HARAKA_CONF/rspamd.ini"; then
		tell_status "configure Haraka rspamd plugin"
		echo "host = $(get_jail_ip rspamd)
add_headers = always
" | tee -a "$HARAKA_CONF/rspamd.ini"
	fi

	if ! grep -qs ^rspamd "$HARAKA_CONF/plugins"; then
		tell_status "enabling rspamd plugin"
		# shellcheck disable=1004
		sed -i '' -e '/spamassassin$/a\
rspamd
' "$HARAKA_CONF/plugins"
	fi
}

configure_haraka_watch()
{
	if ! grep -qs ^watch "$HARAKA_CONF/plugins"; then
		tell_status "enabling watch plugin"
		echo 'watch' >> "$HARAKA_CONF/plugins"
	fi

	if [ ! -f "$HARAKA_CONF/watch.ini" ]; then
		echo '[wss]' > "$HARAKA_CONF/watch.ini"
	fi
}

configure_haraka_smtp_ini()
{
	if [ ! -f "$HARAKA_CONF/smtp.ini" ]; then
		configure_install_default smtp.ini
	fi

	sed -i.bak \
		-e 's/^;listen=\[.*$/listen=[::0]:25,[::0]:465,[::0]:587/' \
		-e 's/^;nodes=cpus/nodes=2/' \
		-e 's/^;daemonize=true/daemonize=true/' \
		-e 's/^;daemon_pid_file/daemon_pid_file/' \
		-e 's/^;daemon_log_file/daemon_log_file/' \
		"$HARAKA_CONF/smtp.ini"
}

configure_haraka_outbound_ini()
{
	if [ ! -f "$HARAKA_CONF/outbound.ini" ]; then
		configure_install_default outbound.ini
	fi

	if grep -q ^local_mx_ok "$HARAKA_CONF/outbound.ini"
	then
		tell_status "preserving local_mx_ok in outbound.ini"
	else
		tell_status "setting local_mx_ok in outbound.ini"
		echo 'local_mx_ok=true' >> "$HARAKA_CONF/outbound.ini"
	fi
}

configure_haraka_plugins()
{
	if [ ! -f "$HARAKA_CONF/plugins" ]; then
		configure_install_default plugins
	fi

	# enable a bunch of plugins
	sed -i.bak \
		-e '/^#process_title/ s/#//' \
		-e '/^#spf$/ s/#//' \
		-e '/^#bounce/ s/#//' \
		-e '/^#data.uribl/ s/#data\.//' \
		-e '/^#uribl/ s/#//' \
		-e '/^#attachment/ s/#//' \
		-e '/^#dkim_sign/ s/#//' \
		-e '/^#karma$/ s/#//' \
		-e '/^# fcrdns/ s/# //' \
		"$HARAKA_CONF/plugins"
}

configure_install_default()
{
	local _haraka="$STAGE_MNT/usr/local/lib/node_modules/Haraka"
	local _source="$_haraka/config"

	if [ ! -f "$_source/$1" ]; then
		local _pname="${1%.*}"
		_source="$_haraka/node_modules/haraka-plugin-$_pname/config"
		if [ ! -f "$_source/$1" ]; then
			echo "unable to find default '$1' in "
			echo "    $_haraka/config"
			echo " or "
			echo "    $_source"
			exit 1
		fi
	fi

	echo "cp $_source/$1 $HARAKA_CONF/$1"
	cp "$_source/$1" "$HARAKA_CONF/$1"
}

configure_haraka_limit()
{
	if ! grep -qs ^limit "$HARAKA_CONF/plugins"; then
		tell_status "adding limit plugin"
		echo 'limit' | tee -a "$HARAKA_CONF/plugins"
	fi

	if [ ! -f "$HARAKA_CONF/limit.ini" ]; then
		configure_install_default limit.ini
		sed -i.bak \
			-e 's/^; max/max/' \
			-e 's/^; history/history/' \
			-e 's/^; discon/discon/' \
			"$HARAKA_CONF/limit.ini"
	fi
}

configure_haraka_dkim()
{
	if [ ! -f "$HARAKA_CONF/dkim_sign.ini" ]; then
		tell_status "enabling dkim_sign plugin"
		echo 'disabled=false' | tee -a "$HARAKA_CONF/dkim_sign.ini"
	fi

	if [ ! -d "$HARAKA_CONF/dkim" ]; then
		mkdir -p "$HARAKA_CONF/dkim"
	fi

	if [ ! -f "$HARAKA_CONF/dkim/dkim_key_gen.sh" ]; then
		cp "$STAGE_MNT/usr/local/lib/node_modules/Haraka/node_modules/haraka-plugin-dkim/config/dkim_key_gen.sh" \
			"$HARAKA_CONF/dkim/dkim_key_gen.sh"
	fi

	if [ ! -d "$HARAKA_CONF/dkim/$TOASTER_MAIL_DOMAIN" ]; then
		tell_status "generating DKIM keys"
		cd "$HARAKA_CONF/dkim"
		sh dkim_key_gen.sh "$TOASTER_MAIL_DOMAIN"
		cat "$HARAKA_CONF/dkim/$TOASTER_MAIL_DOMAIN/dns"

		tell_status "NOTICE: action required for DKIM validation. See message ^^^"
		sleep 5
	fi
}

configure_haraka_karma()
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

configure_haraka_redis()
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

configure_haraka_geoip() {
	if ! grep -qs ^calc_distance "$HARAKA_CONF/geoip.ini"; then
		tell_status "enabling geoip distance"
		echo "calc_distance=true
[asn]
report_as=asn
" | tee -a "$HARAKA_CONF/geoip.ini"
	fi
}

configure_haraka_http()
{
	if [ ! -f "$HARAKA_CONF/http.ini" ]; then
		tell_status "enable Haraka HTTP server"
		echo "listen=[::0]:80" | tee -a "$HARAKA_CONF/http.ini"
	fi
}

configure_haraka_haproxy()
{
	if [ ! -f "$HARAKA_CONF/haproxy_hosts" ]; then
		tell_status "enable haproxy support"
		get_jail_ip haproxy | tee -a "$HARAKA_CONF/haproxy_hosts"
	fi
}

configure_haraka_helo()
{
	if [ ! -f "$HARAKA_CONF/helo.checks.ini" ]; then
		tell_status "disabling HELO rejections"

		tee "$HARAKA_CONF/helo.checks.ini" <<EO_HELO_INI
[reject]
host_mismatch=false
EO_HELO_INI
	fi

	if [ ! -f "helo.checks.regexps" ]; then
		tell_status "rejecting brutefore AUTH signature"
		echo "ylmf\-pc" | tee "$HARAKA_CONF/helo.checks.regexps"
	fi
}

configure_haraka_results()
{
	if [ -f "$HARAKA_CONF/results.ini" ]; then
		return
	fi

	tell_status "cleaning up results"
	tee "$HARAKA_CONF/results.ini" <<EO_RESULTS
[fcrdns]
hide=ptr_names,ptr_name_to_ip,ptr_name_has_ips,ptr_multidomain,has_rdns

[data.headers]
order=fail,pass,msg

[data.uribl]
hide=skip

[dnsbl]
hide=pass

[qmail-deliverable]
order=fail,pass,msg

EO_RESULTS
}

enable_newsyslog() {
	tell_status "enabling newsyslog"
	stage_sysrc newsyslog_enable=YES
	sed -i.bak \
		-e '/^#0.*newsyslog/ s/^#0/0/' \
		"$STAGE_MNT/etc/crontab"
}

configure_haraka_log_reader()
{
	if grep -qs log-reader "$HARAKA_CONF/plugins"; then
		return
	fi

	tell_status "enabling log-reader plugin"
	echo log-reader >> "$HARAKA_CONF/plugins"
}

configure_haraka_log_rotation()
{
	enable_newsyslog

	tell_status "configuring haraka.log rotation"
	mkdir -p "$STAGE_MNT/etc/newsyslog.conf.d"
	tee -a "$STAGE_MNT/etc/newsyslog.conf.d/haraka.conf" <<EO_HARAKA
/var/log/haraka.log			644  7	   *	@T00  JC
EO_HARAKA
}

configure_haraka_access()
{
	local ACCESS="$HARAKA_CONF/connect.rdns_access.whitelist"
	if grep -qs "$(get_jail_ip stage)" "$ACCESS"; then
		return
	fi

	tell_status "whitelisting the staging IP"
	tee -a "$ACCESS" <<EO_WL
$(get_jail_ip munin)
$(get_jail_ip stage)
EO_WL
}

configure_haraka_dcc()
{
	if [ -f "$HARAKA_CONF/dcc.ini" ]; then
		return
	fi

	tell_status "configuring DCC"
	tee -a "$HARAKA_CONF/dcc.ini" <<EO_DCC
[dccifd]
host=$(get_jail_ip dcc)
port=1025
EO_DCC
}

configure_haraka_spf()
{
	if grep -qs '^;' "$HARAKA_CONF/spf.ini"; then
		tell_status "spf.ini already configured"
	else
		tell_status "configuring SPF [relay]context=myself"
		tee -a "$HARAKA_CONF/spf.ini" <<EO_SPF_RELAY
[relay]
context=myself
EO_SPF_RELAY
	fi
}

configure_haraka()
{
	tell_status "installing Haraka, stage 2"
	stage_exec haraka -i /data

	tell_status "configuring Haraka"
	# echo 'LOGINFO' > "$HARAKA_CONF/loglevel"
	if [ ! -f "$HARAKA_CONF/tarpit.timeout" ]; then
		echo '3' > "$HARAKA_CONF/tarpit.timeout"
	fi

	if [ ! -f "$HARAKA_CONF/me" ]; then
		echo "$TOASTER_HOSTNAME" > "$HARAKA_CONF/me"
	fi

	if [ ! -f "$HARAKA_CONF/deny_includes_uuid" ]; then
		echo '12' > "$HARAKA_CONF/deny_includes_uuid"
	fi

	if [ ! -f "$HARAKA_CONF/rate_limit.ini" ]; then
		echo "redis_server = $(get_jail_ip redis)" > "$HARAKA_CONF/rate_limit.ini"
	fi

	if [ ! -f "$HARAKA_CONF/plugins" ]; then
		configure_install_default plugins
	fi

	configure_haraka_smtp_ini
	configure_haraka_outbound_ini
	configure_haraka_plugins
	configure_haraka_limit
	configure_haraka_syslog
	configure_haraka_vpopmail
	configure_haraka_smtp_forward
	configure_haraka_qmail_deliverable
	configure_haraka_dnsbl

	if [ ! -f "$HARAKA_CONF/data.headers.ini" ]; then
		echo "reject=no" | tee -a "$HARAKA_CONF/data.headers.ini"
	fi

	configure_haraka_http
	configure_haraka_tls
	configure_haraka_dkim
	configure_haraka_p0f
	configure_haraka_spamassassin
	configure_haraka_rspamd
	configure_haraka_clamav
	configure_haraka_avg
	configure_haraka_watch
	configure_haraka_karma
	configure_haraka_redis
	configure_haraka_geoip
	configure_haraka_haproxy
	configure_haraka_helo
	configure_haraka_results
	configure_haraka_log_reader
	configure_haraka_log_rotation
	configure_haraka_access
	configure_haraka_dcc
	configure_haraka_spf

	_pf_etc="$ZFS_DATA_MNT/haraka/etc/pf.conf.d"
	store_config "$_pf_etc/rdr.conf" <<EO_PF
rdr inet  proto tcp from any to <ext_ip4> port { 25 465 587 } -> $(get_jail_ip  haraka)
rdr inet6 proto tcp from any to <ext_ip6> port { 25 465 587 } -> $(get_jail_ip6 haraka)
EO_PF

	install_geoip_dbs
}

start_haraka()
{
	tell_status "starting haraka"
	cp "$STAGE_MNT/usr/local/lib/node_modules/Haraka/contrib/bsd-rc.d/haraka" \
		"$STAGE_MNT/usr/local/etc/rc.d/haraka"
	chmod 555 "$STAGE_MNT/usr/local/etc/rc.d/haraka"
	stage_sysrc haraka_enable=YES
	stage_sysrc haraka_flags='-c /data'

	if [ ! -d "$HARAKA_CONF/queue" ]; then
		mkdir -p "$HARAKA_CONF/queue"
	fi

	stage_exec service haraka start
}

test_haraka()
{
	tell_status "testing Haraka"
	stage_listening 25 5 2
}

preinstall_checks() {
	base_snapshot_exists || exit 1

	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/redis"; then
		tell_status "FATAL: redis jail required but not provisioned."
		exit
	fi
}

preinstall_checks
create_staged_fs haraka
mkdir -p "$STAGE_MNT/usr/local/share/GeoIP"
add_devfs_rule
start_staged_jail haraka
install_haraka
configure_haraka
start_haraka
test_haraka
promote_staged_jail haraka
