#!/bin/sh

. mail-toaster.sh || exit

export JAIL_CONF_EXTRA=""
export JAIL_FSTAB="fdescfs $ZFS_JAIL_MNT/unifi/dev/fd fdescfs rw 0 0
proc     $ZFS_JAIL_MNT/unifi/proc   procfs  rw 0 0"

install_unifi()
{
	tell_status "installing Unifi deps"
	stage_pkg_install mongodb44 openjdk17 snappyjava gmake || exit

	tell_status "installing Unifi"
	stage_port_install net-mgmt/unifi8 || exit

	tell_status "Enable UniFi"
	stage_sysrc unifi_enable=YES
}

configure_unifi()
{
	true;
	# /usr/local/share/java/unifi/data/system.properties
	#"db.mongo.local=false"
	#"db.mongo.uri=mongodb://ubnt:password@IP_ADDRESS:PORT/unifi-test"
	#"statdb.mongo.uri=mongodb://ubnt:password@IP_ADDRESS:PORT/unifi-test_stat"
	#"unifi.db.name=unifi-test"
}

start_unifi()
{
	stage_exec service unifi start
}

test_unifi()
{
	stage_test_running java
	sleep 1
}

base_snapshot_exists || exit
create_staged_fs unifi
start_staged_jail unifi
install_unifi
configure_unifi
start_unifi
test_unifi
promote_staged_jail unifi
