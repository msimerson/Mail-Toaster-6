#!/bin/sh

set -e -u

. mail-toaster.sh

export JAIL_START_EXTRA="devfs_ruleset=7
		allow.raw_sockets=1"
export JAIL_CONF_EXTRA="
		devfs_ruleset = 7;
		allow.raw_sockets;"
export JAIL_FSTAB=""

install_dhcpd()
{
	tell_status "installing dhcpd"
	stage_pkg_install isc-dhcp44-server
}

configure_dhcpd()
{
	tell_status "configuring isc-dhcpd"
	stage_sysrc dhcpd_enable="YES"
	stage_sysrc dhcpd_flags="-q"
	stage_sysrc dhcpd_conf="/data/etc/dhcpd.conf"
	stage_sysrc dhcpd_ifaces=""
	stage_sysrc dhcpd_withumask="022"
	stage_sysrc dhcpd_chroot_enable="NO"
	stage_sysrc dhcpd_devfs_enable="NO"
	stage_sysrc dhcpd_rootdir="/data/db"	# directory to run in
	echo "configured"

	_pf_etc="$ZFS_DATA_MNT/dhcp/etc/pf.conf.d"
	store_config "$_pf_etc/rdr.conf" <<EO_PF_RDR
rdr inet  proto tcp from any to <ext_ips> port { 67 68 } -> $(get_jail_ip  dhcp)
rdr inet6 proto tcp from any to <ext_ips> port { 67 68 } -> $(get_jail_ip6 dhcp)
EO_PF_RDR

	if [ ! -d "$ZFS_DATA_MNT/dhcp/etc" ]; then
		mkdir -p "$ZFS_DATA_MNT/dhcp/etc"
	fi

	if [ ! -d "$ZFS_DATA_MNT/dhcp/db" ]; then
		mkdir -p "$ZFS_DATA_MNT/dhcp/db"
	fi

	get_public_ip
	store_config "$ZFS_DATA_MNT/dhcp/etc/dhcpd.conf" <<EO_DHCP
option domain-name "$TOASTER_MAIL_DOMAIN";
# option domain-name-servers $PUBLIC_IP4;

default-lease-time 6000;
max-lease-time 9200;

get-lease-hostnames true;

authoritative;

# ad-hoc DNS update scheme - set to "none" to disable dynamic DNS updates.
ddns-update-style none;

log-facility local7;

# No service will be given on this subnet, but declaring it helps the
# DHCP server to understand the network topology.
subnet 172.16.0.0 netmask 255.240.0.0 {
}

# subnet 10.0.3.0 netmask 255.255.255.0 {
#  range 10.0.3.200 10.0.3.250;
#  option routers 10.0.3.1;
#  option broadcast-address 10.0.3.255;
#  default-lease-time 1000;
#  option domain-name "example.com";
#  option domain-name-servers 10.0.3.1, 8.8.8.8, 8.8.4.4;
#}

EO_DHCP

}

start_dhcpd()
{
	tell_status "starting dhcpd"
	stage_exec service isc-dhcpd start
}

test_dhcpd()
{
	stage_test_running dhcpd
	stage_listening 68
	echo "it worked."
}

base_snapshot_exists || exit
create_staged_fs dhcp
start_staged_jail dhcp
install_dhcpd
configure_dhcpd
start_dhcpd
test_dhcpd
promote_staged_jail dhcp
