#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

install_homebridge()
{
	tell_status "install homebridge"

	stage_pkg_install node npm dbus avahi-libdns gcc
	stage_exec ln -s /usr/local/include/avahi-compat-libdns_sd/dns_sd.h /usr/include/dns_sd.h
	stage_sysrc dbus_enable="YES"
	stage_sysrc avahi_daemon_enable="YES"
	service dbus start
	service avahi-daemon start
	stage_exec npm install -g node-gyp node-pre-gyp
}

configure_homebridge()
{
	tell_status "configuring homebridge"
}

start_homebridge()
{
	tell_status "starting up homebridge"
}

test_homebridge()
{
	tell_status "testing homebridge"
	#stage_test_running
	#stage_listening
}

base_snapshot_exists || exit
create_staged_fs homebridge
start_staged_jail homebridge
install_homebridge
configure_homebridge
start_homebridge
test_homebridge
promote_staged_jail homebridge
