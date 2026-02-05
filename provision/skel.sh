#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

install_skel()
{
	tell_status "install skel"

	#stage_pkg_install 
	#stage_exec
}

configure_skel()
{
	tell_status "configuring skel"
}

start_skel()
{
	tell_status "starting up skel"
	#stage_sysrc
	#stage_exec
}

test_skel()
{
	tell_status "testing skel"
	#stage_test_running
	#stage_listening
}

base_snapshot_exists || exit
create_staged_fs skel
start_staged_jail skel
install_skel
configure_skel
start_skel
test_skel
promote_staged_jail skel
