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
export JAIL_CONF_EXTRA='allow.raw_sockets;
		mount += "devfs     $path/compat/linux/dev     devfs     rw  0 0";
		mount += "tmpfs     $path/compat/linux/dev/shm tmpfs     rw,size=1g,mode=1777  0 0";
		mount += "fdescfs   $path/compat/linux/dev/fd  fdescfs   rw,linrdlnk 0 0";
		mount += "linprocfs $path/compat/linux/proc    linprocfs rw  0 0";
		mount += "linsysfs  $path/compat/linux/sys     linsysfs  rw  0 0";
		#mount += "/tmp      $path/compat/linux/tmp     nullfs    rw  0 0";
		#mount += "/home     $path/compat/linux/home    nullfs    rw  0 0";'

install_ubuntu()
{
	install_linux jammy
}

configure_ubuntu()
{
	tell_status "configuring"
}

start_ubuntu()
{
	tell_status "starting CentOS"
}

test_ubuntu()
{
	tell_status "testing CentOS"
}

base_snapshot_exists || exit
create_staged_fs ubuntu
start_staged_jail ubuntu
install_ubuntu
configure_ubuntu
start_ubuntu
test_ubuntu
promote_staged_jail ubuntu
