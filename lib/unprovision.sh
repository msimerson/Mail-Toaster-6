#!/bin/sh

unprovision_last()
{
	for _j in $JAIL_ORDERED_LIST; do
		if zfs_filesystem_exists "$ZFS_JAIL_VOL/$_j.last"; then
			tell_status "destroying $ZFS_JAIL_VOL/$_j.last"
			zfs destroy "$ZFS_JAIL_VOL/$_j.last"
		fi
	done
}

unprovision_filesystem()
{
	if zfs_filesystem_exists "$ZFS_JAIL_VOL/$1.ready"; then
		tell_status "destroying $ZFS_JAIL_VOL/$1.ready"
		zfs destroy "$ZFS_JAIL_VOL/$1.ready" || return 1
	fi

	if zfs_filesystem_exists "$ZFS_JAIL_VOL/$1.last"; then
		tell_status "destroying $ZFS_JAIL_VOL/$1.last"
		zfs destroy "$ZFS_JAIL_VOL/$1.last"  || return 1
	fi

	if [ -e "$ZFS_JAIL_VOL/$1/dev/null" ]; then
		umount -t devfs "$ZFS_JAIL_VOL/$1/dev"  || return 1
	fi

	if zfs_filesystem_exists "$ZFS_DATA_VOL/$1"; then
		tell_status "destroying $ZFS_DATA_MNT/$1"
		unmount_data "$1" || return 1
		zfs destroy "$ZFS_DATA_VOL/$1" || return 1
	fi

	if zfs_filesystem_exists "$ZFS_JAIL_VOL/$1"; then
		tell_status "destroying $ZFS_JAIL_VOL/$1"
		zfs destroy "$ZFS_JAIL_VOL/$1" || return 1
	fi
}

unprovision_filesystems()
{
	for _j in $JAIL_ORDERED_LIST; do
		unprovision_filesystem "$_j" || return 1
	done

	if zfs_filesystem_exists "$ZFS_JAIL_VOL"; then
		tell_status "destroying $ZFS_JAIL_VOL"
		zfs destroy "$ZFS_JAIL_VOL" || return 1
	fi

	if zfs_filesystem_exists "$ZFS_DATA_VOL"; then
		tell_status "destroying $ZFS_DATA_VOL"
		zfs destroy "$ZFS_DATA_VOL" || return 1
	fi

	if zfs_filesystem_exists "$BASE_VOL"; then
		tell_status "destroying $BASE_VOL"
		zfs destroy -r "$BASE_VOL" || return 1
	fi
}

unprovision_files()
{
	for _f in /etc/jail.conf /etc/pf.conf /usr/local/sbin/jailmanage; do
		if [ -f "$_f" ]; then
			tell_status "rm $_f"
			rm "$_f"
		fi
	done

	if grep -q "^$JAIL_NET_PREFIX" /etc/hosts; then
		sed -i.bak -e "/^$JAIL_NET_PREFIX.*/d" /etc/hosts
	fi
}

unprovision_rc()
{
	tell_status "disabling jail $1 startup"
	sysrc jail_list-=" $1"
	sysrc -f /etc/periodic.conf security_status_pkgaudit_jails-=" $1"

	if [ -f /etc/jail.conf.d/$1.conf ]; then
		tell_status "deleting /etc/jail.conf.d/$1.conf"
		rm "/etc/jail.conf.d/$1.conf"
	fi
}

unprovision()
{
	if [ -n "$1" ]; then

		if [ "$1" = "last" ]; then
			unprovision_last
			return
		fi

		service jail stop stage "$1"
		unprovision_filesystem "$1" || return 1
		unprovision_rc "$1"
		return
	fi

	service jail stop
	sleep 1

	ipcrm -W
	unprovision_filesystems
	unprovision_files
	for _j in $JAIL_ORDERED_LIST; do unprovision_rc "$_j"; done
	echo "done"
}
