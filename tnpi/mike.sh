#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

install_mike()
{
	tell_status "installing Mike"
	stage_pkg_install mtr-nox11
}

configure_mike()
{
	tell_status "configuring mike"
}

start_mike()
{
	tell_status "configuring mike"
}

test_mike()
{
	tell_status "testing mike"
}

base_snapshot_exists || exit
create_staged_fs mike
start_staged_jail mike
install_mike
configure_mike
start_mike
test_mike
promote_staged_jail mike
