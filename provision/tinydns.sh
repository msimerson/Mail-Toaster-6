#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_tinydns()
{
	tell_status "installing djbdns"
	stage_pkg_install rsync dialog4ports daemontools || exit

	if [ ! -d "$STAGE_MNT/data/home" ]; then
		mkdir "$STAGE_MNT/data/home" || exit
	fi
	stage_exec pw useradd tinydns -d /data/home/tinydns -m

	tell_status "installing ucspi-tcp with IPv6"
	stage_make_conf sysutils_ucspi-tcp_SET 'sysutils_ucspi-tcp_SET=IPV6'
	stage_port_install sysutils/ucspi-tcp || exit

	tell_status "installing djbdns with IPv6"
	stage_make_conf dns_djbdns_SET 'dns_djbdns_SET=IP6'
	stage_port_install dns/djbdns || exit
}

configure_svscan()
{
	if [ ! -d "$STAGE_MNT/var/service" ]; then
		tell_status "creating default service dir"
		mkdir -p "$STAGE_MNT/var/service" || exit
	fi

	if [ ! -d "$STAGE_MNT/data/service" ]; then
		tell_status "creating local service dir"
		mkdir -p "$STAGE_MNT/data/service" || exit
	fi
}

configure_tinydns4()
{
	tell_status "creating tinydns server"
	stage_exec tinydns-conf tinydns bin /var/service/tinydns "$(get_jail_ip stage)"
	store_config "$STAGE_MNT/var/service/tinydns/run" "overwrite" <<EO_TINYDNS_RUN
#!/bin/sh

# logging enabled
#exec 2>&1

# logging disabled
exec 1>/dev/null 2>&1

exec envuidgid tinydns envdir ./env softlimit -d300000 /usr/local/bin/tinydns
EO_TINYDNS_RUN

	echo "/data/root" > "$STAGE_MNT/var/service/tinydns/env/ROOT" || exit
}

configure_tinydns6()
{
	tell_status "creating tinydns IPv6 server"
	stage_exec tinydns-conf tinydns bin /var/service/tinydns-v6 "$(get_jail_ip6 stage)"
	store_config "$STAGE_MNT/var/service/tinydns-v6/run" "overwrite" <<EO_TINYDNS_RUN
#!/bin/sh

# logging enabled
#exec 2>&1

# logging disabled
exec 1>/dev/null 2>&1

exec envuidgid tinydns envdir ./env softlimit -d300000 /usr/local/bin/tinydns
EO_TINYDNS_RUN

	echo "/data/root" > "$STAGE_MNT/var/service/tinydns-v6/env/ROOT" || exit
}

configure_tinydns()
{
	configure_svscan
	configure_tinydns4
	configure_tinydns_data
	configure_tinydns6
}

configure_tinydns_data()
{
	if [ -d "$ZFS_DATA_MNT/tinydns/root" ]; then
		tell_status "tinydns data already configured"
		return
	fi

	tell_status "configuring tinydns data"
	mv "$STAGE_MNT/var/service/tinydns/root" "$ZFS_DATA_MNT/tinydns/root"
	tee -a "$ZFS_DATA_MNT/tinydns/root/data" <<EO_EXAMPLE
.example.com:1.2.3.4:a:259200
=www.example.com:1.2.3.5:86400
EO_EXAMPLE
	stage_exec make -C /data/root
	stage_exec chown -R tinydns /data/root
}

configure_axfrdns()
{
	tell_status "creating axfrdns server"
	stage_exec axfrdns-conf tinydns bin /var/service/axfrdns /data "$(get_jail_ip stage)"
	store_config "$STAGE_MNT/var/service/axfrdns/run" "overwrite" <<'EO_AXFRDNS_RUN'
#!/bin/sh

# logging enabled
#exec 2>&1

# logging disabled
exec 1>/dev/null 2>&1

exec envdir ./env sh -c '
	exec envuidgid tinydns softlimit -d300000 tcpserver -vDRHl0 -x tcp.cdb -- "$IP" 53 /usr/local/bin/axfrdns
'
EO_AXFRDNS_RUN

	store_config "$STAGE_MNT/var/service/axfrdns/tcp" "overwrite" <<EOTCP
:allow,AXFR=""
:deny
EOTCP
	stage_exec make -C /var/service/axfrdns
}

configure_axfrdns6()
{
	tell_status "creating axfrdns IPv6 server"
	stage_exec axfrdns-conf tinydns bin /var/service/axfrdns-v6 /data "$(get_jail_ip6 stage)"
	store_config "$STAGE_MNT/var/service/axfrdns-v6/run" "overwrite" <<'EO_AXFRDNS_RUN'
#!/bin/sh

# logging enabled
#exec 2>&1

# logging disabled
exec 1>/dev/null 2>&1

exec envdir ./env sh -c '
	exec envuidgid tinydns softlimit -d300000 tcpserver -vDRHl0 -x tcp.cdb -- "$IP" 53 /usr/local/bin/axfrdns
'
EO_AXFRDNS_RUN

	store_config "$STAGE_MNT/var/service/axfrdns-v6/tcp" "overwrite" <<EOTCP6
:allow,AXFR=""
:deny
EOTCP6
	stage_exec make -C /var/service/axfrdns-v6
}

start_tinydns()
{
	tell_status "starting dns daemons"
	stage_sysrc svscan_enable="YES"
	stage_sysrc sshd_enable="YES"
	stage_exec service svscan start || exit
}

test_tinydns()
{
	tell_status "testing tinydns"
	stage_test_running tinydns

	stage_listening 53
	echo "tinydns is running."

	local _fqdn="www.example.com"
	if ! grep -qs "$_fqdn" "$ZFS_DATA_MNT/tinydns/root/data"; then
		_fqdn="$TOASTER_HOSTNAME"
	fi

	tell_status "testing UDP DNS query"
	drill    "$_fqdn" @"$(get_jail_ip stage)" || exit

	tell_status "testing TCP DNS query"
	drill -t "$_fqdn" @"$(get_jail_ip stage)" || exit

	tell_status "switching tinydns IP to deployment IP"
	get_jail_ip tinydns | tee "$STAGE_MNT/var/service/tinydns/env/IP" "$STAGE_MNT/var/service/axfrdns/env/IP"
	get_jail_ip6 tinydns | tee "$STAGE_MNT/var/service/tinydns-v6/env/IP" "$STAGE_MNT/var/service/axfrdns-v6/env/IP"

	stage_exec service svscan stop || exit
	for d in tinydns axfrdns tinydns-v6 axfrdns-v6
	do
		if [ ! -d "$ZFS_DATA_MNT/tinydns/service/$d" ]; then
			tell_status "moving $d from staging to production"
			mv "$STAGE_MNT/var/service/$d" "$ZFS_DATA_MNT/tinydns/service/"
		fi
	done
	stage_sysrc svscan_servicedir="/data/service"
}

base_snapshot_exists || exit
create_staged_fs tinydns
start_staged_jail tinydns
install_tinydns
configure_tinydns
configure_axfrdns
configure_axfrdns6
start_tinydns
test_tinydns
promote_staged_jail tinydns
