#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

install_dhcpd
{
	tell_status "installing dhcpd"
	stage_pkg_install dhcpd || exit
}

configure_dhcpd()
{

}

start_dhcpd()
{
	tell_status "starting dhcpd"
	stage_sysrc dhcpd_enable=YES
	stage_exec service dhcpd start || exit
}

test_dhcpd()
{
	echo "it worked."
}

base_snapshot_exists || exit
create_staged_fs dhcp
start_staged_jail
install_dhcpd
configure_dhcpd
start_dhcpd
test_dhcpd
promote_staged_jail dhcp
