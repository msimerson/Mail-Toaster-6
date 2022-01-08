#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_grafana()
{
	tell_status "installing Grafana"
	stage_pkg_install grafana8 || exit
}

configure_grafana()
{
	if [ ! -d "$STAGE_MNT/data/etc" ]; then
		mkdir "$STAGE_MNT/data/etc" || exit
	fi

	if [ ! -f "$STAGE_MNT/data/etc/grafana.conf" ]; then
		tell_status "installing default grafana.conf"
		cp "$STAGE_MNT/usr/local/etc/grafana.conf" "$STAGE_MNT/data/etc/grafana.conf" || exit
	fi

	stage_sysrc grafana_config="/data/etc/grafana.conf"

	if [ ! -d "$STAGE_MNT/data/db" ]; then
		tell_status "creating grafana data/db dir"
		mkdir "$STAGE_MNT/data/db" || exit
		chown 904:904 "$STAGE_MNT/data/db"
	fi

	tell_status "Enabling Grafana"
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
configure_grafana
start_grafana
test_grafana
promote_staged_jail grafana
