#!/bin/sh

# export these in your environment to override
export BOURNE_SHELL=${BOURNE_SHELL:=bash}
export JAIL_NET_PREFIX=${JAIL_NET_PREFIX:="127.0.0"}
export JAIL_NET_INTERFACE=${JAIL_NET_INTERFACE:=lo0}
export ZFS_VOL=${ZFS_VOL:=zroot}

export ZFS_JAIL_VOL="$ZFS_VOL/jails"
export ZFS_JAIL_MNT=${ZFS_JAIL_MNT:="/jails"}

export FBSD_MIRROR=${FBSD_MIRROR:="ftp://ftp.freebsd.org"}
export FBSD_ARCH=`uname -m`
export FBSD_REL_VER=`/bin/freebsd-version | /usr/bin/cut -f1-2 -d'-'`
export FBSD_PATCH_VER=`/bin/freebsd-version | /usr/bin/cut -f3 -d'-'`
export FBSD_PATCH_VER=${FBSD_PATCH_VER:=p0}


# the 'base' jail that other jails are cloned from
export BASE_NAME="base-$FBSD_REL_VER"
export BASE_VOL="$ZFS_JAIL_VOL/$BASE_NAME"
export BASE_SNAP="${BASE_VOL}@${FBSD_PATCH_VER}"
export BASE_MNT="$ZFS_JAIL_MNT/$BASE_NAME"
export BASE_ETC="$BASE_MNT/etc"
export BASE_IP="${JAIL_NET_PREFIX}.2"

export STAGE_IP="${JAIL_NET_PREFIX}.254"
export STAGE_NAME="stage-$FBSD_REL_VER"
export STAGE_VOL="$ZFS_JAIL_VOL/$STAGE_NAME"
export STAGE_MNT="$ZFS_JAIL_MNT/$STAGE_NAME"

safe_jailname()
{
	# constrain jail name chars to alpha-numeric and _
	echo `echo "$1" | sed -e 's/[^a-zA-Z0-9]/_/g'`
}

export SAFE_NAME=`safe_jailname $STAGE_NAME`

if [ -z "$SAFE_NAME" ]; then
	echo "unset SAFE_NAME"
	exit
fi

echo "safe name: $SAFE_NAME"

zfs_filesystem_exists()
{
	if zfs list -t filesystem $1 2>/dev/null | grep -q ^$1; then
		echo $1 filesystem exists
		return 0
	else
		return 1
	fi
}

zfs_snapshot_exists()
{
	if zfs list -t snapshot $1 2>/dev/null | grep -q $1; then
		echo $1 snapshot exists
		return 0
	else
		return 1
	fi
}

base_snapshot_exists()
{
	zfs_snapshot_exists $BASE_SNAP
}

stop_jail()
{
	service jail stop $1
	jail -r $1 2>/dev/null
}

stop_active_jail()
{
	echo "stopping jail $1"
	stop_jail $1
}

stop_staged_jail()
{
	TO_STOP="$1"
	if [ -z "$TO_STOP" ]; then
		TO_STOP="$SAFE_NAME"
	fi

	echo "stopping staged jail $1"
	stop_jail $TO_STOP
}

delete_staged_fs()
{
	stop_staged_jail $SAFE_NAME

	if [ -d "$STAGE_MNT" ]; then
		echo "zfs destroy $STAGE_VOL"
		zfs destroy $STAGE_VOL || exit
	else
		#echo "$STAGE_MNT does not exist"
	fi
}

create_staged_fs()
{
	delete_staged_fs

	echo "zfs clone $BASE_SNAP $STAGE_VOL"
	zfs clone $BASE_SNAP $STAGE_VOL || exit
}

start_staged_jail()
{
	if [$# -eq 2]; then
		local _name=$1
		local _path=$2
	else
		local _name="$SAFE_NAME"
		local _path="$STAGE_MNT"
	fi

	jail -c \
		name=$_name \
		host.hostname=$_name \
		path=$_path \
		interface=$JAIL_NET_INTERFACE \
		ip4.addr=$STAGE_IP \
		exec.start="/bin/sh /etc/rc" \
		exec.stop="/bin/sh /etc/rc.shutdown" \
		persist || exit
}

rename_fs_staged_to_ready()
{
	local _new_vol="$ZFS_JAIL_VOL/${1}.ready"

	# clean up stages that failed promotion
	if [ -d "$ZFS_JAIL_MNT/${1}.ready" ]; then
		echo "zfs destroy $_new_vol (failed promotion)"
		zfs destroy $_new_vol || exit
	else
		#echo "$_new_vol does not exist"
	fi

	# get the wait over with before shutting down production jail
	echo "zfs rename $STAGE_VOL $_new_vol"
	zfs rename $STAGE_VOL $_new_vol || ( \
			echo "waiting 60 seconds for ZFS filesystem to settle" \
			&& sleep 60 \
			&& zfs rename $STAGE_VOL $_new_vol \
		) || exit
}

rename_fs_active_to_last()
{
	local LAST="$ZFS_JAIL_VOL/$1.last"
	local ACTIVE="$ZFS_JAIL_VOL/$1"

	if [ -d "$ZFS_JAIL_MNT/$1.last" ]; then
		echo "zfs destroy $LAST"
		zfs destroy $LAST || exit
	fi

	if [ -d "$ZFS_JAIL_MNT/$1" ]; then
		echo "zfs rename $ACTIVE $LAST"
		zfs rename $ACTIVE $LAST || exit
	fi
}

rename_fs_ready_to_active()
{
	echo "zfs rename $$ZFS_JAIL_VOL/${1}.ready $ZFS_JAIL_VOL/$1"
	zfs rename $ZFS_JAIL_VOL/${1}.ready $ZFS_JAIL_VOL/$1 || exit
}

proclaim_success()
{
	echo
	echo "Success! A new '$1' jail is provisioned"
	echo
}

promote_staged_jail()
{
	stop_staged_jail

	rename_fs_staged_to_ready $1
	stop_active_jail $1
	rename_fs_active_to_last $1
	rename_fs_ready_to_active $1

	echo "start jail $1"
	service jail start $1 || exit
	proclaim_success $1
}

stage_pkg_install()
{
	jexec $SAFE_NAME pkg install -y $@
}

stage_rc_conf()
{
	sysrc -f $STAGE_MNT/etc/rc.conf $@
}