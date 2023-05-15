#!/bin/sh

# shellcheck disable=SC2046

_root="$ZFS_JAIL_MNT/mysql/root"

mysql_password_set()
{
	if [ -f "$_root/.mylogin.cnf" ]; then return 0; fi
	if grep -qs ^password "$_root/.my.cnf"; then return 0; fi

	return 1
}

mysql_bin()
{
	if mysql_password_set; then
		echo "/usr/local/bin/mysql"
		return
	fi

	# set in toaster-watcher.conf
	if [ -n "$TOASTER_MYSQL_PASS" ]; then
		echo "/usr/local/bin/mysql --password=\"$TOASTER_MYSQL_PASS\""
		return
	fi

	echo "/usr/local/bin/mysql"
}

mysql_query()
{
	if [ -n "$1" ]; then
		echo "db: $1"
		jexec mysql $(mysql_bin) "$1" || return 1
	else
		jexec mysql $(mysql_bin) || return 1
	fi

	return 0
}

mysql_create_db()
{
	if mysql_db_exists "$1"; then
		tell_status "$1 db exists in mysql"
		return 0
	fi

	tell_status "creating mysql database $1"
	echo "CREATE DATABASE $1 CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;" | mysql_query || return 1
	return 0
}

mysql_db_exists()
{
	local _query="SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='$1';"
	result=$(echo "$_query" | jexec mysql $(mysql_bin) -s -N)

	if [ -z "$result" ]; then
		echo "$1 db does not exist"
		return 1
	fi

	echo "$1 db exists"
	return 0
}

mysql_user_exists()
{
	local _query="SELECT * FROM mysql.user WHERE User='$1' AND Host='$2';"
	result=$(echo "$_query" | jexec mysql $(mysql_bin) -s -N)

	if [ -z "$result" ]; then
		echo "$1 user does not exist"
		return 1
	fi

	echo "$1 user exists"
	return 0
}
