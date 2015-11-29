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

stop_staged_jail()
{
    TO_STOP="$1"
    if [ -z "$TO_STOP" ]; then
        TO_STOP="$SAFE_NAME"
    fi

    echo "stopping staged jail $TO_STOP"
    service jail stop $TO_STOP
    jail -r $TO_STOP 2>/dev/null
}

delete_staged_fs()
{
    stop_staged_jail $SAFE_NAME

    if [ -d "$STAGE_MNT" ]; then
        echo "zfs destroy $STAGE_VOL"
        zfs destroy $STAGE_VOL || exit
    else
        echo "$STAGE_MNT does not exist"
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
    jail -c \
        name=$1 \
        host.hostname=$1 \
        path=$2 \
        interface=$JAIL_NET_INTERFACE \
        ip4.addr=$STAGE_IP \
        exec.start="/bin/sh /etc/rc" \
        exec.stop="/bin/sh /etc/rc.shutdown" \
        persist || exit
}

proclaim_success()
{
    echo
    echo "Success! A new '$1' jail is provisioned"
    echo
}