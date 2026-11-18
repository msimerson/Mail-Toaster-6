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

db_client()
{
	# MariaDB 11+ warns when its client is run by the mysql name
	if [ "$TOASTER_MARIADB" = "1" ]; then
		echo mariadb
	else
		echo mysql
	fi
}

install_mariadb()
{
	tell_status "installing mariadb"
	stage_pkg_install mariadb123-server
}

write_pass_to_conf()
{
	if grep -sq TOASTER_MYSQL_PASS "$MT6_CONF"; then
		sed_inplace \
			-e "/^export TOASTER_MYSQL_PASS=/ s|=\"\"|=\"$TOASTER_MYSQL_PASS\"|" \
			"$MT6_CONF"
	else
		mkdir -p "$(dirname "$MT6_CONF")"
		echo "export TOASTER_MYSQL_PASS=\"$TOASTER_MYSQL_PASS\"" >> "$MT6_CONF"
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
	local _dbdir
	_dbdir="$(get_jail_data mysql)/db"

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
		tell_status "TOASTER_MYSQL_PASS unset in $MT6_CONF"

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

	echo 'SHOW DATABASES' | stage_exec "$(db_client)" --password="$TOASTER_MYSQL_PASS" \
		|| echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '$TOASTER_MYSQL_PASS';" \
			| stage_exec "$(db_client)" -u root

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

migrate_extra_cnf()
{
	# An edited extra.cnf is preserved, so strip settings that newer servers
	# refuse. MariaDB 10.6+ rejects the 'none' and 'innodb' checksums and
	# 11.0 deprecated innodb_file_per_table, which defaults to ON. MySQL 8.4
	# accepts both, so an operator's MySQL settings are left alone.
	local _my_cnf="$1"
	[ "$TOASTER_MARIADB" = "1" ] || return 0
	[ -f "$_my_cnf" ] || return 0

	# data/etc is owned by the mysql user, who could have made this a link
	if [ -L "$_my_cnf" ]; then
		tell_status "WARNING: not migrating symlink $_my_cnf"
		return 0
	fi

	# a host-side temp file, not one in the mysql-writable data/etc
	local _tmp
	_tmp=$(mktemp -t extra.cnf) || return 1

	# option files allow hyphens in names and quotes around values, so
	# normalize both in the comparison only, the kept lines are untouched
	awk '
		{
			l = tolower($0)
			if (l ~ /^[[:space:]]*[a-z0-9_-]+[[:space:]]*=/) {
				name = l
				sub(/[[:space:]]*=.*/, "", name)
				sub(/^[[:space:]]*/, "", name)
				gsub(/-/, "_", name)
				val = l
				sub(/^[^=]*=[[:space:]]*/, "", val)
				sub(/[[:space:]]*[#;].*$/, "", val)
				sub(/[[:space:]]+$/, "", val)
				gsub(/["\047]/, "", val)
				if (name == "innodb_checksum_algorithm" && val ~ /^(strict_)?(none|innodb)$/) next
				if (name == "innodb_file_per_table" && val ~ /^(1|on)$/) next
			}
			print
		}
	' "$_my_cnf" > "$_tmp"

	if ! cmp -s "$_my_cnf" "$_tmp"; then
		tell_status "removing obsolete innodb settings from $_my_cnf"
		# cat, not mv, so the file keeps its owner and mode
		cat "$_tmp" > "$_my_cnf"
	fi
	rm -f "$_tmp"
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

	local _dbdir
	_dbdir="$(get_jail_data mysql)/db"

	# innodb_file_per_table and innodb_checksum_algorithm are left at their
	# defaults (ON, and full_crc32 on MariaDB / crc32 on MySQL). CRC32 is
	# hardware accelerated and the non-strict default still reads pages
	# written while the checksum was 'none'.
	local _my_cnf="$STAGE_MNT/data/etc/extra.cnf"
	store_config "$_my_cnf" update <<EO_MY_CNF
[mysqld]
datadir                         = /data/db
innodb_data_home_dir            = /data/db
innodb_log_group_home_dir       = /data/db

innodb_doublewrite = off
innodb_flush_neighbors = 0
EO_MY_CNF

	migrate_extra_cnf "$_my_cnf"
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

upgrade_mariadb_tables()
{
	# MariaDB does not upgrade the system tables of an older datadir on
	# its own. mariadb-upgrade is a no-op when they are already current.
	# The staged jail runs on its own empty datadir (the live data is
	# unmounted from it), so this runs in the promoted jail, on the live data.
	[ "$TOASTER_MARIADB" = "1" ] || return 0

	tell_status "upgrading mariadb system tables"

	local _try=0
	until jexec mysql mariadb-admin --password="$TOASTER_MYSQL_PASS" ping >/dev/null 2>&1; do
		_try=$((_try + 1))
		if [ "$_try" -gt 30 ]; then
			echo "mariadb did not start in the mysql jail"
			exit 1
		fi
		sleep 2
	done

	jexec mysql mariadb-upgrade --password="$TOASTER_MYSQL_PASS" || exit 1
}

test_mysql()
{
	tell_status "testing mysql"
	stage_listening 3306 2
	echo 'SHOW DATABASES' | stage_exec "$(db_client)" --password="$TOASTER_MYSQL_PASS"
	echo "it worked"
}

migrate_mysql_dbs()
{
	if [ -f "$(get_jail_data mysql)/mysql.err" ]; then
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
	local _extra_cnf
	_extra_cnf="$(get_jail_data mysql)/etc/extra.cnf"
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

installed_db_server()
{
	# eg: mariadb1011-server-10.11.10 or mysql84-server-8.4.0
	# Read from the jail's root, so a stopped jail is inspected too.
	pkg -r "$ZFS_JAIL_MNT/mysql" info 2>/dev/null | cut -f1 -d' ' \
		| grep -E '^(mariadb|mysql)[0-9]+-server-' | head -n1
}

halt_mysql_upgrade()
{
	echo "
	HALT: $*
	"
	exit 1
}

check_mariadb_upgrade()
{
	# The staged jail starts the new server on a fresh datadir, and the
	# promoted jail then starts on the live one. Halt before an engine
	# switch, which needs a dump and restore, or a downgrade. Note a MariaDB
	# upgrade, which rewrites the data files and cannot be undone except by
	# a zfs rollback, so snapshot_mariadb_data can snapshot it at cutover.
	MARIADB_UPGRADE_FROM=""

	# no data, nothing to protect. Running or not, existing data is.
	[ -d "$(get_jail_data mysql)/db/mysql" ] || return 0

	local _pkg
	_pkg=$(installed_db_server)
	if [ -z "$_pkg" ]; then
		halt_mysql_upgrade "$(get_jail_data mysql)/db has data but the engine and
	version of the mysql jail could not be determined from its package database.
	Inspect it with: pkg -r $ZFS_JAIL_MNT/mysql info | grep -E 'mariadb|mysql'"
	fi

	local _running=mysql _wanted=mysql
	case "$_pkg" in mariadb*) _running=mariadb ;; esac
	[ "$TOASTER_MARIADB" = "1" ] && _wanted=mariadb

	if [ "$_running" != "$_wanted" ]; then
		halt_mysql_upgrade "the mysql jail runs $_pkg but this provision installs $_wanted
	(TOASTER_MARIADB=${TOASTER_MARIADB:-0}). MySQL and MariaDB cannot share a
	datadir. Dump the databases, switch, and restore them into the new jail,
	or set TOASTER_MARIADB to match the running server."
	fi

	[ "$_running" = "mariadb" ] || return 0

	local _ver
	_ver=$(echo "$_pkg" | cut -d- -f3)
	echo "$_ver" | grep -qE '^[0-9]+\.[0-9]+' \
		|| halt_mysql_upgrade "cannot parse the version of $_pkg"

	case "$(echo "$_ver" | awk -F. '{
		if ($1 < 12 || ($1 == 12 && $2 < 3)) print "older"
		else if ($1 == 12 && $2 == 3) print "current"
		else print "newer" }')" in
		current) return 0 ;;
		newer) halt_mysql_upgrade "the mysql jail runs $_pkg, newer than the 12.3 this
	provision installs. MariaDB cannot be downgraded in place. Update this
	provision, or restore the datadir from a backup taken before the upgrade." ;;
	esac

	MARIADB_UPGRADE_FROM="$_ver"
}

snapshot_mariadb_data()
{
	[ -n "$MARIADB_UPGRADE_FROM" ] || return 0

	# Snapshot at cutover, not at the start of provisioning: the old server
	# takes writes until now, and a clean stop leaves the datadir consistent.
	stop_jail mysql

	MARIADB_SNAPSHOT="$ZFS_DATA_VOL/mysql@mariadb-$MARIADB_UPGRADE_FROM-$(date +%Y%m%d%H%M%S)"
	tell_status "upgrading MariaDB $MARIADB_UPGRADE_FROM to 12.3, snapshotting data to $MARIADB_SNAPSHOT"
	zfs snapshot "$MARIADB_SNAPSHOT"

	trap '[ $? = 0 ] || mariadb_rollback_help' EXIT
}

mariadb_rollback_help()
{
	[ -n "$MARIADB_SNAPSHOT" ] || return 0
	echo "
	The upgrade failed. The data was snapshotted as $MARIADB_SNAPSHOT.

	Stop the staged and the mysql jails, and roll the data back:

		jail -r stage; service jail stop mysql
		zfs rollback $MARIADB_SNAPSHOT

	If the output above reached 'promoting jail mysql', the old jail is now
	$ZFS_JAIL_VOL/mysql.last: swap it back in as $ZFS_JAIL_VOL/mysql.
	Otherwise mysql is still the old jail. Then: service jail start mysql
	"
}

base_snapshot_exists || exit 1
migrate_mysql_dbs
check_mysql_native_passwords
check_mariadb_upgrade
create_staged_fs mysql
start_staged_jail mysql
install_db_server
configure_mysql
start_mysql
test_mysql
snapshot_mariadb_data
promote_staged_jail mysql
upgrade_mariadb_tables
