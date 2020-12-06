#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_rsnapshot()
{
	tell_status "installing rsnapshot"
	stage_pkg_install rsnapshot coreutils || exit
}

configure_rsnapshot()
{
	local _pdir="$STAGE_MNT/usr/local/etc/periodic"

	for p in daily weekly monthly
	do
		if [ ! -d "$_pdir/$p" ]; then
			tell_status "creating $_pdir/$p"
			mkdir -p "$_pdir/$p" || exit
		fi

		if [ ! -f "$_pdir/$p/rsnapshot" ]; then
			tell_status "installing $p periodic task"
			tee "$_pdir/$p/rsnapshot" <<EO_RSNAP
/usr/local/bin/rsnapshot -c /data/etc/rsnapshot.conf $p
EO_RSNAP
            chmod 755 "$_pdir/$p/rsnapshot"
		fi
	done

	for d in etc snaps
	do
		if [ ! -d "$ZFS_DATA_MNT/rsnapshot/$d" ]; then
			mkdir "$ZFS_DATA_MNT/rsnapshot/$d"
		fi
	done

	if [ ! -f "$ZFS_DATA_MNT/rsnapshot/etc/rsnapshot.conf" ]; then
		tell-status "installing default $ZFS_DATA_MNT/etc/rsnapshot.conf"
		cp "$STAGE_MNT/usr/local/etc/rsnapshot.conf.default" "$ZFS_DATA_MNT/rsnapshot/etc/rsnapshot.conf"
	fi

	if [ -d "$ZFS_DATA_MNT/rsnapshot/ssh" ]; then
		if [ ! -d "$STAGE_MNT/root/.ssh" ]; then
			umask 0077; mkdir "$STAGE_MNT/root/.ssh"; umask 0022;
		fi
		cp "$ZFS_DATA_MNT/rsnapshot/ssh/*" "$STAGE_MNT/root/.ssh"
	fi
}

start_rsnapshot()
{
	echo "rsnapshot is triggered by periodic, which is run by cron"
}

test_rsnapshot()
{
	echo "hrmm, how to test?"
}

base_snapshot_exists || exit
create_staged_fs rsnapshot
start_staged_jail rsnapshot
install_rsnapshot
configure_rsnapshot
start_rsnapshot
test_rsnapshot
promote_staged_jail rsnapshot
