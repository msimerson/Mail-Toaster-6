#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/mysql \$path/var/db/mysql nullfs rw 0 0\";"

install_db_server()
{
	#Check if MariaDB needs to be installed
	if [ "$TOASTER_MARIADB" = "1" ]; then
		install_mariadb
	else
		install_mysql
	fi
}

install_mysql()
{
	tell_status "installing mysql"
	stage_pkg_install mysql56-server || exit
}

install_mariadb()
{
	tell_status "installing mariadb"
	stage_pkg_install mariadb101-server || exit
}

configure_mysql()
{
	tell_status "configuring mysql"
	stage_sysrc mysql_args="--syslog"

	if [ -f "$ZFS_JAIL_MNT/mysql/etc/my.cnf" ]; then
		tell_status "preserving /etc/my.cnf"
		cp "$ZFS_JAIL_MNT/mysql/etc/my.cnf" "$STAGE_MNT/etc/my.cnf"
	fi

	local _dbdir="$ZFS_DATA_MNT/mysql/var/db/mysql"
	if [ ! -d "$_dbdir" ]; then
		mkdir -p "$_dbdir" || exit
	fi

	local _my_cnf="$_dbdir/my.cnf"
	if [ ! -f "$_my_cnf" ]; then
		tell_status "installing $_my_cnf"
		tee -a "$_my_cnf" <<EO_MY_CNF
[mysqld]
innodb_doublewrite = off
innodb_file_per_table = 1
EO_MY_CNF
	fi

}

start_mysql()
{
	tell_status "starting mysql"
	stage_sysrc mysql_enable=YES

	if [ -d "$ZFS_JAIL_MNT/mysql/var/db/mysql" ]; then
		# mysql jail already exists, unmount the data dir since two mysql's
		# cannot access the data concurrently
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
		stage_listening 3306
		echo "it worked"
	fi
}

base_snapshot_exists || exit
create_staged_fs mysql
start_staged_jail mysql
install_db_server
start_mysql
configure_mysql
test_mysql
promote_staged_jail mysql
