#!/bin/sh

. mail-toaster.sh || exit

install_avg()
{
	# TODO
#	mkdir /tmp/avg $JAILS_MNT/avg/var/tmp/avg $JAILS_MNT/haraka/var/tmp/avg || exit
#	sed -i.bak -e 's/#mount +=  "\/tmp\/avg/mount +=  "\/tmp\/avg/' /etc/jail.conf

	stage_exec make -C /usr/ports/misc/compat7x install distclean
	stage_fbsd_package lib32
	fetch -o $STAGE_MNT/usr/lib32/libiconv.so.3 http://mail-toaster.org/install/libiconv.so.3

	sysrc -R $STAGE_MNT ldconfig32_paths="\$ldconfig32_paths /opt/avg/av/lib"
	mkdir -p $STAGE_MNT/usr/local/etc/rc.d || exit

	fetch -m http://download.avgfree.com/filedir/inst/avg2013ffb-r3115-a6155.i386.tar.gz || exit
	tar -C $STAGE_MNT/tmp -xzf avg2013ffb-r3115-a6155.i386.tar.gz || exit
	jexec $SAFE_NAME /tmp/avg2013ffb-r3115-a6155.i386/install.sh
}

configure_avg()
{
	stage_exec avgcfgctl -w Default.aspam.spamassassin.enabled="false"
	stage_exec avgcfgctl -w Default.tcpd.avg.address="127.0.0.14"
	stage_exec avgcfgctl -w Default.tcpd.smtp.enabled="false"
	stage_exec avgcfgctl -w Default.tcpd.spam.enabled="false"
	stage_exec avgcfgctl -w Default.setup.features.oad="false"
}

start_avg()
{
	stage_exec service avgd.sh restart || \
		stop_staged_jail && start_staged_jail
}

test_avg()
{
	echo "testing AVG..."
	ps ax -J $SAFE_NAME | grep avg || exit
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_staged_fs
stage_sysrc hostname=avg
start_staged_jail
stage_mount_ports
install_avg
configure_avg
start_avg
test_avg
stage_unmount_ports
promote_staged_jail avg
