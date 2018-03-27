#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_influxdb()
{
	tell_status "installing influxdb"
	stage_pkg_install influxdb || exit

	tell_status "Enable InfluxdDB"
	stage_sysrc influxd_enable=YES

	mkdir "$STAGE_MNT/var/lib"
	chown 907:907 "$STAGE_MNT/var/lib"

}

configure_influxdb()
{
	local _conf="$STAGE_MNT/usr/local/etc/influxd.conf"

	sed -i.bak \
		-e '/dir =.*meta"/ s/\/var\/db\/influxdb/\/data\/db/' \
		-e '/dir =.*data"/ s/\/var\/db\/influxdb/\/data\/db/' \
		-e '/wal-dir =.*wal"/ s/\/var\/db\/influxdb/\/data\/db/' \
		"$_conf"

	mkdir "$STAGE_MNT/data/db" || exit
	chown 907:907 "$STAGE_MNT/data/db" || exit
}

start_influxdb()
{
	stage_exec service influxd start
}

test_influxdb()
{
	stage_test_running influxd
	sleep 1
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
