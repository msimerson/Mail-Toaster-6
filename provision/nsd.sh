#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_nsd()
{
	tell_status "installing NSD"
	stage_pkg_install nsd rsync dialog4ports || exit

	if [ ! -d "$STAGE_MNT/data/home/nsd" ]; then
		mkdir -p "$STAGE_MNT/data/home/nsd" || exit
		chown 216:216 "$STAGE_MNT/data/home/nsd"
	fi

	stage_exec pw user mod nsd -u 216 -g 216 -s /bin/sh -d /data/home/nsd
}

configure_nsd()
{
	stage_sysrc nsd_enable=YES
	stage_sysrc nsd_config=/data/etc/nsd.conf

	for _f in master.password group;
	do
		if [ -f "$ZFS_JAIL_MNT/nsd/etc/$_f" ]; then
			cp "$ZFS_JAIL_MNT/nsd/etc/$_f" "$STAGE_MNT/etc/"
			stage_exec pwd_mkdb -p /etc/master.passwd
		fi
	done
}

start_nsd()
{
	tell_status "starting nsd daemon"
	stage_exec service nsd start || exit
}

test_nsd()
{
	tell_status "testing nsd"
	stage_test_running nsd

	stage_listening 53
	echo "it worked."

	tell_status "testing UDP DNS query"
	drill    www.example.com @"$(get_jail_ip stage)" || exit

	tell_status "testing TCP DNS query"
	drill -t www.example.com @"$(get_jail_ip stage)" || exit
}

base_snapshot_exists || exit
create_staged_fs nsd
start_staged_jail nsd
install_nsd
configure_nsd
start_nsd
test_nsd
promote_staged_jail nsd
