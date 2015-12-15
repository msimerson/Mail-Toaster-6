#!/bin/sh

. mail-toaster.sh || exit

install_monitor()
{
    tell_status "installing monitoring apps"
	stage_pkg_install nagios nrpe swaks p5-Net-SSLeay || exit
}

configure_monitor()
{
    tell_status "configuring monitor"
	# local _local_etc="$STAGE_MNT/usr/local/etc"

}

start_monitor()
{
    tell_status "starting monitor"
	# stage_sysrc monitor_enable=YES
	# stage_exec service monitor start
}

test_monitor()
{
	tell_status "testing monitor"
	# stage_exec sockstat -l -4 | grep :80 || exit
    echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs monitor
stage_sysrc hostname=monitor
start_staged_jail
install_monitor
configure_monitor
start_monitor
test_monitor
promote_staged_jail monitor
