#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

install_rsnapshot()
{
	tell_status "installing rsnapshot"
	stage_pkg_install rsnapshot coreutils
}

configure_rsnapshot()
{
	local _pdir="$STAGE_MNT/usr/local/etc/periodic"

	for _p in daily weekly monthly
	do
		if [ ! -f "$_pdir/$_p/rsnapshot" ]; then
			store_exec "$_pdir/$_p/rsnapshot" <<EO_RSNAP
/usr/local/bin/rsnapshot -c /data/etc/rsnapshot.conf $_p
EO_RSNAP
		fi
	done

	for d in etc snaps
	do
		if [ ! -d "$(get_jail_data rsnapshot)/$d" ]; then
			mkdir "$(get_jail_data rsnapshot)/$d"
		fi
	done

	if [ ! -f "$(get_jail_etc rsnapshot)/rsnapshot.conf" ]; then
		tell_status "installing default $(get_jail_etc rsnapshot)/rsnapshot.conf"
		cp "$STAGE_MNT/usr/local/etc/rsnapshot.conf.default" "$(get_jail_etc rsnapshot)/rsnapshot.conf"
	fi

	if [ -d "$(get_jail_data rsnapshot)/ssh" ]; then
		if [ ! -d "$STAGE_MNT/root/.ssh" ]; then
			umask 0077; mkdir "$STAGE_MNT/root/.ssh"; umask 0022;
		fi
		cp "$(get_jail_data rsnapshot)/ssh/"* "$STAGE_MNT/root/.ssh/"
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
