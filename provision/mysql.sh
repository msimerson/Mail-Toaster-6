#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

install_db_server()
{
	for _d in etc db; do
		_path="$STAGE_MNT/data/$_d"
		if [ ! -d "$_path" ]; then
			mkdir "$_path"
			chown 88:88 "$_path"
		fi
	done

	# Check if MariaDB needs to be installed
	if [ "$TOASTER_MARIADB" = "1" ]; then
		install_mariadb
	else
		install_mysql
	fi
}

install_mysql()
{
	tell_status "installing mysql"
	stage_pkg_install mysql84-server
}

install_mariadb()
{
	tell_status "installing mariadb"
	stage_pkg_install mariadb1011-server
}

write_pass_to_conf()
{
	if grep -sq TOASTER_MYSQL_PASS mail-toaster.conf; then
		sed_inplace \
			-e "/^export TOASTER_MYSQL_PASS=/ s|=\"\"|=\"$TOASTER_MYSQL_PASS\"|" \
			mail-toaster.conf
	else
		echo "export TOASTER_MYSQL_PASS=\"$TOASTER_MYSQL_PASS\"" >> mail-toaster.conf
	fi

	preserve_file mysql /root/.my.cnf

	local _my_cnf="$STAGE_MNT/root/.my.cnf"
	if [ ! -f "$_my_cnf" ]; then
		tee "$_my_cnf" <<EO_MY_CNF
[client]
user = root
password = $TOASTER_MYSQL_PASS
EO_MY_CNF
		chmod 600 "$_my_cnf"
	fi
}

configure_mysql_keys()
{
	local _dbdir="$ZFS_DATA_MNT/mysql/db"

	if [ ! -f "$_dbdir/private_key.pem" ]; then
		tell_status "enabling sha256_password support"
		openssl genrsa -out "$_dbdir/private_key.pem" 2048
		chown 88:88 "$_dbdir/private_key.pem"
		chmod 400 "$_dbdir/private_key.pem"
	fi

	if [ ! -f "$_dbdir/public_key.pem" ]; then
		openssl rsa -in "$_dbdir/private_key.pem" -pubout -out "$_dbdir/public_key.pem"
		chown 88:88 "$_dbdir/public_key.pem"
		chmod 444 "$_dbdir/public_key.pem"
	fi
}

configure_mysql_root_password()
{
	if [ -z "$TOASTER_MYSQL_PASS" ]; then
		tell_status "TOASTER_MYSQL_PASS unset in mail-toaster.conf"

		local _my_cnf="$ZFS_JAIL_MNT/mysql/root/my.cnf"
		if [ -f "$_my_cnf" ] && [ -r "$_my_cnf" ]; then
			tell_status "TOASTER_MYSQL_PASS unset in $_my_cnf"
			TOASTER_MYSQL_PASS=$(grep password "$_my_cnf" | awk '{ print $3 }')
		fi

		if [ -z "$TOASTER_MYSQL_PASS" ]; then
			tell_status "generating a random password for MySQL"
			TOASTER_MYSQL_PASS=$(get_random_pass 15 safe)
		fi
		export TOASTER_MYSQL_PASS
	fi

	echo 'SHOW DATABASES' | stage_exec mysql --password="$TOASTER_MYSQL_PASS" \
		|| echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '$TOASTER_MYSQL_PASS';" \
			| stage_exec mysql -u root

	write_pass_to_conf
}

configure_mysql_ram()
{
	local _my_cnf="$1"
	local _physmem; _physmem=$(sysctl -n hw.physmem 2>/dev/null || echo 0)
	local _8gb=8589934592

	if [ "$_physmem" -le 0 ] || [ "$_physmem" -ge "$_8gb" ]; then
		return
	fi

	tell_status "system RAM < 8GB, capping innodb_buffer_pool_size to 512M"
	if grep -q innodb_buffer_pool_size "$_my_cnf"; then
		sed_inplace \
			-e '/^innodb_buffer_pool_size/ s/=.*/= 512M/' \
			"$_my_cnf"
	else
		printf "\ninnodb_buffer_pool_size = 512M\n" >> "$_my_cnf"
	fi
}

configure_mysql()
{
	tell_status "configuring mysql"
	local _my_cnf="$STAGE_MNT/usr/local/etc/mysql/my.cnf"
	# MariaDB has my.cnf but the interesting piece is in conf.d/server.cnf
	[ "$TOASTER_MARIADB" != 1 ] || _my_cnf="$STAGE_MNT/usr/local/etc/mysql/conf.d/server.cnf"
	if [ ! -f "$STAGE_MNT/data/etc/my.cnf" ]; then
		if [ -f "$_my_cnf" ]; then
			sed_inplace \
				-e 's/= \/var\/db\/mysql$/= \/data\/db/g' \
				"$_my_cnf"
		else
			sed \
				-e 's/= \/var\/db\/mysql$/= \/data\/db/g' \
				"${_my_cnf}.sample" > "$_my_cnf"
		fi
	fi

	stage_sysrc mysql_enable=YES
	stage_sysrc mysql_dbdir="/data/db"
	stage_sysrc mysql_optfile="/data/etc/extra.cnf"

	local _dbdir="$ZFS_DATA_MNT/mysql/db"

	local _my_cnf="$STAGE_MNT/data/etc/extra.cnf"
	store_config "$_my_cnf" <<EO_MY_CNF
[mysqld]
datadir                         = /data/db
innodb_data_home_dir            = /data/db
innodb_log_group_home_dir       = /data/db

innodb_doublewrite = off
innodb_file_per_table = 1
innodb_checksum_algorithm = none
innodb_flush_neighbors = 0
EO_MY_CNF

	configure_mysql_ram "$_my_cnf"

	store_config "$STAGE_MNT/usr/local/etc/newsyslog.conf.d/mysql.conf" <<EO_ERR
/data/db/mysql.err    mysql:mysql    640  7  250000  *  Z
EO_ERR
}

start_mysql()
{
	tell_status "starting mysql"

	if [ -d "$ZFS_JAIL_MNT/mysql/data/db/mysql" ]; then
		# mysql jail exists, unmount the data dir as two mysql's
		# cannot access the data concurrently
		tell_status "unmounting live mysql data FS"
		unmount_data mysql
	fi

	stage_exec service mysql-server start
	configure_mysql_root_password
	configure_mysql_keys
}

test_mysql()
{
	tell_status "testing mysql"
	stage_listening 3306 2
	echo 'SHOW DATABASES' | stage_exec mysql --password="$TOASTER_MYSQL_PASS"
	echo "it worked"
}

migrate_mysql_dbs()
{
	if [ -f "$ZFS_DATA_MNT/mysql/mysql.err" ]; then
		echo "
	HALT: mysql data migration required.

	See https://github.com/msimerson/Mail-Toaster-6/wiki/Updating
		"
		exit 1
	fi

	if jail_is_running mysql; then
		echo "mysql jail is running"

		_my_ver=$(pkg -j mysql info | grep mysql | grep server | cut -f1 -d' ' | cut -d- -f3)
		if [ -n "$_my_ver" ]; then
			_major=$(echo "$_my_ver" | cut -f1 -d'.')
			if [ "$_major" -lt "8" ]; then
				echo "
	HALT: mysql upgrade to version 8 required.

	See https://github.com/msimerson/Mail-Toaster-6/wiki/Updating
				"
				exit 1

			fi
		fi
	fi
}

check_mysql_native_passwords()
{
	# MySQL 8.4 disables mysql_native_password and 9.0 removes it.
	# Before staging an 8.4 install over a running 8.0, verify no
	# accounts still depend on it; if any do, halt with the ALTER USER
	# statements needed to migrate them to caching_sha2_password.
	jail_is_running mysql || return 0

	local _my_ver
	_my_ver=$(pkg -j mysql info | grep mysql | grep server | cut -f1 -d' ' | cut -d- -f3)
	[ -z "$_my_ver" ] && return 0

	local _major _minor
	_major=$(echo "$_my_ver" | cut -f1 -d'.')
	_minor=$(echo "$_my_ver" | cut -f2 -d'.')

	if [ "$_major" != "8" ] || [ "$_minor" != "0" ]; then
		return 0
	fi

	# Operator opt-in: MySQL 8.4 still ships the mysql_native_password plugin
	# but leaves it disabled by default. Setting mysql_native_password=ON in
	# [mysqld] re-enables it, so the upgrade is safe even with accounts that
	# still use the plugin.
	local _extra_cnf="$ZFS_DATA_MNT/mysql/etc/extra.cnf"
	if [ -f "$_extra_cnf" ] && awk '
		/^[[:space:]]*\[mysqld\][[:space:]]*$/ { in_section = 1; next }
		/^[[:space:]]*\[/                      { in_section = 0 }
		in_section && tolower($0) ~ /^[[:space:]]*mysql_native_password[[:space:]]*=[[:space:]]*on[[:space:]]*(#.*)?$/ { found = 1; exit }
		END { exit !found }
	' "$_extra_cnf"; then
		tell_status "mysql_native_password=ON set in $_extra_cnf; allowing 8.4 upgrade"
		return 0
	fi

	tell_status "MySQL 8.0 detected — scanning for accounts using deprecated auth plugins"

	local _query="SELECT CONCAT('ALTER USER ''', user, '''@''', host, ''' IDENTIFIED WITH caching_sha2_password BY ''<new_password>'';') FROM mysql.user WHERE plugin IN ('mysql_native_password') AND user NOT IN ('mysql.infoschema','mysql.session','mysql.sys');"

	local _alters
	_alters=$(echo "$_query" | jexec mysql mysql -N -B 2>/dev/null) || _alters=""

	if [ -z "$_alters" ]; then
		tell_status "no accounts using deprecated auth plugins; safe to upgrade to 8.4"
		return 0
	fi

	echo "
	HALT: MySQL 8.0 is EOL and 8.4 removes the mysql_native_password and
	sha256_password authentication plugins. The accounts below still use a
	deprecated plugin and must be migrated to caching_sha2_password before
	the 8.4 upgrade can proceed.

	Connect to the running mysql 8.0 jail and run each statement, substituting
	a real password for each <new_password> placeholder:

		jexec mysql mysql

$_alters

	After migrating every account, re-run this provision script.

	See https://dev.mysql.com/doc/refman/8.4/en/mysql-nutshell.html
	"
	exit 1
}

if [ "$TOASTER_MYSQL" = "1" ] || [ "$SQUIRREL_SQL" = "1" ] || [ "$ROUNDCUBE_SQL" = "1" ]; then
	tell_status "installing MySQL"
else
	tell_status "skipping MySQL install, not configured"
	exit
fi

base_snapshot_exists || exit 1
migrate_mysql_dbs
check_mysql_native_passwords
create_staged_fs mysql
start_staged_jail mysql
install_db_server
configure_mysql
start_mysql
test_mysql
promote_staged_jail mysql
