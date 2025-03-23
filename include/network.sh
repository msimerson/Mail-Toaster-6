#!/bin/sh

get_public_facing_nic()
{
	local _ver=${1:-"ipv4"}

	export PUBLIC_NIC

	if [ "$_ver" = 'ipv6' ]; then
		PUBLIC_NIC=$(netstat -rnW | awk '/^default/ { print $6 }' | tail -n1)
	else
		PUBLIC_NIC=$(netstat -rnW | awk '/^default/ { print $6 }' | head -n1)
	fi

	if [ -z "$PUBLIC_NIC" ]; then
		echo "public NIC detection failed" >&2
		exit 1
	fi
}

get_public_ip()
{
	local _ver=${1:-"ipv4"}

	if [ "$_ver" = "ipv6" ]; then
		get_public_ip6
	else
		get_public_ip4
	fi
}

get_public_ip4()
{
	# callers rely on the PUBLIC_NIC this exports, so look it up either way
	get_public_facing_nic ipv4

	# PUBLIC_IP4 is the public facing address, which need not be bound to a
	# local interface. ifconfig finds it only where the two coincide, so a
	# configured value wins.
	if [ -n "$PUBLIC_IP4" ]; then return; fi

	export PUBLIC_IP4
	PUBLIC_IP4=$(ifconfig "$PUBLIC_NIC" inet | grep inet | awk '{print $2}' | head -n1)
}

get_public_ip6()
{
	# callers rely on the PUBLIC_NIC this exports, so look it up either way
	get_public_facing_nic ipv6

	if [ -n "$PUBLIC_IP6" ]; then return; fi

	export PUBLIC_IP6
	PUBLIC_IP6=$(ifconfig "$PUBLIC_NIC" inet6 | grep inet6 | grep -v fe80 | awk '{print $2}' | head -n1)
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
	_pfdir="$(get_jail_host_etc "$1")/pf.conf.d"

	mt6-fetch contrib pfrule.sh
	install -d -m 0755 "$_pfdir"
	install -C -m 0755 contrib/pfrule.sh "$(get_pfrule_path)"
}

port_is_listening()
{
	local _port=${1:-"25"}
	local _jail=${2:-"stage"}

	sockstat -l -q -4 -6 -p "$_port" -j "$_jail" | grep -q .
}

install_acme_sh()
{
	stage_pkg_install acme.sh

	# use a home directory that persists across deployments
	stage_exec sh -c "[ -d /data/home/acme ] || mkdir -p /data/home/acme"
	stage_exec pw usermod acme -d /data/home/acme

	stage_exec sh -c "[ -e /data/home/acme/deploy] || ln -s /usr/local/share/examples/acme.sh/deploy /data/home/acme/deploy"
	stage_exec ln -s /data/home/acme /root/.acme.sh

	# renew the certs automatically
	store_exec "$STAGE_MNT/usr/local/etc/periodic/daily/acme.sh" <<EO_ACME_CRON
#!/usr/local/bin/bash
/usr/local/sbin/acme.sh --cron
EO_ACME_CRON
}

install_minimal_hosts()
{
	store_config "$STAGE_MNT/etc/hosts" "append" <<EO_HOSTS
$(get_jail_ip syslog) syslog
$(get_jail_ip bsd_cache) pkg vulnxml freebsd-update
EO_HOSTS
}
