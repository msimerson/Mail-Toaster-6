#!/bin/sh

. mail-toaster.sh || exit

# tested with bionic (18), focal (20) and jammy (22)
DEBIAN_RELEASE="jammy"

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
		allow.reserved_ports;
		mount += "devfs     $path/compat/linux/dev     devfs     rw  0 0";
		mount += "tmpfs     $path/compat/linux/dev/shm tmpfs     rw,size=1g,mode=1777  0 0";
		mount += "fdescfs   $path/compat/linux/dev/fd  fdescfs   rw,linrdlnk 0 0";
		mount += "linprocfs $path/compat/linux/proc    linprocfs rw  0 0";
		mount += "linsysfs  $path/compat/linux/sys     linsysfs  rw  0 0";
		mount += "/tmp      $path/compat/linux/tmp     nullfs    rw  0 0";
		#mount += "/home     $path/compat/linux/home    nullfs    rw  0 0";'

enable_linuxulator()
{
	tell_status "enabling Linux emulation on Host (loads kernel modules)"
	sysrc linux_enable=YES
	sysrc linux_mounts_enable=NO
	service linux start

	tell_status "enabling Linux emulation in jail"
	stage_sysrc linux_enable=YES
	stage_sysrc linux_mounts_enable=NO
	stage_exec service linux start

}

install_ubuntu()
{
	enable_linuxulator

	tell_status "installing $DEBIAN_RELEASE"
	stage_pkg_install debootstrap || exit 1
	stage_exec debootstrap $DEBIAN_RELEASE /compat/linux
}

configure_ubuntu()
{
	case "$DEBIAN_RELEASE" in
		bionic)
		focal)
		jammy)
			if [ -f "$STAGE_MNT/compat/linux/etc/apt/sources.list" ]; then
				tell_status "restoring APT sources"
				tee "$STAGE_MNT/compat/linux/etc/apt/sources.list" <<EO_SOURCES
deb http://archive.ubuntu.com/ubuntu $DEBIAN_RELEASE main universe restricted multiverse
deb http://security.ubuntu.com/ubuntu/ $DEBIAN_RELEASE-security universe multiverse restricted main
deb http://archive.ubuntu.com/ubuntu $DEBIAN_RELEASE-backports universe multiverse restricted main
deb http://archive.ubuntu.com/ubuntu $DEBIAN_RELEASE-updates universe multiverse restricted main
EO_SOURCES
			fi
			;;
	esac
}

start_ubuntu()
{
	case "$DEBIAN_RELEASE" in
		bionic)
			stage_exec chroot /compat/linux apt remove -y rsyslog
			;;
		jammy)
			stage_exec mount -t devfs devfs /compat/linux/dev
			;;
	esac

	tell_status "updating apt"
	stage_exec chroot /compat/linux apt update || exit 1

	tell_status "updating installed apt packages"
	stage_exec chroot /compat/linux apt upgrade -y || exit 1

	case "$DEBIAN_RELEASE" in
		jammy)
			stage_exec umount /compat/linux/dev
			;;
	esac
}

test_ubuntu()
{
	echo "looks good to me!"
}

base_snapshot_exists || exit
create_staged_fs ubuntu
start_staged_jail ubuntu
install_ubuntu
configure_ubuntu
start_ubuntu
test_ubuntu
promote_staged_jail ubuntu
