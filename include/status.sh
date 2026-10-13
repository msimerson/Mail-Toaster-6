#!/bin/sh

export STATUS_TLS_WARN_DAYS=${STATUS_TLS_WARN_DAYS:-14}
export STATUS_TLS_CRIT_DAYS=${STATUS_TLS_CRIT_DAYS:-7}
export STATUS_ZPOOL_WARN_PCT=${STATUS_ZPOOL_WARN_PCT:-80}
export STATUS_ZPOOL_CRIT_PCT=${STATUS_ZPOOL_CRIT_PCT:-90}

# Nagios plugin exit codes
STATUS_OK=0
STATUS_WARN=1
STATUS_CRIT=2
STATUS_UNKNOWN=3

# keep in sync with the ports each provision/<jail>.sh test_<jail>() checks
status_jail_ports()
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
# so take one snapshot and attribute each socket to a jail by its owning PID
status_load_listeners()
{
	_status_listeners=$(
		{
			jls jid name
			echo "--"
			ps -ax -o pid= -o jid=
			echo "--"
			sockstat -l -q -4 -6
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
	local _ip="-" _state="DOWN" _ports="" _tls="-"

	if jail_is_running "$_safe"; then
		_state="up"
		_ip=$(status_jail_ip4 "$_safe")

		local _port
		for _port in $(status_jail_ports "$_jail"); do
			if status_port_listening "$_safe" "$_port"; then
				_ports="$_ports $_port"
			else
				_ports="$_ports $_port!"
				status_note $STATUS_CRIT "$_jail is not listening on port $_port"
			fi
		done
	else
		status_note $STATUS_CRIT "$_jail is not running"
	fi

	local _cert; _cert=$(status_jail_cert "$_jail")
	if [ -n "$_cert" ]; then
		local _sev=0
		_tls=$(status_tls_expiry "$_cert") || _sev=$?
		if [ "$_sev" -gt 0 ]; then
			status_note "$_sev" "$_jail TLS certificate $_tls: $_cert"
		fi
	fi

	status_row "$_jail" "$_ip" "$_state" "${_ports# }" "$_tls"
}

# sized before the slow checks run, so each row prints as soon as it is known
status_column_widths()
{
	_status_w_jail=4
	_status_w_ip=2
	_status_w_ports=5

	local _jail _cell
	for _jail in "$@"; do
		[ ${#_jail} -le "$_status_w_jail" ] || _status_w_jail=${#_jail}

		_cell=$(status_jail_ip4 "$(safe_jailname "$_jail")")
		[ ${#_cell} -le "$_status_w_ip" ] || _status_w_ip=${#_cell}

		_cell=$(status_jail_ports "$_jail" | sed 's/[0-9][0-9]*/&!/g')
		[ ${#_cell} -le "$_status_w_ports" ] || _status_w_ports=${#_cell}
	done
}

status_row()
{
	printf "%-${_status_w_jail}s  %-${_status_w_ip}s  %-5s  %-${_status_w_ports}s  %s\n" \
		"$1" "${2:--}" "$3" "${4:--}" "$5"
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

	# shellcheck disable=SC2086
	status_column_widths $_jails
	status_load_listeners
	status_row JAIL IP STATE PORTS TLS

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
