#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
# shellcheck disable=2016
export JAIL_CONF_EXTRA="
                mount.fdescfs;
                mount.procfs;"

install_unifi()
{
	tell_status "installing Unifi deps"
	stage_pkg_install mongodb34 openjdk8 gmake || exit

	tell_status "installing Unifi"
	stage_port_install net-mgmt/unifi5 || exit

	tell_status "Enable UniFi 5"
	stage_sysrc unifi_enable=YES
	stage_sysrc mongod_enable=YES
}

start_unifi()
{
	stage_exec service mongod start
	stage_exec service unifi start
}

test_unifi()
{
	stage_test_running mongod
	sleep 1
	stage_test_running java
	sleep 1
}

base_snapshot_exists || exit
create_staged_fs unifi
start_staged_jail unifi
install_unifi
start_unifi
test_unifi
promote_staged_jail unifi
