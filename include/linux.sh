#!/bin/sh

# see examples in provision/centos and provision/ubuntu

configure_linuxulator()
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

configure_apt_sources()
{
	case "$1" in
		bionic|focal|jammy)
			tell_status "restoring APT sources"
			tee "$STAGE_MNT/compat/linux/etc/apt/sources.list" <<EO_UB_SOURCES
deb http://archive.ubuntu.com/ubuntu $1 main universe restricted multiverse
deb http://security.ubuntu.com/ubuntu/ $1-security universe multiverse restricted main
deb http://archive.ubuntu.com/ubuntu $1-backports universe multiverse restricted main
deb http://archive.ubuntu.com/ubuntu $1-updates universe multiverse restricted main
EO_UB_SOURCES
			;;
		bullseye)
			tell_status "adding APT sources"
			tee "$STAGE_MNT/compat/linux/etc/apt/sources.list" <<EO_DEB_SOURCES
deb http://deb.debian.org/debian $1 main contrib non-free
deb http://deb.debian.org/debian-security/ $1-security main contrib non-free
deb http://deb.debian.org/debian $1-updates main contrib non-free
deb http://deb.debian.org/debian $1-backports main contrib non-free
EO_DEB_SOURCES
	esac
}

install_apt_updates()
{
	tell_status "updating apt"
	stage_exec chroot /compat/linux apt update || exit 1

	tell_status "updating installed apt packages"
	stage_exec chroot /compat/linux apt upgrade -y || exit 1
}

install_linux()
{
	# tested with values of $1:
	#   Ubuntu: bionic (18), focal (20) and jammy (22)
	#   Debian: bullseye (11)
	#   CentOS: centos (7)

	configure_linuxulator

	case "$1" in
		centos)
			tell_status "installing $1"
			stage_pkg_install linux_base-c7 || exit 1
		;;
		bionic|bullseye|focal|jammy)
			tell_status "installing (debian|ubuntu) $1"
			stage_pkg_install debootstrap || exit 1
			stage_exec debootstrap $1 /compat/linux
			configure_apt_sources $1
		;;
	esac

	case "$1" in
		bionic) stage_exec chroot /compat/linux apt remove -y rsyslog ;;
		jammy)  stage_exec mount -t devfs devfs /compat/linux/dev ;;
	esac

	case "$1" in
		bionic|focal|jammy|bullseye) install_apt_updates ;;
	esac

	case "$1" in
		jammy) stage_exec umount /compat/linux/dev ;;
	esac
}

