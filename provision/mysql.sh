#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/mysql \$path/var/db/mysql nullfs rw 0 0\";"

install_db_server()
{
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
	stage_pkg_install mysql80-server || exit 1
}

install_mariadb()
{
	tell_status "installing mariadb"
	stage_pkg_install mariadb1011-server || exit 1
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

	local _my_cnf="$STAGE_MNT/root/.my.cnf"
	tee "$_my_cnf" <<EO_MY_CNF
[client]
user = root
password = $TOASTER_MYSQL_PASS
EO_MY_CNF
	chmod 600 "$_my_cnf"
}

configure_mysql_keys()
{
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
		tell_status "TOASTER_MYSQL_PASS unset in mail-toaster.conf, generating a password"

		TOASTER_MYSQL_PASS=$(openssl rand -base64 15)
		export TOASTER_MYSQL_PASS
	fi

	echo 'SHOW DATABASES' | stage_exec mysql --password="$TOASTER_MYSQL_PASS" \
		|| echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '$TOASTER_MYSQL_PASS';" \
			| stage_exec mysql -u root || exit 1

	write_pass_to_conf
}

configure_mysql()
{
	tell_status "configuring mysql"
	stage_sysrc mysql_optfile="/var/db/mysql/my.cnf"
	if [ ! -f "$STAGE_MNT/data/etc/my.cnf" ]; then
		sed -i '' \
			-e 's/= \/var\/db\/mysql$/= \/data\/db/g' \
			"$STAGE_MNT/usr/local/etc/mysql/my.cnf"
		# enable this when mysql port adds config setting to rc.d script
		# cp "$STAGE_MNT/usr/local/etc/mysql/my.cnf" "$STAGE_MNT/data/etc/my.cnf"
	fi

	preserve_file /etc/my.cnf

	local _dbdir="$ZFS_DATA_MNT/mysql"
	if [ ! -d "$_dbdir" ]; then mkdir "$_dbdir" || exit 1; fi

	local _my_cnf="$_dbdir/my.cnf"
	if [ ! -f "$_my_cnf" ]; then
		tell_status "installing $_my_cnf"
		tee -a "$_my_cnf" <<EO_MY_CNF
[mysqld]
innodb_doublewrite = off
innodb_file_per_table = 1
innodb_checksum_algorithm = none
innodb_flush_neighbors = 0
EO_MY_CNF
	fi

	configure_mysql_keys
	configure_mysql_root_password
}

start_mysql()
{
	tell_status "starting mysql"
	stage_sysrc mysql_enable=YES

	if [ -d "$ZFS_JAIL_MNT/mysql/var/db/mysql" ]; then
		# update, mysql jail exists, unmount the data dir, two mysql's
		# cannot access the data concurrently
		unmount_data mysql
	fi

	stage_exec service mysql-server start || exit
}

test_mysql()
{
	tell_status "testing mysql"
	stage_listening 3306 2
	echo 'SHOW DATABASES' | stage_exec mysql --password="$TOASTER_MYSQL_PASS" || exit 1
	echo "it worked"
}

if [ "$TOASTER_MYSQL" = "1" ] || [ "$SQUIRREL_SQL" = "1" ] || [ "$ROUNDCUBE_SQL" = "1" ]; then
	tell_status "installing MySQL"
else
	tell_status "skipping MySQL install, not configured"
	exit
fi

base_snapshot_exists || exit
create_staged_fs mysql
start_staged_jail mysql
install_db_server
start_mysql
configure_mysql
test_mysql
promote_staged_jail mysql
