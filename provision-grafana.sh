#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_grafana()
{
	tell_status "installing Grafana"
	stage_pkg_install influxdb telegraf statsd grafana3 || exit

	tell_status "Enable Influxd 3, Grafana 3, telegraf, and statsd"
	stage_sysrc influxd_enable=YES
	stage_sysrc grafana3_enable=YES
	stage_sysrc statsd_enable=YES
	stage_sysrc telegraf_enable=YES

	mkdir "$STAGE_MNT/var/lib"
	chown 907:907 "$STAGE_MNT/var/lib"

	sed -i '' \
		-e "s/ process\./ require('events')\./" \
		"$STAGE_MNT/usr/local/share/statsd/lib/config.js"
}

start_grafana()
{
	stage_exec service influxd start
	stage_exec service telegraf start
	stage_exec service grafana3 start
	stage_exec service statsd start
}

test_grafana()
{
	stage_test_running grafana
	sleep 1
	stage_test_running telegraf
	sleep 1
	stage_test_running influxd
	sleep 1
	stage_listening 8125
	# stage_test_running statsd
}

base_snapshot_exists || exit
create_staged_fs grafana
start_staged_jail grafana
install_grafana
start_grafana
test_grafana
promote_staged_jail grafana
