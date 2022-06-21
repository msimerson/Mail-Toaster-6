#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

install_isaac()
{
	tell_status "installing Isaac"
	stage_pkg_install python37
}

configure_isaac()
{
	tell_status "configuring isaac"
	echo "WARN: manually copy passwd & group files over"
}

start_isaac()
{
	tell_status "configuring isaac"
}

test_isaac()
{
	tell_status "testing isaac"
}

base_snapshot_exists || exit
create_staged_fs isaac
start_staged_jail isaac
install_isaac
configure_isaac
start_isaac
test_isaac
promote_staged_jail isaac
