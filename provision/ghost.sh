#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_ghost()
{
	tell_status "install ghost"

	stage_pkg_install npm-node18 || exit
	stage_exec npm install -g ghost-cli@latest
}

configure_ghost()
{
	tell_status "configuring ghost"
	if [ -d "$STAGE_MNT/data/www/ghost" ]; then return; fi

	mkdir -p "$STAGE_MNT/data/www/ghost"
	stage_exec bash -c 'cd /data/www/ghost && ghost install local'
}

start_ghost()
{
	tell_status "starting up ghost"
	stage_exec bash -c 'cd /data/www/ghost && ghost start || exit 1'
}

test_ghost()
{
	tell_status "testing ghost"
	stage_listening 2368 3
}

base_snapshot_exists || exit
create_staged_fs ghost
start_staged_jail ghost
install_ghost
configure_ghost
start_ghost
test_ghost
promote_staged_jail ghost
