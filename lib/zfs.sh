#!/bin/sh

zfs_filesystem_exists()
{
	zfs list -t filesystem "$1" 2>/dev/null | grep -q "^$1" || return 1
	tell_status "$1 filesystem exists"
	return 0
}

zfs_snapshot_exists()
{
	if zfs list -t snapshot "$1" 2>/dev/null | grep -q "$1"; then
		echo "$1 snapshot exists"
		return
	fi
	false
}

zfs_mountpoint_exists()
{
	zfs list -t filesystem "$1" 2>/dev/null | grep -q "$1\$" || return 1
	echo "$1 mountpoint exists"
	return 0
}

zfs_create_fs()
{
	if zfs_filesystem_exists "$1"; then return; fi
	if zfs_mountpoint_exists "$2"; then return; fi

	if echo "$1" | grep "$ZFS_DATA_VOL"; then
		if ! zfs_filesystem_exists "$ZFS_DATA_VOL"; then
			tell_status "zfs create -o mountpoint=$ZFS_DATA_MNT $ZFS_DATA_VOL"
			zfs create -o mountpoint="$ZFS_DATA_MNT" "$ZFS_DATA_VOL"  || exit
		fi
	fi

	if echo "$1" | grep "$ZFS_JAIL_VOL"; then
		if ! zfs_filesystem_exists "$ZFS_JAIL_VOL"; then
			tell_status "zfs create -o mountpoint=$ZFS_JAIL_MNT $ZFS_JAIL_VOL"
			zfs create -o mountpoint="$ZFS_JAIL_MNT" "$ZFS_JAIL_VOL"  || exit
		fi
	fi

	if [ -z "$2" ]; then
		tell_status "zfs create $1"
		zfs create "$1" || exit
		echo "done"
		return
	fi

	tell_status "zfs create -o mountpoint=$2 $1"
	zfs create -o mountpoint="$2" "$1"  || exit
	echo "done"
}

zfs_destroy_fs()
{
	local _fs="$1"
	local _flags=${2-}

	if ! zfs_filesystem_exists "$_fs"; then return; fi

	if [ -n "$_flags" ]; then
		echo "zfs destroy $2 $1"
		zfs destroy "$2" "$1" || exit 1
	else
		echo "zfs destroy $1"
		zfs destroy "$1" || exit 1
	fi
}
