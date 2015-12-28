#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA="allow.sysvipc=1"
export JAIL_CONF_EXTRA="
		allow.sysvipc = 1;
		mount.fdescfs;
		mount.procfs;
		mount += \"$ZFS_DATA_MNT/avg \$path/data/avg nullfs rw 0 0\";"

install_avg()
{
	tell_status "making FreeBSD like 2008"
	fetch -m http://download.avgfree.com/filedir/inst/avg2013ffb-r3115-a6155.i386.tar.gz || exit

	stage_exec make -C /usr/ports/misc/compat7x install distclean
	stage_fbsd_package lib32
	fetch -o "$STAGE_MNT/usr/lib32/libiconv.so.3" http://mail-toaster.org/install/libiconv.so.3

	sysrc -R "$STAGE_MNT" ldconfig32_paths="\$ldconfig32_paths /opt/avg/av/lib"
	mkdir -p "$STAGE_MNT/usr/local/etc/rc.d" || exit

	tell_status "installing avgd"
	tar -C "$STAGE_MNT/tmp" -xzf avg2013ffb-r3115-a6155.i386.tar.gz || exit
	mkdir -p "$STAGE_MNT/opt/avg"
	stage_exec /tmp/avg2013ffb-r3115-a6155.i386/install.sh
}

configure_avg()
{
	tell_status "configuring avgd"
	stage_exec avgcfgctl -w Default.aspam.spamassassin.enabled="false"
	stage_exec avgcfgctl -w Default.tcpd.avg.address="0.0.0.0"
	stage_exec avgcfgctl -w Default.tcpd.smtp.enabled="false"
	stage_exec avgcfgctl -w Default.tcpd.spam.enabled="false"
	stage_exec avgcfgctl -w Default.setup.features.oad="false"
}

start_avg()
{
	tell_status "starting avgd"
	stage_exec service avgd.sh restart

	tell_status "downloading virus databases"
	stage_exec avgupdate
}

test_avg()
{
	tell_status "testing if AVG process is running"
	sleep 2
	ps ax -J stage | grep avg || exit

	tell_status "verifying avgtcpd is listening"
	sockstat -l | grep 54322 || exit
	echo "it works"
}

base_snapshot_exists || exit
create_staged_fs avg
stage_sysrc hostname=avg
start_staged_jail
install_avg
configure_avg
start_avg
test_avg
promote_staged_jail avg
