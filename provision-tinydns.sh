#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_tinydns()
{
	tell_status "installing djbdns"
	stage_pkg_install djbdns rsync dialog4ports || exit

	if [ ! -d "$STAGE_MNT/data/home" ]; then
		mkdir "$STAGE_MNT/data/home" || exit
	fi
	stage_exec pw useradd tinydns -d /data/home/tinydns -m

	tell_status "installing djbdns with IPv6 support"
	tee -a "$STAGE_MNT/etc/make.conf" <<EO_MAKE_CONF
dns_djbdns_SET=IP6
sysutils_ucspi-tcp_SET=IPV6
EO_MAKE_CONF
	stage_exec make -C /usr/ports/sysutils/ucspi-tcp build deinstall install clean
	stage_exec pkg delete -y djbdns
	stage_exec make -C /usr/ports/dns/djbdns build deinstall install clean
}

configure_tinydns()
{
	tell_status "creating default service dir"
	mkdir -p "$STAGE_MNT/var/service" || exit

	if [ ! -d "$STAGE_MNT/data/service" ]; then
		tell_status "creating local service dir"
		mkdir -p "$STAGE_MNT/data/service" || exit
	fi

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

	if [ ! -d "$ZFS_DATA_MNT/tinydns/root" ]; then
		tell_status "configuring tinydns data"
		mv "$STAGE_MNT/var/service/tinydns/root" "$ZFS_DATA_MNT/tinydns/root"
		tee -a "$ZFS_DATA_MNT/tinydns/root/data" <<EO_EXAMPLE
.example.com:1.2.3.4:a:259200
=www.example.com:1.2.3.5:86400
EO_EXAMPLE
		stage_exec make -C /data/root
	fi
	stage_exec chown -R tinydns /data/root
	echo "/data/root" > "$STAGE_MNT/var/service/tinydns/env/ROOT" || exit
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
	echo "it worked."

	tell_status "testing UDP DNS query"
	drill    www.example.com @"$(get_jail_ip stage)" || exit

	tell_status "testing TCP DNS query"
	drill -t www.example.com @"$(get_jail_ip stage)" || exit

	tell_status "switching tinydns IP to deployment IP"
	get_jail_ip tinydns | tee "$STAGE_MNT/var/service/tinydns/env/IP" "$STAGE_MNT/var/service/axfrdns/env/IP"

	stage_exec service svscan stop || exit
	for d in tinydns axfrdns
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
start_staged_jail
install_tinydns
configure_tinydns
configure_axfrdns
start_tinydns
test_tinydns
promote_staged_jail tinydns
