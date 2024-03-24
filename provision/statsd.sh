#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

install_statsd()
{
	tell_status "installing statsd"
	stage_pkg_install statsd || exit

	tell_status "Enable statsd"
	stage_sysrc statsd_enable=YES

	mkdir "$STAGE_MNT/var/lib"
	chown 907:907 "$STAGE_MNT/var/lib"

	sed -i '' \
		-e "s/ process\./ require('events')\./" \
		"$STAGE_MNT/usr/local/share/statsd/lib/config.js"
}

start_statsd()
{
	stage_exec service statsd start
}

test_statsd()
{
	stage_test_running statsd
}

base_snapshot_exists || exit
create_staged_fs statsd
start_staged_jail statsd
install_statsd
start_statsd
test_statsd
promote_staged_jail statsd
