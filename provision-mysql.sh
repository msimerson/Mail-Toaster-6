#!/bin/sh

. mail-toaster.sh || exit

#export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/mysql \$path/var/db/mysql nullfs rw 0 0\";"

install_mysql()
{
	stage_pkg_install mysql56-server || exit
}

configure_mysql()
{
}

start_mysql()
{
	stage_sysrc mysql_enable=YES
#	stage_exec service mysql-server start || exit
	sleep 1
}

test_mysql()
{
#	stage_exec sockstat -l -4 | grep 3306 || exit
#	echo 'SHOW DATABASES' | jexec $SAFE_NAME /usr/local/bin/mysql \
#	    | grep -q mysql || exit
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_data_fs mysql
create_staged_fs mysql
stage_sysrc hostname=mysql
start_staged_jail
install_mysql
start_mysql
configure_mysql
test_mysql
promote_staged_jail mysql
