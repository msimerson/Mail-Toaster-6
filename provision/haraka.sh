#!/bin/sh

set -e

. mail-toaster.sh

service_config haraka
export TOASTER_HARAKA_VERSION=${TOASTER_HARAKA_VERSION:-""}

export JAIL_DEVFS_RULESET="$JAIL_DEVFS_RULESET_BPF"
export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

mt6-include tls

HARAKA_CONF="$(get_jail_data haraka)/config"

install_haraka()
{
	tell_status "installing node & npm"
	stage_pkg_install npm-node24 gmake pkgconf git-tiny python3
	if [ "$BOURNE_SHELL" != "bash" ]; then
		tell_status "Install bash since not in base"
		stage_pkg_install bash
	fi

	tell_status "installing Haraka"
	if [ -n "$TOASTER_HARAKA_VERSION" ]; then
		stage_exec bash -c "npm install -g --omit=dev --allow-scripts=modern-syslog haraka@$TOASTER_HARAKA_VERSION"
	else
		stage_exec bash -c "git clone https://github.com/haraka/Haraka.git /usr/local/lib/node_modules/haraka"
		stage_exec bash -c "cd /usr/local/lib/node_modules/haraka && npm install --omit=dev"
		stage_exec bash -c "ln -s /usr/local/lib/node_modules/haraka/bin/haraka /usr/local/bin/haraka"
		stage_exec bash -c "ln -s /usr/local/lib/node_modules/haraka/bin/haraka_grep /usr/local/bin/haraka_grep"
	fi

	local _plugins="ws express"
	for _p in dmarc-perl elasticsearch log-reader p0f watch; do
		_plugins="$_plugins haraka-plugin-$_p"
	done
	stage_exec bash -c "if [ -f /data/package.json ]; then rm /data/package.json; fi"
	stage_exec bash -c "cd /data && npm install --omit=dev $_plugins"
}

haraka_enable_plugin()
{
	local _plugin="$1"

	if grep -qs "^$_plugin\$" "$HARAKA_CONF/plugins"; then return; fi

	tell_status "enabling $_plugin plugin"
	sed_inplace -e "/^# $_plugin\$/ s/# //" "$HARAKA_CONF/plugins"

	if ! grep -qs "^$_plugin\$" "$HARAKA_CONF/plugins"; then
		echo "$_plugin" | tee -a "$HARAKA_CONF/plugins"
	fi
}

install_geoip_dbs()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/geoip"; then
		tell_status "GeoIP jail not present, SKIPPING geoip plugin"
		return
	fi

	mount_nullfs "$(get_jail_data geoip)/db" "$STAGE_MNT/usr/local/share/GeoIP"

	fstab_add_mount haraka "$(get_jail_data geoip)/db" "$ZFS_JAIL_MNT/haraka/usr/local/share/GeoIP"

	haraka_enable_plugin geoip
}

install_p0f()
{
	tell_status "install p0f"
	stage_pkg_install p0f

	tell_status "installing p0f startup file"
	mkdir -p "$STAGE_MNT/usr/local/etc/rc.d"
	local _start="$STAGE_MNT/usr/local/etc/rc.d/p0f"
	cp "$STAGE_MNT/data/node_modules/haraka-plugin-p0f/contrib/bsd-rc.d/p0f" "$_start"
	chmod 755 "$_start"

	get_public_facing_nic
	if [ "$PUBLIC_NIC" != "bce1" ]; then
		sed_inplace -e "s/ bce1 / $PUBLIC_NIC /" "$_start"
	fi

	stage_sysrc p0f_enable=YES
	stage_exec service p0f start
}

configure_haraka_syslog()
{
	haraka_enable_plugin syslog

	if ! grep -qs daemon_log_file "$HARAKA_CONF/smtp.ini"; then
		if [ ! -f "$HARAKA_CONF/smtp.ini" ]; then
			store_config "$HARAKA_CONF/smtp.ini" <<EO_DLF
daemon_log_file=/dev/null
EO_DLF
		else
			# send haraka logs to /dev/null
			sed_inplace -e 's/^daemon_log_file=.*/daemon_log_file=\/dev\/null/' "$HARAKA_CONF/smtp.ini"
		fi
	fi

	store_config "$HARAKA_CONF/log.reader.ini" "overwrite" <<EO_LRC
[log]
file=/data/log/maillog
EO_LRC

	# absence of mailogs in jail prevents log-reader from working
	if ! grep -qs always_ok "$HARAKA_CONF/syslog.ini"; then
		# don't write to daemon_log_file if syslog write was successful
		echo "[general]
always_ok=true" | tee -a "$HARAKA_CONF/syslog.ini"
	fi

	# log to the data volume so mail logs survive a re-provision
	local _logdir
	_logdir="$(get_jail_data haraka)/log"
	if [ ! -d "$_logdir" ]; then
		tell_status "creating log dir $_logdir"
		mkdir -p "$_logdir"
	fi

	store_config "$STAGE_MNT/etc/syslog.conf" "overwrite" <<EO_SYSLOG
mail.info					/data/log/maillog
#*.*			@syslog
EO_SYSLOG

	touch "$_logdir/maillog"
}

# Set a key in the main section of an ini (the keys before the first
# [section], or under [main]) unless the file already sets it: an existing
# value, whatever it is, is the operator's choice. Haraka accepts indented
# section headers, so a key in an indented [example.com] is not main's.
haraka_ini_default()
{
	local _ini="$HARAKA_CONF/$1" _key="$2" _value="$3"

	if awk -v key="$_key" '
		BEGIN { inmain = 1 }
		{
			line = $0
			sub(/^[[:space:]]+/, "", line)
			if (line ~ /^\[/) {
				sec = line
				sub(/^\[/, "", sec)
				sub(/\].*$/, "", sec)
				inmain = (sec == "main")
				next
			}
			if (inmain && line ~ "^" key "[[:space:]]*=") found = 1
		}
		END { exit !found }
	' "$_ini" 2>/dev/null; then
		tell_status "preserving $_key in $1"
		return 0
	fi

	tell_status "setting $_key=$_value in $1"
	local _tmp
	_tmp=$(mktemp "${TMPDIR:-/tmp}/haraka-ini.XXXXXX") || return 1
	{
		echo "$_key=$_value"
		[ ! -f "$_ini" ] || cat "$_ini"
	} > "$_tmp"
	cat "$_tmp" > "$_ini"
	rm -f "$_tmp"
}

# A [section] of its own, as a domain has in qmail-deliverable.ini, does not
# inherit the main section's keys. Set a key in each section that lacks it,
# leaving the ones that set it, whatever the value, alone.
haraka_ini_section_defaults()
{
	local _ini="$HARAKA_CONF/$1" _key="$2" _value="$3"
	[ -f "$_ini" ] || return 0

	local _tmp
	_tmp=$(mktemp "${TMPDIR:-/tmp}/haraka-ini.XXXXXX") || return 1
	awk -v key="$_key" -v value="$_value" '
		{ lines[NR] = $0 }
		END {
			n = 0
			for (i = 1; i <= NR; i++) {
				line = lines[i]
				sub(/^[[:space:]]+/, "", line)
				if (line ~ /^\[/) {
					n++
					name = line
					sub(/^\[/, "", name)
					sub(/\].*$/, "", name)
					hdr[i] = n
					secname[n] = name
				} else if (n > 0 && line ~ "^" key "[[:space:]]*=") {
					has[n] = 1
				}
			}
			for (i = 1; i <= NR; i++) {
				print lines[i]
				if ((i in hdr) && secname[hdr[i]] != "main" && !(hdr[i] in has))
					print key "=" value
			}
		}' "$_ini" > "$_tmp" || { rm -f "$_tmp"; return 1; }

	if ! cmp -s "$_tmp" "$_ini"; then
		tell_status "setting $_key=$_value in the sections of $1 that lack it"
		cat "$_tmp" > "$_ini"
	fi
	rm -f "$_tmp"
}

configure_haraka_smtp_forward()
{
	if [ ! -f "$HARAKA_CONF/smtp_forward.ini" ]; then
		tell_status "configure smtp forward to vpopmail jail"
		echo "host=$(get_jail_ip4 vpopmail)
port=25
" | tee -a "$HARAKA_CONF/smtp_forward.ini"
	fi

	# Mail from an authenticated (relaying) sender goes to outbound, not to
	# smtp_forward, unless this is set. Outbound routes by the queue.next_hop
	# that qmail-deliverable left, the Dovecot LMTP URL it sets for mailboxes,
	# so a vpopmail alias is handed to Dovecot, which has no such mailbox.
	# With it, smtp_forward delivers aliases to qmail on the vpopmail jail,
	# as it does for unauthenticated mail. A mailbox still goes to Dovecot
	# over LMTP, and mail for other domains stays with outbound, as
	# qmail-deliverable marks those as wanting outbound.
	haraka_ini_default smtp_forward.ini enable_outbound true
}

configure_haraka_vpopmail()
{
	if [ ! -f "$HARAKA_CONF/auth_vpopmaild.ini" ]; then
		tell_status "config SMTP AUTH using vpopmaild"
		echo "host=$(get_jail_ip4 vpopmail)" > "$HARAKA_CONF/auth_vpopmaild.ini"
	fi

	if ! grep -qs ^auth/auth_vpopmaild "$HARAKA_CONF/plugins"; then
		tell_status "enabling vpopmaild plugin"

		# shellcheck disable=1004
		sed_inplace \
			-e '/^# auth\/auth_proxy$/a\
auth\/auth_vpopmaild
' "$HARAKA_CONF/plugins"
	fi
}

configure_haraka_qmail_deliverable()
{
	if [ ! -f "$HARAKA_CONF/qmail-deliverable.ini" ]; then
		tell_status "config recipient validation with Qmail::Deliverable"
		echo "check_outbound=true
host=$(get_jail_ip4 vpopmail)
queue=smtp_forward
next_hop=lmtp://$(get_jail_ip4 dovecot)" | \
			tee -a "$HARAKA_CONF/qmail-deliverable.ini"
	fi

	# A message for both an alias and a mailbox has two routes (qmail and
	# Dovecot). qmail-deliverable then hands it to outbound, which resolves
	# the domain's MX, which is this host, where the same recipients split
	# again and go back to outbound. Deferring the second recipient makes
	# the sender retry it as a message of its own.
	haraka_ini_default qmail-deliverable.ini split defer
	# a domain with its own section does not inherit it from main
	haraka_ini_section_defaults qmail-deliverable.ini split defer

	if ! grep -qs ^qmail-deliverable "$HARAKA_CONF/plugins"; then
		tell_status "enabling qmail-deliverable plugin"
		sed_inplace \
			-e '/^# qmail-deliverable/ s/# //' \
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

	haraka_enable_plugin p0f
}

configure_haraka_spamassassin()
{
	if [ ! -d "$ZFS_JAIL_MNT/spamassassin" ]; then
		tell_status "skipping spamassassin setup, no jail exists"
		return
	fi

	haraka_enable_plugin spamassassin

	if [ ! -f "$HARAKA_CONF/spamassassin.ini" ]; then
		tell_status "configuring Haraka spamassassin plugin"
		echo "spamd_socket=$(get_jail_ip4 spamassassin):783
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
		echo "host = $(get_jail_ip4 avg)
tmpdir=/data/avg/spool
" | tee -a "$HARAKA_CONF/avg.ini"
	fi

	if zfs_filesystem_exists "$ZFS_DATA_VOL/avg"; then
		tell_status "adding avg data FS to Haraka jail"
		JAIL_FSTAB="$JAIL_FSTAB
$(get_jail_data avg)   $ZFS_JAIL_MNT/haraka/data/avg nullfs rw 0 0"

		if ! grep -qs spool "$HARAKA_CONF/avg.ini"; then
			tell_status "update tmpdir in avg.ini"
			sed_inplace -e \
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
		sed_inplace -e '/clamd$/a\
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

	haraka_enable_plugin clamd

	if ! grep -qs ^clamd_socket "$HARAKA_CONF/clamd.ini"; then
		tell_status "configure Haraka clamav plugin"
		echo "clamd_socket=$(get_jail_ip4 clamav):3310

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
	haraka_enable_plugin tls

	if [ ! -f "$HOST_TLS_KEY" ] || [ ! -f "$HOST_TLS_CRT" ]; then
		return
	fi

	if [ -d "$HARAKA_CONF/tls" ]; then
		install_tls_pem "$HARAKA_CONF/tls/${TOASTER_HOSTNAME}.pem"
	else
		install_tls_pair "$HARAKA_CONF/tls_cert.pem" "$HARAKA_CONF/tls_key.pem"
	fi
}

configure_haraka_dnsbl()
{
	if [ ! -f "$HARAKA_CONF/dns-list.ini" ]; then
		tell_status "configuring dns-list"
		configure_install_default dns-list.ini
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
		echo "host = $(get_jail_ip4 rspamd)
add_headers = always
" | tee -a "$HARAKA_CONF/rspamd.ini"
	fi

	haraka_enable_plugin rspamd
}

configure_haraka_watch()
{
	haraka_enable_plugin watch

	if [ ! -f "$HARAKA_CONF/watch.ini" ]; then
		echo "[wss]
url=wss://$TOASTER_HOSTNAME/watch" > "$HARAKA_CONF/watch.ini"
	fi
}

haraka_listen_addr()
{
	if jail_has_ip6; then
		echo "[::0]"
	else
		echo "0.0.0.0"
	fi
}

configure_haraka_smtp_ini()
{
	if [ ! -f "$HARAKA_CONF/smtp.ini" ]; then
		configure_install_default smtp.ini
	fi

	local _addr; _addr=$(haraka_listen_addr)
	sed_inplace \
		-e "s/^;listen=.*\$/listen=$_addr:25,$_addr:465,$_addr:587/" \
		-e 's/^;nodes=cpus/nodes=2/' \
		-e 's/^;daemonize=true/daemonize=true/' \
		-e 's/^;daemon_pid_file/daemon_pid_file/' \
		-e 's/^;daemon_log_file/daemon_log_file/' \
		"$HARAKA_CONF/smtp.ini"
}

configure_haraka_connection_ini() {
	if [ ! -f "$HARAKA_CONF/connection.ini" ]; then
		configure_install_default connection.ini
	fi

	sed_inplace \
		-e '/^deny_chars=/ s/=0/=12/' \
		"$HARAKA_CONF/connection.ini"

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

	for _p in process_title spf bounce uribl attachment dkim karma fcrdns; do
		haraka_enable_plugin "$_p"
	done
}

configure_install_default()
{
	local _haraka="$STAGE_MNT/usr/local/lib/node_modules/haraka"
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

	printf 'cp %s %s\n' "$_source/$1" "$HARAKA_CONF/$1"
	cp "$_source/$1" "$HARAKA_CONF/$1"
}

configure_haraka_limit()
{
	haraka_enable_plugin limit

	if [ ! -f "$HARAKA_CONF/limit.ini" ]; then
		configure_install_default limit.ini
		sed_inplace \
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

	# dkim_sign.ini above is the old plugin's. The dkim plugin only reads
	# dkim.ini, whose default has [sign] enabled=false, so without this a
	# fresh install generates keys below and never signs with them.
	if [ ! -f "$HARAKA_CONF/dkim.ini" ]; then
		tell_status "enabling DKIM signing"
		configure_install_default dkim.ini
		sed_inplace \
			-e '/^\[sign\]/,/^\[/ s/^enabled[[:space:]]*=.*/enabled = true/' \
			"$HARAKA_CONF/dkim.ini"
	fi

	if [ ! -d "$HARAKA_CONF/dkim" ]; then
		mkdir -p "$HARAKA_CONF/dkim"
	fi

	if [ ! -f "$HARAKA_CONF/dkim/dkim_key_gen.sh" ]; then
		cp "$STAGE_MNT/usr/local/lib/node_modules/haraka/node_modules/haraka-plugin-dkim/config/dkim_key_gen.sh" \
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
server_ip=$(get_jail_ip4 redis)

[deny_excludes]
plugins=send_email, access, helo.checks, headers, mail_from.is_resolvable, avg, limit, attachment, tls
" | tee -a "$HARAKA_CONF/karma.ini"

}

configure_haraka_redis()
{
	haraka_enable_plugin redis

	if [ ! -f "$HARAKA_CONF/redis.ini" ]; then
		echo "configuring redis plugin"
		tee "$HARAKA_CONF/redis.ini" <<EO_REDIS_CONF
[server]
host=$(get_jail_ip4 redis)
db=3

[pubsub]
host=$(get_jail_ip4 redis)
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
		echo "listen=$(haraka_listen_addr):80" | tee -a "$HARAKA_CONF/http.ini"
	fi
}

configure_haraka_haproxy()
{
	if [ ! -f "$HARAKA_CONF/haproxy_hosts" ]; then
		tell_status "enable haproxy support"
		get_jail_ip4 haproxy | tee -a "$HARAKA_CONF/haproxy_hosts"
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

[headers]
order=fail,pass,msg

[uribl]
hide=skip

[dns-list]
hide=pass

[dns-list]
hide=pass

[qmail-deliverable]
order=fail,pass,msg

EO_RESULTS
}


configure_haraka_log_reader()
{
	haraka_enable_plugin log-reader
}

configure_haraka_log_rotation()
{
	stage_enable_newsyslog

	tell_status "configuring haraka log rotation"
	store_config "$STAGE_MNT/etc/newsyslog.conf.d/haraka.conf" "overwrite" <<EO_HARAKA
/data/log/maillog			644  21	   *	@T00  JC
/var/log/haraka.log			644  21	   *	@T00  JC
EO_HARAKA
}

configure_haraka_access()
{
	local ACCESS="$HARAKA_CONF/connect.rdns_access.whitelist"
	if grep -qs "$(get_jail_ip4 stage)" "$ACCESS"; then
		return
	fi

	tell_status "whitelisting the staging IP"
	tee -a "$ACCESS" <<EO_WL
$(get_jail_ip4 munin)
$(get_jail_ip4 stage)
EO_WL
}

configure_haraka_dcc()
{
	if [ -f "$HARAKA_CONF/dcc.ini" ]; then return; fi

	if grep -qs '^\[dccifd\]' "$HARAKA_CONF/dcc.ini"; then return; fi

	tell_status "configuring DCC"
	tee -a "$HARAKA_CONF/dcc.ini" <<EO_DCC
[dccifd]
host=$(get_jail_ip4 dcc)
port=1025
EO_DCC
}

configure_haraka_spf()
{
	if grep -qs '^context=myself' "$HARAKA_CONF/spf.ini"; then
		tell_status "spf.ini already configured"
	else
		tell_status "configuring SPF [relay]context=myself"
		tee -a "$HARAKA_CONF/spf.ini" <<EO_SPF_RELAY
[relay]
context=myself
EO_SPF_RELAY
	fi
}

configure_haraka_me()
{
	# `haraka -i` has already written config/me by now, with the jail's own
	# hostname, so testing for the file alone left a new host greeting
	# with "EHLO haraka". That, or nothing, is no name an operator chose.
	local _me="$HARAKA_CONF/me" _cur=""
	if [ -f "$_me" ]; then _cur=$(tr -d '[:space:]' < "$_me"); fi

	case "$_cur" in
		""|haraka) ;;
		*) return 0 ;;
	esac

	tell_status "setting the Haraka name (config/me) to $TOASTER_HOSTNAME"
	echo "$TOASTER_HOSTNAME" > "$_me"
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

	configure_haraka_me

	if [ ! -f "$HARAKA_CONF/rate_limit.ini" ]; then
		echo "redis_server = $(get_jail_ip4 redis)" > "$HARAKA_CONF/rate_limit.ini"
	fi

	if [ ! -f "$HARAKA_CONF/plugins" ]; then
		configure_install_default plugins
	fi

	configure_haraka_smtp_ini
	configure_haraka_connection_ini
	configure_haraka_outbound_ini
	configure_haraka_plugins
	configure_haraka_limit
	configure_haraka_syslog
	configure_haraka_vpopmail
	configure_haraka_smtp_forward
	configure_haraka_qmail_deliverable
	configure_haraka_dnsbl

	configure_haraka_http
	configure_haraka_tls
	configure_haraka_dkim
	[ "$(sysctl -n security.jail.jailed)" = 1 ] || configure_haraka_p0f
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

	configure_mta_pf_rdr haraka

	install_geoip_dbs
}

start_haraka()
{
	tell_status "starting haraka"
	cp "$STAGE_MNT/usr/local/lib/node_modules/haraka/contrib/bsd-rc.d/haraka" \
		"$STAGE_MNT/usr/local/etc/rc.d/haraka"
	chmod 555 "$STAGE_MNT/usr/local/etc/rc.d/haraka"
	stage_sysrc haraka_enable=YES
	stage_sysrc haraka_flags='-c /data'

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
assure_devfs_bpf_ruleset
start_staged_jail haraka
install_haraka
configure_haraka
start_haraka
test_haraka
promote_staged_jail haraka
