#!/bin/sh

safe_jailname()
{
	# constrain jail name chars to alpha-numeric and _
	# shellcheck disable=SC2001
	echo "$1" | sed -e 's/[^a-zA-Z0-9]/_/g'
}

get_jail_ip()
{
	local _start=${JAIL_NET_START:=1}

	case "$1" in
		syslog) echo "$JAIL_NET_PREFIX.$_start"; return ;;
		base)   echo "$JAIL_NET_PREFIX.$((_start + 1))"; return ;;
		stage)  echo "$JAIL_NET_PREFIX.254"; return ;;
	esac

	if echo "$1" | grep -q ^base; then
		echo "$JAIL_NET_PREFIX.$((_start + 1))"
		return
	fi

	local _octet="$_start"

	for _j in $JAIL_ORDERED_LIST; do
		if [ "$1" = "$_j" ]; then
			echo "$JAIL_NET_PREFIX.$_octet"
			return
		fi
		_octet=$((_octet + 1))
	done

	_dns=$(host "$1" | grep 'has address' | cut -f4 -d' ')
	if [ -n "$_dns" ]; then
		echo "$_dns"
		return
	fi

	# return error code
	return 2
}

get_jail_ip6()
{
	local _start=${JAIL_NET_START:=1}

	case "$1" in
		syslog) echo "$JAIL_NET6:$(dec_to_hex "$_start")";       return ;;
		base)   echo "$JAIL_NET6:$(dec_to_hex $((_start + 1)))"; return ;;
		stage)  echo "$JAIL_NET6:$(dec_to_hex 254)";             return ;;
	esac

	if echo "$1" | grep -q ^base; then
		echo "$JAIL_NET6:$(dec_to_hex $((_start + 1)))"
		return
	fi

	local _octet="$_start"

	for _j in $JAIL_ORDERED_LIST; do
		if [ "$1" = "$_j" ]; then
			echo "$JAIL_NET6:$(dec_to_hex "$_octet")"
			return
		fi
		_octet=$((_octet + 1))
	done

	_dns=$(host "$1" | grep 'has IPv6 address' | cut -f5 -d' ')
	if [ -n "$_dns" ]; then
		echo "$_dns"
		return
	fi

	# return error code
	return 2
}

# Write a jail's inbound mail port redirects to its pf.conf.d/rdr.conf.
# Port 25 (inbound MTA) follows $TOASTER_MTA; ports 465 and 587 (submission
# and SMTPS, the MSA) follow $TOASTER_MSA. A jail only claims the ports whose
# role names it, so exactly one jail redirects each port. Rewritten on every
# provision so the rules track the current settings; when a jail no longer owns
# any mail port its stale rdr.conf is removed.
configure_mta_pf_rdr()
{
	local _jail="$1"
	local _ports=""

	if [ "$TOASTER_MTA" = "$_jail" ]; then
		_ports="25"
	fi
	if [ "$TOASTER_MSA" = "$_jail" ]; then
		_ports="${_ports:+$_ports }465 587"
	fi

	local _conf _pf_etc
	_pf_etc="$(get_jail_host_etc "$_jail")/pf.conf.d"

	if [ -z "$_ports" ]; then
		for _conf in "$_pf_etc/rdr.conf" "$_pf_etc/filter.conf"; do
			if [ -f "$_conf" ]; then
				tell_status "removing mail port redirects from $_conf"
				rm -f "$_conf"
			fi
		done
		return 0
	fi

	configure_pf_jail_table "$_jail"

	store_config "$_pf_etc/rdr.conf" "overwrite" <<EO_PF_RDR
rdr inet  proto tcp from any to <ext_ip4> port { $_ports } -> $(get_jail_ip "$_jail")
rdr inet6 proto tcp from any to <ext_ip6> port { $_ports } -> $(get_jail_ip6 "$_jail")
EO_PF_RDR

	store_config "$_pf_etc/filter.conf" <<EO_PF_FILTER
pass in quick proto tcp from any to <$_jail> port { $_ports }
EO_PF_FILTER
}

configure_pf_jail_table()
{
	local _jail="$1"
	local _pf_etc
	_pf_etc="$(get_jail_host_etc "$_jail")/pf.conf.d"

	get_public_ip4
	get_public_ip6

	store_config "$_pf_etc/$_jail.table" <<EO_PF_TABLE
$PUBLIC_IP4
$PUBLIC_IP6
$(get_jail_ip "$_jail")
$(get_jail_ip6 "$_jail")
EO_PF_TABLE
}

get_reverse_ip()
{
	local _jail_ip; _jail_ip=$(get_jail_ip "$1")
	if [ -z "$_jail_ip" ]; then
		echo "unknown jail: $1" >&2
		exit 1
	fi

	local _rev_ip
	_rev_ip=$(echo "$_jail_ip" | awk '{split($1,a,".");printf("%s.%s.%s.%s",a[4],a[3],a[2],a[1])}')
	echo "$_rev_ip.in-addr.arpa"
}

get_reverse_ip6()
{
	_rev_ip=$(get_jail_ip6 "$1" | sed -e 's/://g' | rev | sed -e 's/./&./g')
	echo "${_rev_ip}ip6.arpa"
}

jail_conf_header()
{
	local _path="$ZFS_JAIL_MNT/$1"
	if [ "$1" = "base" ]; then _path="$BASE_MNT"; fi

	cat <<EO_JAIL_CONF_HEAD
exec.start = "/bin/sh /etc/rc";
exec.stop = "/bin/sh /etc/rc.shutdown";
exec.clean;
devfs_ruleset=5;
path = "$_path";
interface = $JAIL_NET_INTERFACE;
host.hostname = \$name;

EO_JAIL_CONF_HEAD
}

get_safe_jail_path()
{
	local _safe; _safe=$(safe_jailname "$1")
	if [ "$1" != "$_safe" ]; then
		echo "
		path = $ZFS_JAIL_MNT/${1};"
	else
		echo ""
	fi
}

get_jail_data()
{
	echo "$ZFS_DATA_MNT/$1"
}

# control files the host reads or runs on the jail's behalf, like fstab
get_jail_host_etc()
{
	printf '%s' "$ZFS_DATA_MNT/etc/$1"
}

jail_is_running()
{
	jls -d -j "$1" name 2>/dev/null | grep -q "$1"
}

stop_jail()
{
	tell_status "stopping jail $1"
	local _safe; _safe=$(safe_jailname "$1")
	if jail_is_running "$_safe"; then
		echo "service jail stop $_safe"
		if ! service jail stop "$_safe"; then
			echo "jail -r $_safe"
			if jail -r "$_safe" 2>/dev/null; then echo "removed"; fi
		fi
	fi

	if jail_is_running "$_safe"; then
		echo "jail -r $_safe"
		if jail -r "$_safe" 2>/dev/null; then echo "removed"; fi
	fi
}

jail_rename()
{
	if [ -z "$1" ] || [ -z "$2" ]; then
		echo "usage: $0 <existing jail name> <new jail name>" >&2
		exit 1
	fi

	echo "renaming $1 to $2"
	service jail stop "$1" || exit 1

	for _f in data jails
	do
		zfs unmount "$ZFS_VOL/$_f/$1"
		zfs rename "$ZFS_VOL/$_f/$1" "$ZFS_VOL/$_f/$2" || exit 1
		zfs set mountpoint="/$_f/$2" "$ZFS_VOL/$_f/$2" || exit 1
		zfs mount "$ZFS_VOL/$_f/$2"
	done

	sed_inplace \
		-e "/^$1[[:space:]]/ s/$1/$2/" \
		/etc/jail.conf || exit 1

	service jail start "$2"

	echo "Don't forget to update your PF and/or Haproxy rules"
}

assure_jail()
{
	local _jid; _jid=$(jls -j "$1" jid)
	if [ -z "$_jid" ]; then
		echo "jail $1 is required but not available" >&2
		exit 1
	fi
}

enable_jail()
{
	case " $(sysrc -n jail_list) " in *" $1 "*)
		#echo "jail $1 already enabled at startup"
		return ;;
	esac

	tell_status "enabling jail $1 at startup"
	sysrc jail_list+=" $1"
	sysrc -f /etc/periodic.conf security_status_pkgaudit_jails+=" $1"
}

jail_conf_mount()
{
	if [ "$1" = "base" ]; then
		echo "mount.devfs;"
		return
	fi

	echo "mount.fstab = \"$(get_jail_host_etc "$1")/fstab\";"
}

migrate_jail_conf_etc()
{
	# we should not depend on get_jail_data() changing its output here,
	# it's a migration from the state best described by $ZFS_DATA_MNT/$1/etc
	local _old_etc="$ZFS_DATA_MNT/$1/etc"
	local _new_etc; _new_etc="$(get_jail_host_etc "$1")"

	grep -qF "$_old_etc" "$2" || return

	tell_status "Migrating $_old_etc to $_new_etc in $2"
	sed_inplace -E -e '/^[[:space:]]*(mount\.fstab|exec\.(created|(post|pre)(start|stop)))[[:space:]]*\+?=/ s|'"$_old_etc|$_new_etc|" "$2"

	if grep -qF "$_old_etc" "$2"; then
		tell_status "WARNING: Could not reliably migrate $_old_etc to $_new_etc in $2. Please fix it manually."
	fi
}

warn_stale_jail_conf()
{
	local _jail="$1"
	local _conf="$2"

	local _mount; _mount=$(jail_conf_mount "$_jail")
	if grep -qsF "$_mount" "$_conf"; then return; fi

	tell_status "WARNING: $_conf is out of date"
	echo "  $_jail should declare: $_mount"
	echo "  edit $_conf, or delete the $_jail entry and run this script again"
	echo
}

add_jail_conf()
{
	local _jail_ip; _jail_ip=$(get_jail_ip "$1");
	if [ -z "$_jail_ip" ]; then
		fatal_err "can't determine IP for $1"
	fi

	if [ -d /etc/jail.conf.d ]; then
		add_jail_conf_d "$1"
		return
	fi

	if [ ! -e /etc/jail.conf ]; then
		tell_status "adding /etc/jail.conf header"
		jail_conf_header "$1" | tee -a /etc/jail.conf
	fi

	if grep -q "^$1\\>" /etc/jail.conf; then
		migrate_jail_conf_etc "$1" /etc/jail.conf
		tell_status "preserving $1 config in /etc/jail.conf"
		warn_stale_jail_conf "$1" /etc/jail.conf
		return
	fi

	tell_status "adding $1 to /etc/jail.conf"
	echo "$1	{$(get_safe_jail_path "$1")
		$(jail_conf_mount "$1")
		ip4.addr = $JAIL_NET_INTERFACE|${_jail_ip};
		ip6.addr = $JAIL_NET_INTERFACE|$(get_jail_ip6 "$1");${JAIL_CONF_EXTRA}
	}" | tee -a /etc/jail.conf
}

add_jail_conf_d()
{
	local _jail_ip; _jail_ip=$(get_jail_ip "$1")
	if [ -z "$_jail_ip" ]; then
		fatal_err "can't determine IP for $1"
	fi

	# configure IPv6 if the system has an external/public IPv6 address
	local _IP6=""
	get_public_ip6
	if [ -n "$PUBLIC_IP6" ]; then
		_IP6="ip6.addr = $JAIL_NET_INTERFACE|$(get_jail_ip6 "$1");"
	fi

	local _path="$ZFS_JAIL_MNT/$1"
	if [ "$1" = "base" ]; then _path="$BASE_MNT"; fi

	# base redirects no ports, so the host has no pf rules to run for it
	local _pf_exec=""
	if [ "$1" != "base" ]; then
		_pf_exec="
		exec.created = \"$(get_jail_host_etc "$1")/pf.conf.d/pfrule.sh load\";
		exec.poststop = \"$(get_jail_host_etc "$1")/pf.conf.d/pfrule.sh unload\";"
	fi

	local _conf; _conf="/etc/jail.conf.d/$(safe_jailname "$1").conf"

	store_config "$_conf" "update" <<EO_JAIL_RC
$(safe_jailname "$1")	{$(get_safe_jail_path "$1")
		host.hostname = \$name;
		path = "$_path";
		$(jail_conf_mount "$1")
		devfs_ruleset=5;

		ip4.addr = $JAIL_NET_INTERFACE|${_jail_ip};
		${_IP6}${JAIL_CONF_EXTRA}

		exec.clean;
		exec.start = "/bin/sh /etc/rc";
		exec.stop = "/bin/sh /etc/rc.shutdown";$_pf_exec
	}
EO_JAIL_RC
	migrate_jail_conf_etc "$1" "$_conf.mt6"
	migrate_jail_conf_etc "$1" "$_conf"

	warn_stale_jail_conf "$1" "$_conf"
}

add_automount()
{
	if grep -qs auto_ports /etc/auto_master; then
		if grep -qs "^$ZFS_JAIL_MNT/$1/" /etc/auto_ports; then
			tell_status "automount ports already configured"
		else
			tell_status "enabling /usr/ports automount"
			echo "$ZFS_JAIL_MNT/$1/usr/ports		-fstype=nullfs :/usr/ports" | tee -a /etc/auto_ports
			/usr/sbin/automount
		fi
	else
		echo "automount not enabled, see https://github.com/msimerson/Mail-Toaster-6/wiki/automount"
	fi

	if grep -qs auto_pkgcache /etc/auto_master; then
		if grep -qs "^$ZFS_JAIL_MNT/$1/" /etc/auto_pkgcache; then
			tell_status "automount pkg cache already configured"
		else
			tell_status "enabling /var/cache/pkg automount"
			echo "$ZFS_JAIL_MNT/$1/var/cache/pkg		-fstype=nullfs :/var/cache/pkg" | tee -a /etc/auto_pkgcache
			/usr/sbin/automount
		fi
	fi
}

assure_ip6_addr_is_declared()
{
	if ! grep -qs "^$1" /etc/jail.conf; then
		# config for this jail hasn't been created yet
		return
	fi

	if awk "/^$1/,/}/" /etc/jail.conf | grep -q ip6; then
		echo "ip6.addr is already declared"
		return
	fi

	tell_status "adding ip6.addr to $1 section in /etc/jail.conf"
	sed_inplace \
		-e "/^$1/,/ip4/ s/ip4.*;/&\\
		ip6.addr = $JAIL_NET_INTERFACE|$(get_jail_ip6 "$1");/" \
		/etc/jail.conf
}
