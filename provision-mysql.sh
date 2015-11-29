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
create database roundcubemail;
$GRANT roundcubemail.* to 'roundcube'@'$JAIL_NET_PREFIX.10' IDENTIFIED BY '`$RANDPASS`';
create database squirrelmail;
$GRANT squirrelmail.* to 'squirrelmail'@'$JAIL_NET_PREFIX.10' IDENTIFIED BY '`$RANDPASS`';
create database vpopmail;
$GRANT vpopmail.* to 'vpopmail'@'$JAIL_NET_PREFIX.8' IDENTIFIED BY '`$RANDPASS`';
EO_HEREDOC

	echo "jexec $SAFE_NAME /usr/local/bin/mysql < $TMP_FILE"
	jexec $SAFE_NAME /usr/local/bin/mysql < $TMP_FILE || exit
}

start_mysql()
{
	sysrc -f $STAGE_MNT/etc/rc.conf mysql_enable=YES
	jexec $SAFE_NAME service mysql-server start || exit
	sleep 1
}

test_mysql()
{
	echo 'SHOW DATABASES' | jexec $SAFE_NAME /usr/local/bin/mysql \
	    | grep -q spamassassin || exit
}

rename_active_fs()
{
	local LAST="$ZFS_JAIL_VOL/$1.last"
	local ACTIVE="$ZFS_JAIL_VOL/$1"

	if [ -d "$LAST" ]; then
		echo "zfs destroy $LAST"
		zfs destroy $LAST || exit
	fi

	if [ -d "$ACTIVE" ]; then
		echo "zfs rename $ACTIVE $LAST"
		zfs rename $ACTIVE $LAST || exit
	fi
}

renamed_staged_fs()
{
	local _new_vol="$ZFS_JAIL_VOL/${1}.new"

	 # clean up stages that failed promotion
    if [ -d "$ZFS_JAIL_MNT/${1}.new" ]; then
        echo "zfs destroy $_new_vol (failed promotion)"
        zfs destroy $_new_vol || exit
    else
        echo "$_new_vol does not exist"
    fi

	# get the wait over with before shutting down production jail
	echo "zfs rename $STAGE_VOL $_new_vol"
	zfs rename $STAGE_VOL $_new_vol || ( \
			echo "waiting 60 seconds for ZFS filesystem to settle" \
			&& sleep 60 \
			&& zfs rename $STAGE_VOL $_new_vol \
		) || exit
}

stop_production_jail()
{
	echo "shutdown jail $1"
	service jail stop $1 || exit
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

	local _staged_ready_name="$ZFS_JAIL_VOL/${1}.new"

	renamed_staged_fs "$1"

	stop_production_jail
	unmount_data_directory

	rename_active_fs mysql

	echo "zfs rename $_staged_ready_name $ZFS_JAIL_VOL/$1"
	zfs rename $_staged_ready_name $ZFS_JAIL_VOL/$1 || exit

	mount_data_directory

	echo "start jail $1"
	service jail start $1 || exit
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_staged_fs
sysrc -f $STAGE_MNT/etc/rc.conf hostname=mysql
start_staged_jail $SAFE_NAME $STAGE_MNT
install_mysql
create_data_fs
start_mysql
configure_mysql
test_mysql
promote_staged_jail mysql
proclaim_success mysql
