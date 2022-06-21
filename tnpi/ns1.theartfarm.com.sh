#!/bin/sh

set -e

. mail-toaster.sh
. include/djb.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

configure_tinydns()
{
	configure_svscan
	configure_tinydns4
	configure_tinydns_data
	configure_tinydns6
	stage_sysrc sshd_enable="YES"
}

configure_tinydns_data()
{
	_data_root="$ZFS_DATA_MNT/ns1.theartfarm.com/root"
	if [ -d "$_data_root" ]; then
		tell_status "tinydns data already configured"
		return
	fi

	tell_status "configuring tinydns data"
	mv "$STAGE_MNT/var/service/tinydns/root" "$_data_root"
	tee -a "$_data_root/data" <<EO_EXAMPLE
.example.com:1.2.3.4:a:259200
=www.example.com:1.2.3.5:86400
EO_EXAMPLE
	stage_exec make -C /data/root
	stage_exec chown -R tinydns /data/root
}

test_tinydns()
{
	tell_status "testing tinydns"
	stage_test_running tinydns

	stage_listening 53
	echo "tinydns is running."

	local _fqdn="ns1.theartfarm.com"

	tell_status "testing UDP DNS query for $_fqdn"
	drill    "$_fqdn" @"$(get_jail_ip stage)" || exit

	tell_status "testing TCP DNS query for $_fqdn"
	drill -t "$_fqdn" @"$(get_jail_ip stage)" || exit

	tell_status "switching tinydns IP to deployment IP"
	get_jail_ip tinydns | tee "$STAGE_MNT/var/service/tinydns/env/IP" "$STAGE_MNT/var/service/axfrdns/env/IP"
	get_jail_ip6 tinydns | tee "$STAGE_MNT/var/service/tinydns-v6/env/IP" "$STAGE_MNT/var/service/axfrdns-v6/env/IP"

	stage_exec service svscan stop || exit
	for d in tinydns axfrdns tinydns-v6 axfrdns-v6
	do
		if [ -d "$ZFS_DATA_MNT/ns1.theartfarm.com/service/$d" ]; then
			tell_status "preserving $d service definition"
		else
			tell_status "moving $d from staging to production"
			mv "$STAGE_MNT/var/service/$d" "$ZFS_DATA_MNT/ns1.theartfarm.com/service/"
		fi
	done
	stage_sysrc svscan_servicedir="/data/service"
}

base_snapshot_exists || exit
create_staged_fs ns1.theartfarm.com
start_staged_jail ns1.theartfarm.com
install_daemontools
install_ucspi_tcp
install_djbdns
configure_tinydns
configure_axfrdns4
configure_axfrdns6
start_tinydns
test_tinydns
promote_staged_jail ns1.theartfarm.com
