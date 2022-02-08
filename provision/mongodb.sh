#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		allow.sysvipc;
		allow.mlock;
		mount += \"$ZFS_DATA_MNT/mongodb \$path/data nullfs rw 0 0\";"

install_mongodb()
{
	tell_status "installing mongodb"
	stage_pkg_install mongodb50 || exit

	#stage_pkg_install dialog4ports python scons-py37 boost-libs snappy pcre cyrus-sasl binutils gmp mongodb44 || exit 1
	#stage_port_install databases/mongodb50 || exit 1
}

check_max_wired() {
	local _fbsd_major; _fbsd_major=$(freebsd-version | cut -f1 -d'.')
	if [ "$_fbsd_major" -gt "12" ]; then
		return
	fi

	_count=$(sysctl -n vm.stats.vm.v_wire_count)
	_wired=$(sysctl -n vm.max_wired)

	if [ "$_count" -lt "$_wired" ]; then
		return
	fi

	echo "increase vm.max_wired > $_count"
	echo "sysctl vm.max_wired $((_count * 2))"
	sysctl vm.max_wired=$((_count * 2))
	tee -a /etc/sysctl.conf <<EO_SYSCTL_MONGO
vm.max_wired="$((_count * 2))"
EO_SYSCTL_MONGO
}

configure_mongodb()
{
	tell_status "configuring mongodb"

	mkdir -p "$STAGE_MNT/data/db" "$STAGE_MNT/data/log" "$STAGE_MNT/data/etc" \
		"$STAGE_MNT/usr/local/etc/newsyslog.conf.d" || exit
	stage_exec chown mongodb:mongodb /data/db /data/log /data/etc || exit

	if [ ! -f "$STAGE_MNT/data/etc/mongodb.conf" ]; then
		tell_status "installing /data/etc/mongodb.conf"
		cp "$STAGE_MNT/usr/local/etc/mongodb.conf.sample" "$STAGE_MNT/data/etc/mongodb.conf"
	fi

	check_max_wired

	echo '/data/log/mongod.log   mongodb:mongodb 644  7  *  @T00   JC   /var/run/mongod/mongod.pid' \
		> "$STAGE_MNT/usr/local/etc/newsyslog.conf.d/mongod"
}

start_mongodb()
{
	tell_status "starting mongodb"
	stage_sysrc mongod_enable=YES
	stage_sysrc mongod_config=/data/etc/mongodb.conf
	stage_sysrc mongod_dbpath=/data/db
	stage_sysrc mongod_flags="--logpath /data/log/mongod.log --logappend"

	stage_exec service mongod start
}

test_mongodb()
{
	echo "testing mongodb"
	sleep 1
	stage_listening 27017
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs mongodb
start_staged_jail mongodb
install_mongodb
configure_mongodb
start_mongodb
test_mongodb
promote_staged_jail mongodb
