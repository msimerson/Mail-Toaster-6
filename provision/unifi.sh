#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB="fdescfs	$ZFS_JAIL_MNT/unifi/dev/fd	fdescfs	rw	0	0
$ZFS_DATA_MNT/unifi/java	$ZFS_JAIL_MNT/unifi/usr/local/share/java	nullfs	rw	0	0
proc	$ZFS_JAIL_MNT/unifi/proc	procfs	rw	0	0"

create_unifi_mountpoints()
{
	mkdir -p "$ZFS_JAIL_MNT/unifi/usr/local/share/java"

	if [ ! -d "$ZFS_DATA_MNT/unifi/java" ]; then
		mkdir "$ZFS_DATA_MNT/unifi/java"
	fi
}

install_unifi()
{
	tell_status "installing Unifi deps"
	stage_pkg_install snappyjava openjdk17 gmake


	tell_status "installing Unifi"
	stage_port_install net-mgmt/unifi9
}

configure_unifi()
{
	tell_status "Enable UniFi"
	stage_sysrc unifi_enable=YES

	# /usr/local/share/java/unifi/data/system.properties
	#"db.mongo.local=false"
	#"db.mongo.uri=mongodb://ubnt:password@IP_ADDRESS:PORT/unifi"
	#"statdb.mongo.uri=mongodb://ubnt:password@IP_ADDRESS:PORT/unifi_stat"
	#"unifi.db.name=unifi"
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
create_unifi_mountpoints
start_staged_jail unifi
install_unifi
configure_unifi
start_unifi
test_unifi
promote_staged_jail unifi
