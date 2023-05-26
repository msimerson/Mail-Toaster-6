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
		allow.raw_sockets;
		mount += "devfs     $path/compat/linux/dev     devfs     rw  0 0";
		mount += "tmpfs     $path/compat/linux/dev/shm tmpfs     rw,size=1g,mode=1777  0 0";
		mount += "fdescfs   $path/compat/linux/dev/fd  fdescfs   rw,linrdlnk 0 0";
		mount += "linprocfs $path/compat/linux/proc    linprocfs rw  0 0";
		mount += "linsysfs  $path/compat/linux/sys     linsysfs  rw  0 0";
		#mount += "/tmp      $path/compat/linux/tmp     nullfs    rw  0 0";
		#mount += "/home     $path/compat/linux/home    nullfs    rw  0 0";'

install_centos()
{
	install_linux centos
}

base_snapshot_exists || exit
create_staged_fs centos
start_staged_jail centos
install_centos
promote_staged_jail centos
