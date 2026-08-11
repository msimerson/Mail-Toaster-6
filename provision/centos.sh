#!/bin/sh

set -e -u

. mail-toaster.sh

mt6-include linux

export JAIL_DEVFS_RULESET="$JAIL_DEVFS_RULESET_LINUX"
export JAIL_START_EXTRA="allow.mount
		allow.mount.devfs
		allow.mount.fdescfs
		allow.mount.procfs
		allow.mount.linprocfs
		allow.mount.linsysfs
		allow.mount.tmpfs
		enforce_statfs=1
"
export JAIL_CONF_EXTRA='
		allow.raw_sockets;'
export JAIL_FSTAB="
#/tmp      $ZFS_JAIL_MNT/centos/compat/linux/tmp     nullfs    rw  0 0
#/home     $ZFS_JAIL_MNT/centos/compat/linux/home    nullfs    rw  0 0"

install_centos()
{
	install_linux centos
}

base_snapshot_exists || exit 1
create_staged_fs centos
for _fs in dev proc sys tmp home; do
	mkdir -p "$STAGE_MNT/compat/linux/$_fs"
done
chmod 777 "$STAGE_MNT/compat/linux/tmp"
assure_devfs_linux_ruleset
start_staged_jail centos
install_centos
promote_staged_jail centos
