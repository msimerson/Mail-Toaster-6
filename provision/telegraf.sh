#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_telegraf()
{
	tell_status "installing telegraf"
	stage_pkg_install telegraf || exit

	tell_status "Enable telegraf"
	stage_sysrc telegraf_enable=YES
}

config_telegraf()
{
	local _conf="$STAGE_MNT/usr/local/etc/telegraf.conf"

    sed -i.bak \
        -e "s/urls.*8086/ s/127.0.0.1/172.16.15.50/"
        "$_conf"
}

start_telegraf()
{
	stage_exec service telegraf start
}

test_telegraf()
{
	stage_test_running telegraf
}

base_snapshot_exists || exit
create_staged_fs telegraf
start_staged_jail telegraf
install_telegraf
config_telegraf
start_telegraf
test_telegraf
promote_staged_jail telegraf
