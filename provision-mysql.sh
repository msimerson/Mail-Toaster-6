#!/bin/sh

. mail-toaster.sh || exit

export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/mysql \$path/var/db/mysql nullfs rw 0 0\";"

install_mysql()
{
	tell_status "installing mysql"
	stage_pkg_install mysql56-server || exit
}

configure_mysql()
{
	true
}

start_mysql()
{
	tell_status "starting mysql"
	stage_sysrc mysql_enable=YES

	if [ -d "$ZFS_JAIL_MNT/mysql/var/db/mysql" ]; then
		# mysql jail already exists, unmount the data dir since two mysql's
		# cannot access the data
		unmount_data mysql
	fi

	stage_exec service mysql-server start || exit
}

test_mysql()
{
	tell_status "testing mysql"
	if [ -d "$ZFS_JAIL_MNT/mysql/var/db/mysql" ]; then
		true
	else
		sleep 1
		echo 'SHOW DATABASES' | stage_exec mysql || exit
		stage_exec sockstat -l -4 | grep 3306 || exit
		echo "it worked"
	fi
}

base_snapshot_exists || exit
create_staged_fs mysql
start_staged_jail
install_mysql
start_mysql
configure_mysql
test_mysql
promote_staged_jail mysql
