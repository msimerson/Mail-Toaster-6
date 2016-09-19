#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

# shellcheck disable=2016
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/memcached \$path/data nullfs rw 0 0\";"

install_memcached()
{
	tell_status "installing Memcached"
	stage_pkg_install memcached

}

start_memcached()
{
	tell_status "starting Memcached"
	stage_sysrc memcached_enable=YES
	stage_exec service memcached start

}

test_memcached()
{
	tell_status "testing memcached"
	stage_exec sockstat -l -4 | grep :11211 || exit
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs memcached
start_staged_jail
install_memcached
start_memcached
test_memcached
promote_staged_jail memcached
