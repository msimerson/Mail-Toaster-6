#!/bin/sh

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
}

get_public_ip()
{
	local _ver=${1:-"ipv4"}

	get_public_facing_nic "$_ver"

	if [ "$_ver" = "ipv6" ]; then
		export PUBLIC_IP6
		PUBLIC_IP6=$(ifconfig "$PUBLIC_NIC" inet6 | grep inet | grep -v fe80 | awk '{print $2}' | head -n1)
	else
		export PUBLIC_IP4
		PUBLIC_IP4=$(ifconfig "$PUBLIC_NIC" inet | grep inet | awk '{print $2}' | head -n1)
	fi
}

get_random_ip6net()
{
	# shellcheck disable=2039
	local RAND16
	RAND16=$(od -t uI -N 2 /dev/urandom | awk '{print $2}')
	echo "fd7a:e5cd:1fc1:$(dec_to_hex "$RAND16"):dead:beef:cafe"
}

install_pfrule()
{
	local _pfdir
	_pfdir="$(get_jail_data $1)/etc/pf.conf.d"

	mt6-fetch contrib pfrule.sh
	install -d "$_pfdir"
	install -C -m 0755 contrib/pfrule.sh "$_pfdir/pfrule.sh"
}

port_is_listening()
{
	local _port=${1:-"25"}
	local _jail=${2:-"stage"}

	if [ -n "$(sockstat -l -q -4 -6 -p "$_port" -j "$_jail")" ]; then
		true
	else
		false
	fi
}