#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
# shellcheck disable=2016
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/prometheus \$path/data nullfs rw 0 0\";"

PROM_VERSION=1.4.1

install_prometheus()
{
	tell_status "installing prometheus"
	local _archive="prometheus-$PROM_VERSION.freebsd-amd64.tar.gz"
	if [ ! -f "$_archive" ]; then
		fetch https://github.com/prometheus/prometheus/releases/download/v$PROM_VERSION/$_archive || exit
		fetch https://github.com/prometheus/alertmanager/releases/download/v0.5.1/alertmanager-0.5.1.freebsd-amd64.tar.gz || exit
	fi

	tar -C $ZFS_DATA_MNT/prometheus/ -xzf $_archive || exit
	tar -C $ZFS_DATA_MNT/prometheus/ -xzf  alertmanager-0.5.1.freebsd-amd64.tar.gz || exit
}

configure_prometheus()
{
	echo "no config yet"
}

start_prometheus()
{
	tell_status "starting prometheus"
	stage_exec /data/prometheus-$PROM_VERSION.freebsd-amd64/prometheus &
}

test_prometheus()
{
	tell_status "testing prometheus tcp listener"
	stage_listening 9090
}

base_snapshot_exists || exit
create_staged_fs prometheus
start_staged_jail
install_prometheus
configure_prometheus
start_prometheus
test_prometheus
promote_staged_jail prometheus
