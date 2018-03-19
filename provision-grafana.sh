#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_grafana()
{
	tell_status "installing Grafana"
	stage_pkg_install grafana || exit

	tell_status "Enable Grafana"
	stage_sysrc grafana_enable=YES
}

start_grafana()
{
	stage_exec service grafana start
}

test_grafana()
{
	stage_test_running grafana
}

base_snapshot_exists || exit
create_staged_fs grafana
start_staged_jail grafana
install_grafana
start_grafana
test_grafana
promote_staged_jail grafana
