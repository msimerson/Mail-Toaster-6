#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

mt6-include user

install_beaded_api()
{
	tell_status "installing beadedstream API"
	stage_pkg_install npm-node16 git-lite mongodb44 mongodb-tools ssmtp
	stage_exec bash -c "cd /data/db && npm install"
	stage_exec bash -c "cd /data/db/api && npm install"
	stage_exec npm install -g pm2
}

configure_beaded_api()
{
	tell_status "configuring beaded_api"

	preserve_passdb beaded_api
	preserve_ssh_host_keys beaded_api

	cp /data/beaded_api/rc.d/pm2_beaded "$STAGE_MNT/usr/local/etc/rc.d/"
	stage_sysrc pm2_beaded_enable="YES"
	stage_sysrc sshd_enable="YES"
}

start_beaded_api()
{
	tell_status "configuring beaded_api"
	stage_exec service pm2_beaded start
}

test_beaded_api()
{
	tell_status "testing beaded_api"
	stage_listening 3000
	echo "it works"
}

base_snapshot_exists || exit
create_staged_fs beaded_api
start_staged_jail beaded_api
install_beaded_api
configure_beaded_api
start_beaded_api
test_beaded_api
promote_staged_jail beaded_api
