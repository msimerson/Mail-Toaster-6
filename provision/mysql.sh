#!/bin/sh

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
	stage_pkg_install mysql57-server || exit
}

install_mariadb()
{
	tell_status "installing mariadb"
	stage_pkg_install mariadb104-server || exit
}

configure_mysql()
{
	tell_status "configuring mysql"
	stage_sysrc mysql_args="--syslog"
	stage_sysrc mysql_optfile="/var/db/mysql/my.cnf"

	if [ -f "$ZFS_JAIL_MNT/mysql/etc/my.cnf" ]; then
		tell_status "preserving /etc/my.cnf"
		cp "$ZFS_JAIL_MNT/mysql/etc/my.cnf" "$STAGE_MNT/etc/my.cnf"
	fi

	local _dbdir="$ZFS_DATA_MNT/mysql"
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
	else
		rm "$STAGE_MNT/root/.mysql_secret"
	fi

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
	if [ -f "$STAGE_MNT/root/.mysql_secret" ]; then
		tell_status "new install, setting root password"
		local _initial_pass
		_initial_pass="$(tail -n1 "$STAGE_MNT/root/.mysql_secret")"
		if [ -z "$_initial_pass" ]; then
			echo "ERROR: unable to find the mysql initial password"
			exit 1
		fi
		echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '$TOASTER_MYSQL_PASS';" \
			| stage_exec mysql -u root --connect-expired-password --password="$_initial_pass" \
			|| exit
		rm "$STAGE_MNT/root/.mysql_secret"
	fi

	if [ -d "$ZFS_DATA_MNT/mysql/mysql" ]; then
		tell_status "reinstall, skipping tests"
		return
	fi

	tell_status "testing mysql"

	echo 'SHOW DATABASES' | stage_exec mysql --password="$TOASTER_MYSQL_PASS" || exit
	stage_listening 3306
	echo "it worked"
}

write_pass_to_conf()
{
	if grep -sq TOASTER_MYSQL_PASS mail-toaster.conf; then
		sed -i '' \
			-e "/^export TOASTER_MYSQL_PASS=/ s|=\"\"|=\"$TOASTER_MYSQL_PASS\"|" \
			mail-toaster.conf || exit
	else
		echo "export TOASTER_MYSQL_PASS=\"$TOASTER_MYSQL_PASS\"" >> mail-toaster.conf
	fi

	tee "$STAGE_MNT/root/.my.cnf" <<EO_MY_CNF
[client]
user = root
password = $TOASTER_MYSQL_PASS
EO_MY_CNF
	chmod 600 "$STAGE_MNT/root/.my.cnf"
}

set_mysql_password()
{
	if [ -z "$TOASTER_MYSQL_PASS" ]; then
		tell_status "TOASTER_MYSQL_PASS unset in mail-toaster.conf, generating a password"

		TOASTER_MYSQL_PASS=$(openssl rand -base64 15)
		export TOASTER_MYSQL_PASS
	fi

	write_pass_to_conf
}

if [ "$TOASTER_MYSQL" = "1" ] || [ "$SQUIRREL_SQL" = "1" ] || [ "$ROUNDCUBE_SQL" = "1" ]; then
	tell_status "installing MySQL"
else
	tell_status "skipping MySQL install, not configured"
	exit
fi

base_snapshot_exists || exit
create_staged_fs mysql
set_mysql_password
start_staged_jail mysql
install_db_server
start_mysql
configure_mysql
test_mysql
promote_staged_jail mysql
