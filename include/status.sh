#!/bin/sh

export STATUS_TLS_WARN_DAYS=${STATUS_TLS_WARN_DAYS:-14}
export STATUS_TLS_CRIT_DAYS=${STATUS_TLS_CRIT_DAYS:-7}
export STATUS_ZPOOL_WARN_PCT=${STATUS_ZPOOL_WARN_PCT:-80}
export STATUS_ZPOOL_CRIT_PCT=${STATUS_ZPOOL_CRIT_PCT:-90}
export STATUS_CLAMAV_WARN_DAYS=${STATUS_CLAMAV_WARN_DAYS:-3}
export STATUS_CLAMAV_CRIT_DAYS=${STATUS_CLAMAV_CRIT_DAYS:-7}
export STATUS_PROBE_TIMEOUT=${STATUS_PROBE_TIMEOUT:-10}

# Nagios plugin exit codes
STATUS_OK=0
STATUS_WARN=1
STATUS_CRIT=2
STATUS_UNKNOWN=3

status_jail_ports()
{
	local _ports; _ports=$(status_service_ports "$1")

	# where pf redirects inbound mail, see configure_mta_pf_rdr
	if [ "$1" = "$TOASTER_MTA" ]; then _ports="$_ports 25"; fi
	if [ "$1" = "$TOASTER_MSA" ]; then _ports="$_ports 465 587"; fi

	local _port _unique=""
	for _port in $_ports; do
		case " $_unique " in
			*" $_port "*) ;;
			*) _unique="$_unique $_port" ;;
		esac
	done
	echo "${_unique# }"
}

# keep in sync with the ports each provision/<jail>.sh test_<jail>() checks
status_service_ports()
{
	case "$1" in
		bsd_cache|git|nginx|nictool|roundcube|snappymail|sqwebmail|tachyon)
			echo "80" ;;
		clamav)         echo "3310" ;;
		dcc)            echo "1025" ;;
		dhcp)           echo "68" ;;
		dns|knot|nsd|tinydns) echo "53" ;;
		dovecot)        echo "993 995" ;;
		elasticsearch)  echo "9200 5601" ;;
		ghost)          echo "2368" ;;
		haproxy)        echo "443" ;;
		haraka|postfix) echo "25" ;;
		home-assistant) echo "8123" ;;
		influxdb)       echo "8086" ;;
		jekyll)         echo "4000" ;;
		mail_dmarc)     echo "8080" ;;
		mailman)        echo "25 8001" ;;
		memcached)      echo "11211" ;;
		minecraft)      echo "25565" ;;
		mongodb)        echo "27017" ;;
		mysql)          echo "3306" ;;
		prometheus)     echo "9090 9094" ;;
		redis)          echo "6379" ;;
		rspamd)         echo "11334" ;;
		spamassassin)   echo "783" ;;
		stalwart)       echo "993" ;;
		vpopmail)       echo "25 80 89 8998" ;;
		webmail)
			if [ "$TOASTER_WEBMAIL_PROXY" = "nginx" ]; then
				echo "80 443"
			else
				echo "80"
			fi
			;;
		wildduck)       echo "24 25 587 993 995 2525 3000 8080 8082" ;;
		zonemta)        echo "2525 8082" ;;
	esac
}

status_enabled_jails()
{
	# jail_list has no default in /etc/defaults/rc.conf, so sysrc can't
	# mistake a base system value for one the admin set
	sysrc -n jail_list 2>/dev/null || true
}

status_jail_ip4()
{
	jls -j "$1" ip4.addr 2>/dev/null || true
}

# sockstat walks every socket on the host whatever its filters (~0.5s a call),
# so take one snapshot and attribute each socket to a jail by its owning PID.
# Without -w, sockstat truncates IPv6 addresses, and their ports, to 21 chars.
status_load_listeners()
{
	_status_listeners=$(
		{
			jls jid name
			echo "--"
			ps -ax -o pid= -o jid=
			echo "--"
			sockstat -w -l -q -4 -6
		} 2>/dev/null | awk '
			$1 == "--"   { section++; next }
			section == 0 { name[$1] = $2; next }
			section == 1 { if ($2 in name) jail[$1] = name[$2]; next }
			$3 in jail   { n = split($6, addr, ":"); print jail[$3] ":" addr[n] }
		' | sort -u | tr '\n' ' '
	)
}

status_port_listening()
{
	case " $_status_listeners " in
		*" $1:$2 "*) return 0 ;;
	esac
	return 1
}

# $1 jail's name in jls, $2 ports to leave out
status_observed_ports()
{
	local _l _port _ports=""
	for _l in $_status_listeners; do
		case "$_l" in
			"$1":*) _port="${_l#*:}" ;;
			*) continue ;;
		esac

		# every jail's syslogd binds 514 to forward its logs, even with -s
		case " 514 $2 " in
			*" $_port "*) ;;
			*) _ports="$_ports $_port" ;;
		esac
	done

	if [ -n "$_ports" ]; then
		# shellcheck disable=SC2086
		echo "($(printf '%s\n' $_ports | sort -n | paste -s -d ' ' -))"
	fi
}

# where each provisioner installs TOASTER_HOSTNAME's certificate
status_jail_cert()
{
	local _data; _data=$(get_jail_data "$1")
	local _f

	for _f in \
		"$_data/etc/tls/certs/$TOASTER_HOSTNAME.pem" \
		"$_data/etc/tls.d/$TOASTER_HOSTNAME.pem" \
		"$_data/config/tls/$TOASTER_HOSTNAME.pem" \
		"$_data/config/tls_cert.pem"
	do
		if [ -f "$_f" ]; then
			echo "$_f"
			return
		fi
	done
}

status_tls_expiry()
{
	if ! openssl x509 -in "$1" -noout >/dev/null 2>&1; then
		echo "invalid"; return $STATUS_CRIT
	fi

	if ! openssl x509 -in "$1" -noout -checkend 0 >/dev/null 2>&1; then
		echo "expired"; return $STATUS_CRIT
	fi

	if ! openssl x509 -in "$1" -noout -checkend $((STATUS_TLS_CRIT_DAYS * 86400)) >/dev/null 2>&1; then
		echo "<${STATUS_TLS_CRIT_DAYS}d"; return $STATUS_CRIT
	fi

	if ! openssl x509 -in "$1" -noout -checkend $((STATUS_TLS_WARN_DAYS * 86400)) >/dev/null 2>&1; then
		echo "<${STATUS_TLS_WARN_DAYS}d"; return $STATUS_WARN
	fi

	echo "ok"
}

# $1 label, $2 text the reply must contain ("" for any), then the command.
# A failure prints a second line, the reason.
status_probe_cmd()
{
	local _label="$1" _expect="$2"; shift 2
	local _out _rc=0

	_out=$(timeout "$STATUS_PROBE_TIMEOUT" "$@" </dev/null 2>&1) || _rc=$?

	if [ "$_rc" = 0 ] && echo "$_out" | grep -q "$_expect"; then
		echo "$_label ok"; return $STATUS_OK
	fi

	echo "$_label FAIL"
	if [ "$_rc" = 124 ]; then
		echo "no reply within ${STATUS_PROBE_TIMEOUT}s"
	else
		echo "$_out" | grep . | tail -1
	fi
	return $STATUS_CRIT
}

# with stdin closed, s_client hangs up right after the handshake, so the
# service's greeting is never read
status_probe_tls()
{
	local _label="$1"; shift
	status_probe_cmd "$_label" '^CONNECTION ESTABLISHED' \
		openssl s_client -brief -servername "$TOASTER_HOSTNAME" "$@"
}

status_probe_http()
{
	local _label="$1" _expect="$2" _url="$3"
	status_probe_cmd "$_label" "$_expect" fetch -T 5 -qo - "$_url"
}

# Elasticsearch 8 turns on security by default: TLS on 9200, and a 401 for
# anyone without credentials. That 401 still proves the node is answering.
status_probe_elasticsearch()
{
	local _scheme _out _rc
	for _scheme in http https; do
		_rc=0
		_out=$(timeout "$STATUS_PROBE_TIMEOUT" fetch -T 5 --no-verify-peer --no-verify-hostname \
			-qo - "$_scheme://$1:9200/_cluster/health" </dev/null 2>&1) || _rc=$?

		case "$(echo "$_out" | sed -n 's/.*"status" *: *"\([a-z]*\)".*/\1/p')" in
			# a single node has nowhere to place replicas, so yellow is its healthy
			green)  echo "health green"; return $STATUS_OK ;;
			yellow) echo "health yellow"; return $STATUS_OK ;;
			red)    echo "health red"; return $STATUS_CRIT ;;
		esac

		if echo "$_out" | grep -q 'Unauthorized\|Authentication required'; then
			echo "$_scheme ok"; return $STATUS_OK
		fi
		if [ "$_rc" = 124 ]; then break; fi
	done

	echo "health FAIL"
	if [ "$_rc" = 124 ]; then
		echo "no reply within ${STATUS_PROBE_TIMEOUT}s"
	else
		echo "$_out" | grep . | tail -1
	fi
	return $STATUS_CRIT
}

status_probe_clamav()
{
	local _ping
	if ! _ping=$(status_probe_cmd ping "" jexec "$1" /usr/local/bin/clamdscan --ping 1); then
		echo "$_ping"; return $STATUS_CRIT
	fi

	local _db; _db="$(get_jail_data "$1")/db"
	if [ -z "$(find "$_db" -name 'daily.c[lv]d' 2>/dev/null)" ]; then
		echo "no sigs"; return $STATUS_CRIT
	fi

	if [ -n "$(find "$_db" -name 'daily.c[lv]d' -mtime -"$STATUS_CLAMAV_WARN_DAYS" 2>/dev/null)" ]; then
		echo "sigs ok"; return $STATUS_OK
	fi

	if [ -n "$(find "$_db" -name 'daily.c[lv]d' -mtime -"$STATUS_CLAMAV_CRIT_DAYS" 2>/dev/null)" ]; then
		echo "sigs >${STATUS_CLAMAV_WARN_DAYS}d"; return $STATUS_WARN
	fi

	echo "sigs >${STATUS_CLAMAV_CRIT_DAYS}d"; return $STATUS_CRIT
}

# $1 jail, $2 its name in jls, $3 its first IPv4
status_probe()
{
	case "$1" in
		clamav)       status_probe_clamav "$2" ;;
		dns)          status_probe_cmd resolve "" host -W 3 "$TOASTER_HOSTNAME" "$3" ;;
		dovecot)      status_probe_tls imaps -connect "$3:993" ;;
		elasticsearch) status_probe_elasticsearch "$3" ;;
		haproxy)      status_probe_tls https -connect "$3:443" ;;
		haraka)       status_probe_tls starttls -starttls smtp -connect "$3:25" ;;
		mail_dmarc)   status_probe_http http DMARC "http://$3:8080/" ;;
		mysql)        status_probe_cmd ping "" jexec "$2" /usr/local/bin/mysqladmin ping ;;
		nictool)      status_probe_http http NicTool "http://$3/" ;;
		redis)        status_probe_cmd ping PONG jexec "$2" /usr/local/bin/redis-cli ping ;;
		roundcube)    status_probe_http http rcube_webmail "http://$3/" ;;
		rspamd)       status_probe_http ping pong "http://$3:11334/ping" ;;
		# SPAMD/<protocol> <exit code>, some versions append PONG
		spamassassin) status_probe_cmd ping '^SPAMD/[0-9.]* 0' jexec "$2" /usr/local/bin/spamc -K ;;
		tachyon)      status_probe_http http 'tachyon/v/' "http://$3/tachyon/" ;;
		vpopmail)     status_probe_cmd postmaster "" \
		                  jexec "$2" /usr/local/vpopmail/bin/vuserinfo -n "postmaster@$TOASTER_MAIL_DOMAIN" ;;
		webmail)
			if [ "$TOASTER_WEBMAIL_PROXY" = "nginx" ]; then
				status_probe_tls https -connect "$3:443"
			else
				status_probe_http http "" "http://$3/"
			fi
			;;
	esac
}

status_note()
{
	local _label
	case "$1" in
		"$STATUS_OK")   _label="INFO" ;;
		"$STATUS_WARN") _label="WARNING" ;;
		"$STATUS_CRIT") _label="CRITICAL" ;;
		*)              _label="UNKNOWN" ;;
	esac

	case "$1" in
		"$STATUS_WARN") _status_warnings=$((_status_warnings + 1)) ;;
		"$STATUS_CRIT") _status_criticals=$((_status_criticals + 1)) ;;
	esac

	if [ "$1" -gt "$_status_worst" ]; then _status_worst="$1"; fi

	_status_notes="${_status_notes}$_label: $2
"
}

status_host()
{
	local _pool="${ZFS_VOL%%/*}"
	local _health; _health=$(zpool list -H -o health "$_pool" 2>/dev/null) || _health=""
	local _cap; _cap=$(zpool list -H -o capacity "$_pool" 2>/dev/null) || _cap=""
	_cap="${_cap%\%}"

	if [ -z "$_health" ]; then
		_health="missing"; _cap="?"
		status_note $STATUS_CRIT "zpool $_pool not found"
	elif [ "$_health" != "ONLINE" ]; then
		status_note $STATUS_CRIT "zpool $_pool is $_health"
	elif [ "$_cap" -ge "$STATUS_ZPOOL_CRIT_PCT" ]; then
		status_note $STATUS_CRIT "zpool $_pool is ${_cap}% full"
	elif [ "$_cap" -ge "$STATUS_ZPOOL_WARN_PCT" ]; then
		status_note $STATUS_WARN "zpool $_pool is ${_cap}% full"
	fi

	local _pf="enabled"
	if ! pfctl -s info 2>/dev/null | grep -q '^Status: Enabled'; then
		_pf="DISABLED"
		status_note $STATUS_CRIT "pf is not enabled, jails have no NAT or port redirects"
	fi

	echo "$TOASTER_HOSTNAME  FreeBSD $(freebsd-version -u 2>/dev/null)  mt6 $(mt6_version)  zpool $_pool $_health ${_cap}%  pf $_pf"
}

status_datasets()
{
	local _enabled; _enabled=$(status_enabled_jails)
	local _ds _name _rollback="" _orphans=""

	for _ds in $(zfs list -H -o name -d 1 "$ZFS_JAIL_VOL" 2>/dev/null); do
		_name="${_ds##*/}"
		case "$_name" in
			stage)   status_note $STATUS_WARN "stage exists, a provision failed or is running" ;;
			*.ready) status_note $STATUS_WARN "$_name exists, its promotion failed" ;;
			*.last)
				case " $_enabled " in
					*" ${_name%.last} "*) _rollback="$_rollback $_name" ;;
					*)                    _orphans="$_orphans $_name" ;;
				esac
				;;
		esac
	done

	if [ -n "$_rollback" ]; then
		status_note $STATUS_OK "rollback available:$_rollback"
	fi

	if [ -n "$_orphans" ]; then
		status_note $STATUS_OK "rollback for jails not in jail_list:$_orphans"
	fi
}

status_jail()
{
	local _jail="$1"
	local _safe; _safe=$(safe_jailname "$_jail")
	local _ip="" _state="DOWN" _ports="" _tls="" _probe="" _closed=0 _sev

	if jail_is_running "$_safe"; then
		_state="up"
		_ip=$(status_jail_ip4 "$_safe")

		local _expected; _expected=$(status_jail_ports "$_jail")

		local _port
		for _port in $_expected; do
			if status_port_listening "$_safe" "$_port"; then
				_ports="$_ports $_port"
			else
				_ports="$_ports $_port!"
				_closed=1
				status_note $STATUS_CRIT "$_jail is not listening on port $_port"
			fi
		done

		local _extra; _extra=$(status_observed_ports "$_safe" "$_expected")
		_ports="${_ports# }"
		if [ -n "$_extra" ]; then _ports="${_ports:+$_ports }$_extra"; fi

		if [ "$_closed" = 0 ]; then
			_sev=0
			_probe=$(status_probe "$_jail" "$_safe" "${_ip%%,*}") || _sev=$?
			local _why; _why=$(echo "$_probe" | sed -n 2p)
			_probe=$(echo "$_probe" | sed -n 1p)
			if [ "$_sev" -gt 0 ]; then status_note "$_sev" "$_jail $_probe${_why:+: $_why}"; fi
		fi
	else
		status_note $STATUS_CRIT "$_jail is not running"
	fi

	local _cert; _cert=$(status_jail_cert "$_jail")
	if [ -n "$_cert" ]; then
		_sev=0
		_tls=$(status_tls_expiry "$_cert") || _sev=$?
		if [ "$_sev" -gt 0 ]; then
			status_note "$_sev" "$_jail TLS certificate $_tls: $_cert"
		fi
	fi

	status_row "$_jail" "$_ip" "$_state" "$_ports" "$_tls" "$_probe"
}

# sized before the slow checks run, so each row prints as soon as it is known
status_column_widths()
{
	_status_w_jail=4
	_status_w_ip=2
	_status_w_ports=5

	local _jail _cell _expected
	for _jail in "$@"; do
		[ ${#_jail} -le "$_status_w_jail" ] || _status_w_jail=${#_jail}

		_cell=$(status_jail_ip4 "$(safe_jailname "$_jail")")
		[ ${#_cell} -le "$_status_w_ip" ] || _status_w_ip=${#_cell}

		_expected=$(status_jail_ports "$_jail")
		_cell="$(status_jail_ports "$_jail" | sed 's/[0-9][0-9]*/&!/g') $(status_observed_ports "$(safe_jailname "$_jail")" "$_expected")"
		_cell="${_cell# }"
		_cell="${_cell% }"
		[ ${#_cell} -le "$_status_w_ports" ] || _status_w_ports=${#_cell}
	done
}

status_row()
{
	printf "%-${_status_w_jail}s  %-${_status_w_ip}s  %-5s  %-${_status_w_ports}s  %-7s  %s\n" \
		"$1" "${2:--}" "$3" "${4:--}" "${5:--}" "${6:--}"
}

mt6_status()
{
	if [ "$(id -u)" != "0" ]; then
		echo "status: run as root"
		return $STATUS_UNKNOWN
	fi

	_status_worst=$STATUS_OK
	_status_warnings=0
	_status_criticals=0
	_status_notes=""

	local _jails="$*"
	if [ -z "$_jails" ]; then _jails=$(status_enabled_jails); fi

	if [ -z "$_jails" ]; then
		echo "UNKNOWN: no jails in jail_list"
		return $STATUS_UNKNOWN
	fi

	status_host
	echo

	status_load_listeners
	# shellcheck disable=SC2086
	status_column_widths $_jails
	status_row JAIL IP STATE PORTS TLS PROBE

	local _jail _count=0
	for _jail in $_jails; do
		status_jail "$_jail"
		_count=$((_count + 1))
	done

	status_datasets

	if [ -n "$_status_notes" ]; then
		echo
		printf "%s" "$_status_notes"
	fi

	echo
	case "$_status_worst" in
		"$STATUS_OK")   echo "MT6 OK - $_count jails" ;;
		"$STATUS_WARN") echo "MT6 WARNING - $_status_warnings warning" ;;
		*)              echo "MT6 CRITICAL - $_status_criticals critical, $_status_warnings warning" ;;
	esac

	return "$_status_worst"
}
