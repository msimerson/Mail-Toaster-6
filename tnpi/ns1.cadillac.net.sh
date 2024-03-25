#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include user

install_knot()
{
	tell_status "installing Knot DNS 3"
	stage_pkg_install knot3 rsync || exit

	if [ ! -d "$STAGE_MNT/data/home" ]; then
		mkdir -p "$STAGE_MNT/data/home" || exit
	fi

	install_nrpe
	install_sentry
}


install_nrpe()
{
	if [ -z "$TOASTER_NRPE" ]; then
		echo "TOASTER_NRPE unset, skipping nrpe plugin"
		return
	fi

	tell_status "installing nrpe plugin"
	stage_pkg_install nrpe
	stage_sysrc nrpe_enable=YES
	stage_sysrc nrpe_configfile="/data/etc/nrpe.cfg"
}

configure_knot()
{
	stage_sysrc sshd_enable=YES
	stage_sysrc knot_enable=YES
	stage_sysrc knot_config=/data/etc/knot.conf

	preserve_passdb ns1.cadillac.net
	stage_exec pw user mod knot -d /data/home/knot -s /bin/sh
	stage_exec pw user mod root -d /data/home/root -s /usr/local/bin/bash
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

	stage_listening 53 8
	echo "it worked."

	tell_status "testing UDP DNS query"
	drill    ns1.cadillac.net @"$(get_jail_ip stage)" || exit

	tell_status "testing TCP DNS query"
	drill -t ns1.cadillac.net @"$(get_jail_ip stage)" || exit
}

base_snapshot_exists || exit
create_staged_fs ns1.cadillac.net
start_staged_jail ns1.cadillac.net
install_knot
configure_knot
start_knot
test_knot
promote_staged_jail ns1.cadillac.net
