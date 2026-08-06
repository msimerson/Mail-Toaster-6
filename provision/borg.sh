#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

install_borg()
{
	tell_status "installing borg"
	stage_pkg_install py311-borgbackup || exit
}

configure_borg()
{
	local _pdir="$STAGE_MNT/usr/local/etc/periodic"

	for p in daily weekly monthly
	do
		if [ ! -f "$_pdir/$p/borg" ]; then
			store_exec "$_pdir/$p/borg" <<EO_RSNAP
/usr/local/bin/borg -c /data/etc/borg.conf $p
EO_RSNAP
		fi
	done

	for d in etc snaps
	do
		if [ ! -d "$(get_jail_data borg)/$d" ]; then
			mkdir "$(get_jail_data borg)/$d"
		fi
	done

	if [ ! -f "$(get_jail_data borg)/etc/borg.conf" ]; then
		tell_status "installing default $(get_jail_data borg)/etc/borg.conf"
		cp "$STAGE_MNT/usr/local/etc/borg.conf.default" "$(get_jail_data borg)/etc/borg.conf"
	fi

	if [ -d "$(get_jail_data borg)/ssh" ]; then
		if [ ! -d "$STAGE_MNT/root/.ssh" ]; then
			umask 0077; mkdir "$STAGE_MNT/root/.ssh"; umask 0022;
		fi
		cp "$(get_jail_data borg)/ssh/*" "$STAGE_MNT/root/.ssh"
	fi
}

start_borg()
{
	echo "borg is triggered by periodic, which is run by cron"
}

test_borg()
{
	echo "hrmm, how to test?"
}

base_snapshot_exists || exit
create_staged_fs borg
start_staged_jail borg
install_borg
configure_borg
start_borg
test_borg
promote_staged_jail borg
