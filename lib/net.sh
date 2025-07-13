#!/bin/sh

set -e

get_jail_ip()
{
	local _start=${JAIL_NET_START:=1}

	case "$1" in
		syslog) echo "$JAIL_NET_PREFIX.$_start";   return;;
		base)   echo "$JAIL_NET_PREFIX.$((_start + 1))";   return;;
		stage)  echo "$JAIL_NET_PREFIX.254"; return;;
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
		syslog) echo "$JAIL_NET6:$(dec_to_hex "$_start")";       return;;
		base)   echo "$JAIL_NET6:$(dec_to_hex $((_start + 1)))"; return;;
		stage)  echo "$JAIL_NET6:$(dec_to_hex 254)";             return;;
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

get_public_facing_nic()
{
	local _ver=${1:-"ipv4"}

	export PUBLIC_NIC

	if [ "$_ver" = 'ipv6' ]; then
		PUBLIC_NIC=$(netstat -rn | grep default | awk '{ print $4 }' | tail -n1)
	else
		PUBLIC_NIC=$(netstat -rn | grep default | awk '{ print $4 }' | head -n1)
	fi

	if [ -z "$PUBLIC_NIC" ];
	then
		echo "public NIC detection failed"
		exit 1
	fi

	echo "$PUBLIC_NIC"
}

get_public_ip()
{
	local _ver=${1:-"ipv4"}

	get_public_facing_nic "$_ver"

	export PUBLIC_IP6
	export PUBLIC_IP4

	if [ "$_ver" = "ipv6" ]; then
		PUBLIC_IP6=$(ifconfig "$PUBLIC_NIC" inet6 | grep inet | grep -v fe80 | awk '{print $2}' | head -n1)
		echo "$PUBLIC_IP6"
	else
		PUBLIC_IP4=$(ifconfig "$PUBLIC_NIC" inet | grep inet | awk '{print $2}' | head -n1)
		echo "$PUBLIC_IP4"
	fi
}

get_reverse_ip()
{
	local _jail_ip; _jail_ip=$(get_jail_ip "$1")
	if [ -z "$_jail_ip" ]; then
		echo "unknown jail: $1"
		exit
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
