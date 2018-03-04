#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_telegraf()
{
	tell_status "installing telegraf"
	stage_pkg_install telegraf || exit

	tell_status "Enable telegraf"
	stage_sysrc telegraf_enable=YES
}

start_telegraf()
{
	stage_exec service telegraf start
}

test_telegraf()
{
	stage_test_running telegraf
}

base_snapshot_exists || exit
create_staged_fs telegraf
start_staged_jail telegraf
install_telegraf
start_telegraf
test_telegraf
promote_staged_jail telegraf
