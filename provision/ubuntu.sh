#!/bin/sh

. mail-toaster.sh || exit

mt6-include linux

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
devfs     $ZFS_JAIL_MNT/ubuntu/compat/linux/dev     devfs     rw  0 0
tmpfs     $ZFS_JAIL_MNT/ubuntu/compat/linux/dev/shm tmpfs     rw,size=1g,mode=1777  0 0
fdescfs   $ZFS_JAIL_MNT/ubuntu/compat/linux/dev/fd  fdescfs   rw,linrdlnk 0 0
linprocfs $ZFS_JAIL_MNT/ubuntu/compat/linux/proc    linprocfs rw  0 0
linsysfs  $ZFS_JAIL_MNT/ubuntu/compat/linux/sys     linsysfs  rw  0 0
#/tmp      $ZFS_JAIL_MNT/ubuntu/compat/linux/tmp     nullfs    rw  0 0
#/home     $ZFS_JAIL_MNT/ubuntu/compat/linux/home    nullfs    rw  0 0"

install_ubuntu()
{
	install_linux jammy
}

base_snapshot_exists || exit
create_staged_fs ubuntu
start_staged_jail ubuntu
install_ubuntu
promote_staged_jail ubuntu
