#!/bin/sh

export TOASTER_HOSTNAME=${TOASTER_HOSTNAME:="toaster.example.com"}

# export these in your environment to customize
export BOURNE_SHELL=${BOURNE_SHELL:=bash}
export JAIL_NET_PREFIX=${JAIL_NET_PREFIX:="127.0.0"}
export JAIL_NET_INTERFACE=${JAIL_NET_INTERFACE:=lo0}
export ZFS_VOL=${ZFS_VOL:=zroot}
export ZFS_JAIL_MNT=${ZFS_JAIL_MNT:="/jails"}
export ZFS_DATA_MNT=${ZFS_DATA_MNT:="/data"}
export FBSD_MIRROR=${FBSD_MIRROR:="ftp://ftp.freebsd.org"}

# very little below here should need customizing. If so, consider opening
# an Issue or PR at https://github.com/msimerson/Mail-Toaster-6
export ZFS_JAIL_VOL="${ZFS_VOL}${ZFS_JAIL_MNT}"
export ZFS_DATA_VOL="${ZFS_VOL}${ZFS_DATA_MNT}"

export FBSD_ARCH=`uname -m`
export FBSD_REL_VER=`/bin/freebsd-version | /usr/bin/cut -f1-2 -d'-'`
export FBSD_PATCH_VER=`/bin/freebsd-version | /usr/bin/cut -f3 -d'-'`
export FBSD_PATCH_VER=${FBSD_PATCH_VER:=p0}

# the 'base' jail that other jails are cloned from. This will be named as the
# host OS version, ex: base-10.2-RELEASE and the snapshot name will be the OS
# patch level, ex: base-10.2-RELEASE@p7
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
	if [ ! -d "$STAGE_MNT" ]; then
		return
	fi

	echo "zfs destroy $STAGE_VOL"
	zfs destroy $STAGE_VOL || exit
}

stage_unmount()
{
	unmount_ports $STAGE_MNT
	unmount_data $1 $STAGE_MNT
	stage_unmount_dev
}

create_staged_fs()
{
	echo; echo "     **** stage jail cleanup ****"; echo
	stop_staged_jail $SAFE_NAME
	stage_unmount $1
	delete_staged_fs

	echo; echo "     **** stage jail filesystem setup ****"; echo
	echo "zfs clone $BASE_SNAP $STAGE_VOL"
	zfs clone $BASE_SNAP $STAGE_VOL || exit

	stage_mount_ports
	mount_data $1 $STAGE_MNT
	echo
}

start_staged_jail()
{
	if [ "$#" -eq 2 ]; then
		local _name=$1
		local _path=$2
	else
		local _name="$SAFE_NAME"
		local _path="$STAGE_MNT"
	fi

	echo; echo "     **** stage jail startup ****"; echo

	jail -c \
		name=$_name \
		host.hostname=$_name \
		path=$_path \
		interface=$JAIL_NET_INTERFACE \
		ip4.addr=$STAGE_IP \
		exec.start="/bin/sh /etc/rc" \
		exec.stop="/bin/sh /etc/rc.shutdown" \
		allow.sysvipc=1 \
		mount.devfs \
		|| exit

	pkg -j $SAFE_NAME update
}

rename_fs_staged_to_ready()
{
	local _new_vol="$ZFS_JAIL_VOL/${1}.ready"

	# clean up stages that failed promotion
	if zfs_filesystem_exists "$_new_vol"; then
		echo "zfs destroy $_new_vol (failed promotion)"
		zfs destroy $_new_vol || exit
	fi

	# get the wait over with before shutting down production jail
	echo "zfs rename $STAGE_VOL $_new_vol"
	until zfs rename $STAGE_VOL $_new_vol; do
		echo "waiting for ZFS filesystem to quiet"
		sleep 3
	done
}

rename_fs_active_to_last()
{
	local LAST="$ZFS_JAIL_VOL/$1.last"
	local ACTIVE="$ZFS_JAIL_VOL/$1"

	if zfs_filesystem_exists "$LAST"; then
		echo "zfs destroy $LAST"
		zfs destroy $LAST || exit
	fi

	if zfs_filesystem_exists "$ACTIVE"; then
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

stage_clear_caches()
{
	echo "clearing pkg cache"
	rm -rf $STAGE_MNT/var/cache/pkg/*
}

promote_staged_jail()
{
	echo; echo "   ****  promoting $1 jail ****"; echo
	stop_staged_jail
	stage_unmount $1
	stage_clear_caches

	rename_fs_staged_to_ready $1

	stop_active_jail $1
	unmount_data $1 $ZFS_JAIL_MNT/$1
	unmount_ports $ZFS_JAIL_MNT/$1

	rename_fs_active_to_last $1
	rename_fs_ready_to_active $1
	mount_data $1 $ZFS_JAIL_MNT/$1

	echo "start jail $1"
	service jail start $1 || exit
	proclaim_success $1
}

stage_pkg_install()
{
	echo "pkg -j $SAFE_NAME install -y $@"
	pkg -j $SAFE_NAME install -y $@
}

stage_sysrc()
{
	# don't use -j as this is oft called when jail is not running
	echo "sysrc -R $STAGE_MNT $@"
	sysrc -R $STAGE_MNT $@
}

stage_make_conf()
{
	if grep -qs $1 $STAGE_MNT/etc/make.conf; then
		return
	fi

	echo $2 | tee -a $STAGE_MNT/etc/make.conf || exit
}

stage_exec()
{
	echo "jexec $SAFE_NAME $@"
	jexec $SAFE_NAME $@
}

stage_mount_ports()
{
	echo "mounting /usr/ports"
	mount_nullfs /usr/ports $STAGE_MNT/usr/ports || exit
}

unmount_ports()
{
	if [ ! -d "$1/usr/ports/mail" ]; then
		return
	fi

	if ! mount -t nullfs | grep -q $1; then
		return
	fi

	echo "unmounting $1/usr/ports"
	umount $1/usr/ports || exit
}

stage_fbsd_package()
{
	echo "installing FreeBSD package $1"
	fetch -m $FBSD_MIRROR/pub/FreeBSD/releases/$FBSD_ARCH/$FBSD_REL_VER/$1.txz || exit
	tar -C $STAGE_MNT -xvpJf $1.txz || exit
}

install_redis()
{
	stage_pkg_install redis || exit
	stage_sysrc redis_enable=YES
	stage_exec service redis start

	stage_exec mkdir -p /usr/local/etc/newsyslog.conf.d
	tee -a $STAGE_MNT/usr/local/etc/newsyslog.conf.d/redis <<EO_REDIS
/var/log/redis/redis.log           644  3     100  *     JC
EO_REDIS
}

create_data_fs()
{
	if ! zfs_filesystem_exists $ZFS_DATA_VOL; then
		echo "zfs create -o mountpoint=$ZFS_DATA_MNT $ZFS_DATA_VOL"
		zfs create -o mountpoint=$ZFS_DATA_MNT $ZFS_DATA_VOL
	fi

	local _data="${ZFS_DATA_VOL}/$1"
	if zfs_filesystem_exists $_data; then
		echo "$_data already exists"
		return
	fi

	echo "zfs create -o mountpoint=${ZFS_DATA_MNT}/${1} $_data"
	zfs create -o mountpoint=${ZFS_DATA_MNT}/${1} $_data
}

mount_data()
{
	local _data_vol="$ZFS_DATA_VOL/$1"

	if ! zfs_filesystem_exists "$_data_vol"; then
		echo "no $_data_vol to mount"
		return
	fi

	local _data_mnt="$ZFS_DATA_MNT/$1"
	local _data_mp=`data_mountpoint $1 $2`

	if [ ! -d "$_data_mp" ]; then
		mkdir -p $_data_mp
	fi

	echo "nullfs mount $_data_mnt $_data_mp"
	mount_nullfs $_data_mnt $_data_mp || exit
}

unmount_data()
{
	local _data_vol="$ZFS_DATA_VOL/$1"

	if ! zfs_filesystem_exists "$_data_vol"; then
		echo "no $_data_vol fs to unmount"
		return
	fi

	local _data_mp=`data_mountpoint $1 $2`

	if [ ! -d "$_data_mp" ]; then
		return
	fi

	echo "umount data fs $_data_mp"
	umount $_data_mp
}

data_mountpoint()
{
	case $1 in
		mysql )
			echo "$2/var/db/mysql"; return ;;
		vpopmail )
			echo "$2/usr/local/vpopmail"; return ;;
	esac

	echo $2/data
}

stage_unmount_dev()
{
	if ! mount -t devfs | grep -q stage-; then
		return
	fi
	echo "unmounting $STAGE_MNT/dev"
	umount $STAGE_MNT/dev || exit
}