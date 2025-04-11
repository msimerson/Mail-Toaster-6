#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include user

install_nsd()
{
	tell_status "installing NSD"
	stage_pkg_install nsd rsync || exit

	if [ ! -d "$STAGE_MNT/data/home/nsd" ]; then
		mkdir -p "$STAGE_MNT/data/home/nsd" || exit
		chown 216:216 "$STAGE_MNT/data/home/nsd"
	fi

	stage_exec pw user mod nsd -u 216 -g 216 -s /bin/sh -d /data/home/nsd
}

configure_nsd()
{
	stage_sysrc nsd_enable=YES
	stage_sysrc nsd_config=/data/etc/nsd.conf
	stage_sysrc sshd_enable=YES

	if [ ! -d "$STAGE_MNT/data/etc" ]; then
		mkdir "$STAGE_MNT/data/etc"
	fi

	if [ ! -f "$STAGE_MNT/data/etc/nsd.conf" ]; then
		tell_status "installing default nsd.conf"
		cp "$STAGE_MNT/usr/local/etc/nsd/nsd.conf" "$STAGE_MNT/data/etc/"
	else
		tell_status "linking custom nsd.conf to /usr/local"
		rm "$STAGE_MNT/usr/local/etc/nsd/nsd.conf"
		stage_exec ln -s /data/etc/nsd.conf /usr/local/etc/nsd/nsd.conf
	fi

	if [ ! -d "$STAGE_MNT/data/etc" ]; then
		mkdir "$STAGE_MNT/data/etc"
	fi

	if [ ! -f "$STAGE_MNT/data/etc/nsd.conf" ]; then
		tell_status "installing default nsd.conf"
		cp "$STAGE_MNT/usr/local/etc/nsd/nsd.conf" "$STAGE_MNT/data/etc/"
	fi

	preserve_passdb nsd
}

start_nsd()
{
	tell_status "starting nsd daemon"
	stage_exec service nsd start || exit
}

test_nsd()
{
	tell_status "testing nsd"
	stage_test_running nsd

	stage_listening 53
	echo "it worked."

	tell_status "testing UDP DNS query"
	drill    www.example.com @"$(get_jail_ip stage)" || exit

	tell_status "testing TCP DNS query"
	drill -t www.example.com @"$(get_jail_ip stage)" || exit
}

# mt6-include djb

install_tinydns()
{
	tell_status "installing djbdns"
	stage_pkg_install rsync daemontools || exit

	if [ ! -d "$STAGE_MNT/data/home" ]; then
		mkdir "$STAGE_MNT/data/home" || exit
	fi
	stage_exec pw useradd tinydns -d /data/home/tinydns -m

	tell_status "installing ucspi-tcp with IPv6"
	stage_make_conf sysutils_ucspi-tcp_SET 'sysutils_ucspi-tcp_SET=IPV6'
	stage_port_install sysutils/ucspi-tcp || exit

	install_djbdns_source
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
	tee "$STAGE_MNT/var/service/tinydns/run" <<EO_TINYDNS_RUN
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
	tee "$STAGE_MNT/var/service/tinydns-v6/run" <<EO_TINYDNS_RUN
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
	stage_sysrc hostname="ns3.theartfarm.com"
	#configure_tinydns6
}

configure_tinydns_data()
{
	if [ -d "$ZFS_DATA_MNT/ns3.theartfarm.com/root" ]; then
		tell_status "tinydns data already configured"
		return
	fi

	tell_status "configuring tinydns data"
	mv "$STAGE_MNT/var/service/tinydns/root" "$ZFS_DATA_MNT/ns3.theartfarm.com/root"
	tee -a "$ZFS_DATA_MNT/ns3.theartfarm.com/root/data" <<EO_EXAMPLE
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
	tee "$STAGE_MNT/var/service/axfrdns/run" <<'EO_AXFRDNS_RUN'
#!/bin/sh

# logging enabled
#exec 2>&1

# logging disabled
exec 1>/dev/null 2>&1

exec envdir ./env sh -c '
	exec envuidgid tinydns softlimit -d300000 tcpserver -vDRHl0 -x tcp.cdb -- "$IP" 53 /usr/local/bin/axfrdns
'
EO_AXFRDNS_RUN

	tee "$STAGE_MNT/var/service/axfrdns/tcp" <<EOTCP
:allow,AXFR=""
:deny
EOTCP
	stage_exec make -C /var/service/axfrdns
}

configure_axfrdns6()
{
	tell_status "creating axfrdns IPv6 server"
	stage_exec axfrdns-conf tinydns bin /var/service/axfrdns-v6 /data "$(get_jail_ip6 stage)"
	tee "$STAGE_MNT/var/service/axfrdns-v6/run" <<'EO_AXFRDNS_RUN'
#!/bin/sh

# logging enabled
#exec 2>&1

# logging disabled
exec 1>/dev/null 2>&1

exec envdir ./env sh -c '
	exec envuidgid tinydns softlimit -d300000 tcpserver -vDRHl0 -x tcp.cdb -- "$IP" 53 /usr/local/bin/axfrdns
'
EO_AXFRDNS_RUN

	tee "$STAGE_MNT/var/service/axfrdns-v6/tcp" <<EOTCP6
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

	local _fqdn="ns3.theartfarm.com"

	tell_status "testing UDP DNS query"
	drill    "$_fqdn" @"$(get_jail_ip stage)" || exit

	tell_status "testing TCP DNS query"
	drill -t "$_fqdn" @"$(get_jail_ip stage)" || exit

	tell_status "switching tinydns IP to deployment IP"
	echo 138.210.133.60 | tee "$STAGE_MNT/var/service/tinydns/env/IP" "$STAGE_MNT/var/service/axfrdns/env/IP"
	#get_jail_ip6 ns3.theartfarm.com | tee "$STAGE_MNT/var/service/tinydns-v6/env/IP" "$STAGE_MNT/var/service/axfrdns-v6/env/IP"

	stage_exec service svscan stop || exit
	for d in tinydns axfrdns tinydns-v6 axfrdns-v6
	do
		if [ ! -d "$ZFS_DATA_MNT/ns3.theartfarm.com/service/$d" ]; then
			tell_status "moving $d from staging to production"
			mv "$STAGE_MNT/var/service/$d" "$ZFS_DATA_MNT/ns3.theartfarm.com/service/"
		fi
	done
	stage_sysrc svscan_servicedir="/data/service"
}

base_snapshot_exists || exit
create_staged_fs ns3.theartfarm.com
start_staged_jail ns3.theartfarm.com
install_nsd
configure_nsd
start_nsd
test_nsd
# install_tinydns
# configure_tinydns
# configure_axfrdns
# configure_axfrdns6
# start_tinydns
# test_tinydns
promote_staged_jail ns3.theartfarm.com
