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
	local _db=${1:-""}
	if [ -n "$_db" ]; then
		echo "db: $_db"
		jexec mysql $(mysql_bin) "$_db" || return 1
	else
		jexec mysql $(mysql_bin) || return 1
	fi

	return 0
}

mysql_create_db()
{
	if mysql_db_exists "$1"; then
		tell_status "mysql db exists: $1"
		return 0
	fi

	tell_status "mysql creating db $1"
	echo "CREATE DATABASE $1 CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;" | mysql_query || return 1
	return 0
}

mysql_db_exists()
{
	local _query="SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='$1';"
	local result
	result=$(echo "$_query" | jexec mysql $(mysql_bin) -s -N)

	if [ -z "$result" ]; then
		echo "mysql db missing: $1"
		return 1
	fi

	echo "mysql db exists: $1"
	return 0
}

mysql_user_exists()
{
	local _query="SELECT * FROM mysql.user WHERE User='$1' AND Host='$2';"
	local result
	result=$(echo "$_query" | jexec mysql $(mysql_bin) -s -N)

	if [ -z "$result" ]; then
		echo "mysql user missing: $1@$2"
		return 1
	fi

	echo "mysql user exists: $1@$2"
	return 0
}

mysql_error_warning()
{
	echo; echo "-----------------"
	echo "WARNING: could not connect to MySQL. (Maybe it's password protected?)"
	echo "If this is a new install, you will need to manually set up MySQL."
	echo "-----------------"; echo
	sleep 5
}

mysql_create_user()
{
	local _user="$1"
	local _pass="$2"
	local _db="$3"

	shift 3

	for _host in "$@"; do
		local _query="CREATE USER '$_user'@'$_host' IDENTIFIED BY '$_pass';"
		local _grant="GRANT ALL PRIVILEGES ON $_db.* to '$_user'@'$_host';"

		if ! mysql_user_exists "$_user" "$_host"; then
			echo "$_query"
			echo "$_query" | mysql_query
			echo "$_grant"
			echo "$_grant" | mysql_query
		fi
	done
}

