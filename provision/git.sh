#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

preflight_check() {
	echo ""
}

install_git()
{
	for _d in etc home; do
		_path="$STAGE_MNT/data/$_d"
		[ -d "$_path" ] || mkdir "$_path"
	done

	tell_status "install git"
	stage_pkg_install git
}

configure_git()
{
	stage_sysrc sshd_enable=YES
}

start_git()
{
	stage_exec service sshd start
}

test_git()
{
	echo "testing git..."
	stage_exec ls /data/home/
	echo "it worked"
}

preflight_check
base_snapshot_exists || exit 1
create_staged_fs git
start_staged_jail git
install_git
configure_git
start_git
test_git
promote_staged_jail git
