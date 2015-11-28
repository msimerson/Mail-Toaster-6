#!/bin/sh

export ZFS_JAIL_VOL="${ZFS_JAIL_VOL:=zroot/jails}"
export ZFS_JAIL_MNT="${ZFS_JAIL_MNT:=/jails}"

export FBSD_MIRROR="ftp://ftp.freebsd.org"
export FBSD_REL_VER=`/bin/freebsd-version | /usr/bin/cut -f1-2 -d'-'`
export FBSD_PATCH_VER=`/bin/freebsd-version | /usr/bin/cut -f3 -d'-'`
if [ -z $FBSD_PATCH_VER ]; then
    export FBSD_PATCH_VER="p0"
fi
export FBSD_ARCH=`uname -m`

# the 'base' jail that other jails are cloned from
export BASE_NAME="base-$FBSD_REL_VER"
export BASE_VOL="$ZFS_JAIL_VOL/$BASE_NAME"
export BASE_SNAP="${BASE_VOL}@${FBSD_PATCH_VER}"
export BASE_MNT="$ZFS_JAIL_MNT/$BASE_NAME"
export BASE_ETC="$BASE_MNT/etc"
export BASE_IP="127.0.0.2"

export STAGE_IP="127.0.0.100"
export STAGE_NAME="stage-$FBSD_REL_VER"
export STAGE_VOL="$ZFS_JAIL_VOL/$STAGE_NAME"
export STAGE_MNT="$ZFS_JAIL_MNT/$STAGE_NAME"

safe_jailname()
{
    # constrain jail name chars to alpha-numeric and _
    echo `echo "$1" | sed -e 's/[^a-zA-Z0-9]/_/g'`
}   

base_snapshot_exists()
{
    if zfs list -t snapshot $BASE_SNAP | grep -q $BASE_SNAP; then
        echo $BASE_SNAP snapshot exists
        return 0
    else
        return 1
    fi
}

create_staged_fs()
{
    echo "zfs clone $BASE_SNAP $STAGE_VOL"
    zfs clone $BASE_SNAP $STAGE_VOL || exit
}

delete_staged_fs()
{
    if [ -d "$STAGE_MNT" ]; then
        echo "deleting $STAGE_MNT"
        zfs destroy $STAGE_VOL || exit
    fi
}

start_staged_jail()
{
    jail -c \
        path=$STAGE_MNT \
        mount.devfs \
        name=$1 \
        host.hostname=$1 \
        interface=lo0 \
        ip4.addr=$STAGE_IP \
        exec.start="/bin/sh /etc/rc" \
        exec.stop="/bin/sh /etc/rc.shutdown" \
        persist || exit
}
