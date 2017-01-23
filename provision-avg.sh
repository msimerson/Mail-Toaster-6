#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA="allow.sysvipc=1"
export JAIL_CONF_EXTRA="
		allow.sysvipc = 1;
		mount.fdescfs;
		mount.procfs;
		mount += \"$ZFS_DATA_MNT/avg \$path/data/avg nullfs rw 0 0\";"

install_avg_data_fs()
{
	tell_status "setting up AVG data filesystem"
	for d in $ZFS_DATA_MNT/avg/spool $ZFS_DATA_MNT/avg/update $ZFS_DATA_MNT/avg/var-data; do
		if [ ! -d "$d" ]; then
			echo "mkdir $d"
			mkdir "$d" || exit
		fi
	done

	tell_status "linking AVG dirs to data FS"
	mkdir -p "$STAGE_MNT/opt/avg/av"  || exit
	stage_exec ln -s /data/avg/update /opt/avg/av/update || exit

	mkdir -p "$STAGE_MNT/opt/avg/av/var" || exit
	stage_exec ln -s /data/avg/var-data /opt/avg/av/var/data || exit
}

install_avg()
{
	tell_status "making FreeBSD like 2008 (32-bit)"
	stage_fbsd_package lib32

	tell_status "installing FreeBSD 7.x compatibility"
	stage_exec make -C /usr/ports/misc/compat7x install distclean

	tell_status "installing ancient libiconv.so.3"
	fetch -o "$STAGE_MNT/usr/lib32/libiconv.so.3" http://mail-toaster.org/install/libiconv.so.3
	sysrc -R "$STAGE_MNT" ldconfig32_paths="\$ldconfig32_paths /opt/avg/av/lib"

	install_avg_data_fs

	tell_status "downloading avg2013ffb-r3115-a6155.i386.tar.gz"
	fetch -m http://download.avgfree.com/filedir/inst/avg2013ffb-r3115-a6155.i386.tar.gz || exit

	tell_status "installing avg"
	tar -C "$STAGE_MNT/tmp" -xzf avg2013ffb-r3115-a6155.i386.tar.gz || exit
	mkdir -p "$STAGE_MNT/usr/local/etc/rc.d" || exit
	stage_exec /tmp/avg2013ffb-r3115-a6155.i386/install.sh
}

configure_avg()
{
	tell_status "configuring avg"
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
	# shellcheck disable=2009
	ps ax -J stage | grep avg || exit

	tell_status "verifying avgtcpd is listening"
	stage_listening 54322
	echo "it works"
}

base_snapshot_exists || exit
create_staged_fs avg
stage_sysrc hostname=avg
start_staged_jail avg
install_avg
configure_avg
start_avg
test_avg
promote_staged_jail avg
