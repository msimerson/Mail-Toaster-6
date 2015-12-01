#!/bin/sh

. mail-toaster.sh || exit

install_mysql()
{
	pkg -j $SAFE_NAME install -y mysql56-server || exit
}

create_data_fs()
{
	MY_DATA="${ZFS_VOL}/mysql-data"
	zfs_filesystem_exists $MY_DATA && return

	echo "zfs create -o mountpoint=$ZFS_JAIL_MNT/mysql/var/db/mysql $MY_DATA"
	zfs create -o mountpoint=$ZFS_JAIL_MNT/mysql/var/db/mysql $MY_DATA
}

configure_mysql()
{
	GRANT="GRANT ALL PRIVILEGES ON"
	RANDPASS="openssl rand -hex 18"
	JAIL_NET_PREFIX=${JAIL_NET_PREFIX:=127.0.0}
	TMP_FILE=$STAGE_MNT/tmp/mysql-toaster-users.sql

	echo "creating $TMP_FILE"
	tee $TMP_FILE <<EO_HEREDOC
create database dspam;
$GRANT dspam.* to 'dspam'@'$JAIL_NET_PREFIX.7' IDENTIFIED BY '`$RANDPASS`';
create database spamassassin;
$GRANT spamassassin.* to 'spamassassin'@'$JAIL_NET_PREFIX.6' IDENTIFIED BY '`$RANDPASS`';
create database vpopmail;
$GRANT vpopmail.* to 'vpopmail'@'$JAIL_NET_PREFIX.8' IDENTIFIED BY '`$RANDPASS`';
EO_HEREDOC

	echo "jexec $SAFE_NAME /usr/local/bin/mysql < $TMP_FILE"
	jexec $SAFE_NAME /usr/local/bin/mysql < $TMP_FILE || exit
}

start_mysql()
{
	stage_sysrc mysql_enable=YES
	stage_exec service mysql-server start || exit
	sleep 1
}

test_mysql()
{
	echo 'SHOW DATABASES' | jexec $SAFE_NAME /usr/local/bin/mysql \
	    | grep -q spamassassin || exit
}

unmount_data_directory()
{
	if mount | grep ^${ZFS_VOL}/mysql-data; then
		zfs unmount $ZFS_VOL/mysql-data || exit
	fi
}

mount_data_directory()
{
	zfs mount $ZFS_VOL/mysql-data || exit
}

promote_staged_jail()
{
	stop_staged_jail

	rename_fs_staged_to_ready mysql
	stop_active_jail mysql
	unmount_data_directory
	rename_fs_active_to_last mysql
	rename_fs_ready_to_active mysql
	mount_data_directory

	echo "start jail $1"
	service jail start $1 || exit
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_staged_fs
stage_sysrc hostname=mysql
start_staged_jail
install_mysql
create_data_fs
start_mysql
configure_mysql
test_mysql
promote_staged_jail mysql
proclaim_success mysql
