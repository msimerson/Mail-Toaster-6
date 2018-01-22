#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_knot()
{
	tell_status "installing Knot DNS 2"
	stage_pkg_install knot2 rsync dialog4ports || exit

	if [ ! -d "$STAGE_MNT/data/home" ]; then
		mkdir -p "$STAGE_MNT/data/home" || exit
	fi
}

configure_knot()
{
	stage_sysrc sshd_enable=YES
	stage_sysrc knot_enable=YES
	stage_sysrc knot_config=/data/etc/knot.conf

	for _f in master.password group;
	do
		if [ -f "$ZFS_JAIL_MNT/knot/etc/$_f" ]; then
			cp "$ZFS_JAIL_MNT/knot/etc/$_f" "$STAGE_MNT/etc/"
			stage_exec pwd_mkdb -p /etc/master.passwd
		fi
	done
}

start_knot()
{
	tell_status "starting knot daemon"
	stage_exec service knot start || exit
}

test_knot()
{
	tell_status "testing knot"
	stage_test_running knot

	stage_listening 53
	echo "it worked."

	tell_status "testing UDP DNS query"
	drill    www.example.com @"$(get_jail_ip stage)" || exit

	tell_status "testing TCP DNS query"
	drill -t www.example.com @"$(get_jail_ip stage)" || exit
}

base_snapshot_exists || exit
create_staged_fs knot
start_staged_jail knot
install_knot
configure_knot
start_knot
test_knot
promote_staged_jail knot
