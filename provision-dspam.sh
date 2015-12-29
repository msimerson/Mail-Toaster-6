#!/bin/sh

. mail-toaster.sh || exit

install_dspam()
{
	tell_status "installing dspam"
	stage_pkg_install dspam || exit
}

configure_dspam_mysql()
{
	tell_status "enabling dspam MySQL"

	local _dconf="$STAGE_MNT/usr/local/etc/dspam.conf"
	if [ ! -f "$_dconf" ]; then
		fatal_err "where is $_dconf?"
	fi

	local _last
	if ! mysql_db_exists dspam; then
		tell_status "creating dspam database"
		echo "CREATE DATABASE dspam;" | jexec mysql /usr/local/bin/mysql || exit
	fi

	local _curcfg="$ZFS_JAIL_MNT/dspam/usr/local/etc/dspam.conf"
	if [ -f "$_curcfg" ]; then
		_last=$(grep ^MySQLPass "$_curcfg" | awk '{ print $2 }' | head -n1)
	fi

	if [ -n "$_last" ] && [ "$_last" != "changeme" ]; then
		echo "preserving password"
		_dpass="$_last"
		return
	fi

	_dpass=$(openssl rand -hex 18)

	echo "GRANT ALL PRIVILEGES ON dspam.* to 'dspam'@'$(get_jail_ip dspam)' IDENTIFIED BY '${_dpass}';" \
		| jexec mysql /usr/local/bin/mysql || exit

	echo "GRANT ALL PRIVILEGES ON dspam.* to 'dspam'@'$(get_jail_ip stage)' IDENTIFIED BY '${_dpass}';" \
		| jexec mysql /usr/local/bin/mysql || exit
}

configure_dspam()
{
	tell_status "configuring dspam"
	local _etc="$STAGE_MNT/usr/local/etc"

	cp "$_etc/dspam.conf.sample" "$_etc/dspam.conf"
	sed -i .bak \
		-e 's/^#ServerPID/ServerPID/' \
		-e '/^StorageDriver/ s/libpgsql/libmysql/' \
		"$_etc/dspam.conf"

	configure_dspam_mysql

	tee -a "$_etc/dspam.conf" <<EO_DSPAM_MYSQL
MySQLServer             $(get_jail_ip mysql)
MySQLUser               dspam
MySQLPass               $_dpass
MySQLDb                 dspam
EO_DSPAM_MYSQL
}

start_dspam()
{
	tell_status "starting dspam"
	stage_sysrc dspam_enable=YES
	stage_exec service dspam start
}

test_dspam()
{
	tell_status "testing dspam"
	sleep 2
	stage_exec sockstat -l -4 | grep :24 || exit
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs dspam
start_staged_jail
install_dspam
configure_dspam
start_dspam
test_dspam
promote_staged_jail dspam
