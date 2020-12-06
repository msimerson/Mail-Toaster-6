#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_influxdb()
{
	tell_status "installing influxdb"
	stage_pkg_install influxdb || exit

	tell_status "Enable InfluxdDB"
	stage_sysrc influxd_enable=YES

	if [ ! -d "$STAGE_MNT/var/lib" ]; then
		mkdir "$STAGE_MNT/var/lib"
		chown 907:907 "$STAGE_MNT/var/lib"
	fi
}

configure_influxdb()
{
	local _conf="$STAGE_MNT/usr/local/etc/influxd.conf"

	sed -i.bak \
		-e '/dir =.*meta"/ s/\/var\/db\/influxdb/\/data\/db/' \
		-e '/dir =.*data"/ s/\/var\/db\/influxdb/\/data\/db/' \
		-e '/wal-dir =.*wal"/ s/\/var\/db\/influxdb/\/data\/db/' \
		"$_conf"

	if [ ! -d "$STAGE_MNT/data/db" ]; then
		mkdir "$STAGE_MNT/data/db" || exit
		chown 907:907 "$STAGE_MNT/data/db" || exit
	fi
}

start_influxdb()
{
	stage_exec service influxd start
}

test_influxdb()
{
	tell_status "testing influxd"
	sleep 5
	stage_test_running influxd
	sleep 5
	stage_listening 8086
}

base_snapshot_exists || exit
create_staged_fs influxdb
start_staged_jail influxdb
install_influxdb
configure_influxdb
start_influxdb
test_influxdb
promote_staged_jail influxdb
