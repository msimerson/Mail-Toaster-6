#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include user

install_nsd()
{
	tell_status "installing NSD"
	stage_pkg_install nsd rsync || exit

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
	stage_sysrc sshd_enable=YES

	if [ ! -d "$STAGE_MNT/data/etc" ]; then
		mkdir "$STAGE_MNT/data/etc"
	fi

	if [ ! -f "$STAGE_MNT/data/etc/nsd.conf" ]; then
		tell_status "installing default nsd.conf"
		cp "$STAGE_MNT/usr/local/etc/nsd/nsd.conf" "$STAGE_MNT/data/etc/"
	else
		tell_status "linking custom nsd.conf to /usr/local"
		rm "$STAGE_MNT/usr/local/etc/nsd/nsd.conf"
		stage_exec ln -s /data/etc/nsd.conf /usr/local/etc/nsd/nsd.conf
	fi

	if [ ! -d "$STAGE_MNT/data/etc" ]; then
		mkdir "$STAGE_MNT/data/etc"
	fi

	if [ ! -f "$STAGE_MNT/data/etc/nsd.conf" ]; then
		tell_status "installing default nsd.conf"
		cp "$STAGE_MNT/usr/local/etc/nsd/nsd.conf" "$STAGE_MNT/data/etc/"
	fi

	preserve_passdb nsd
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
create_staged_fs ns3.cadillac.net
start_staged_jail ns3.cadillac.net
install_nsd
configure_nsd
start_nsd
test_nsd
promote_staged_jail ns3.cadillac.net
