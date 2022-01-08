#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include mysql

install_dspam()
{
	assure_jail mysql

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
	mysql_create_db dspam || exit

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

	for _jail in dspam stage; do
		for _ip in $(get_jail_ip "$_jail") $(get_jail_ip6 "$_jail");
		do
			echo "GRANT ALL PRIVILEGES ON dspam.* to 'dspam'@'${_ip}' IDENTIFIED BY '${_dpass}';" \
				| mysql_query || exit
		done
	done
}

configure_dspam()
{
	tell_status "configuring dspam"
	local _etc="$STAGE_MNT/usr/local/etc"

	cp "$_etc/dspam.conf.sample" "$_etc/dspam.conf"
	sed -i.bak \
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
	stage_listening 2424
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs dspam
start_staged_jail dspam
install_dspam
configure_dspam
start_dspam
test_dspam
promote_staged_jail dspam
