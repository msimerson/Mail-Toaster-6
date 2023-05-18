#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_prometheus()
{
	tell_status "installing prometheus"
	stage_pkg_install prometheus alertmanager
}

configure_prometheus()
{
	for _d in etc db; do
		if [ ! -d "$STAGE_MNT/data/$_d" ]; then
			mkdir "$STAGE_MNT/data/$_d" || exit
		fi
	done

	if [ ! -f "$STAGE_MNT/data/etc/prometheus.yml" ]; then
		cp "$STAGE_MNT/usr/local/etc/prometheus.yml" "$STAGE_MNT/data/etc/prometheus.yml" || exit
	fi

	if [ ! -f "$STAGE_MNT/data/etc/alertmanager.yml" ]; then
		cp "$STAGE_MNT/usr/local/etc/alertmanager/alertmanager.yml" "$STAGE_MNT/data/etc/alertmanager.yml" || exit
	fi

	stage_sysrc prometheus_enable=YES
	stage_sysrc prometheus_config=/data/etc/prometheus.yml
	stage_sysrc prometheus_syslog_output_enable=YES

	stage_sysrc alertmanager_enable=YES
	stage_sysrc alertmanager_config=/data/etc/alertmanager.yml
	stage_sysrc alertmanager_data_dir=/data/db
}

start_prometheus()
{
	tell_status "starting prometheus"
	stage_exec service prometheus start
	stage_exec service alertmanager start
}

test_prometheus()
{
	tell_status "testing prometheus tcp listener"
	stage_listening 9090
	stage_listening 9094
}

base_snapshot_exists || exit
create_staged_fs prometheus
start_staged_jail
install_prometheus
configure_prometheus
start_prometheus
test_prometheus
promote_staged_jail prometheus
