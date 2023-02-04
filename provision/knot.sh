#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include user

install_knot()
{
	tell_status "installing Knot DNS 3"
	stage_pkg_install knot3 rsync dialog4ports || exit

	if [ ! -d "$STAGE_MNT/data/home" ]; then
		mkdir -p "$STAGE_MNT/data/home" || exit
	fi

	install_nrpe
}

install_nrpe()
{
	if [ -z "$TOASTER_NRPE" ]; then
		echo "TOASTER_NRPE unset, skipping nrpe plugin"
		return
	fi

	tell_status "installing nrpe plugin"
	stage_pkg_install nrpe3
	stage_sysrc nrpe3_enable=YES
	stage_sysrc nrpe3_configfile="/data/etc/nrpe.cfg"
}

configure_knot()
{
	stage_sysrc sshd_enable=YES
	stage_sysrc knot_enable=YES
	stage_sysrc knot_config=/data/etc/knot.conf
	stage_exec pw user mod knot -d /data/home/knot -s /bin/sh

	preserve_passdb knot
}

start_knot()
{
	tell_status "starting knot daemon"
	stage_exec service knot start || exit
	sleep 2
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
