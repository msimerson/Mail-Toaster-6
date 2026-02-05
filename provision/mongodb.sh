#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA="allow.sysvipc=1 allow.mlock=1"
export JAIL_CONF_EXTRA="
		allow.raw_sockets;
		allow.sysvipc;
		allow.mlock;"
export JAIL_FSTAB=""

install_mongodb()
{
	if [ "$(uname -p)" = "amd64" ]; then
		if ! grep Features /var/run/dmesg.boot | grep -q AVX; then
			tell_status "WARNING: your CPU isn't supported by MongoDB 5+, installing 4.4"
			stage_pkg_install mongodb44 mongodb-tools
			return
		fi
	fi

	tell_status "installing mongodb"
	stage_pkg_install mongodb80
}

install_mongodb_port()
{
	stage_pkg_install python scons-py37 boost-libs snappy pcre cyrus-sasl binutils gmp
	stage_port_install databases/mongodb80
}

check_max_wired() {
	local _fbsd_major; _fbsd_major=$(freebsd-version | cut -f1 -d'.')
	if [ "$_fbsd_major" -gt "12" ]; then return; fi

	_count=$(sysctl -n vm.stats.vm.v_wire_count)
	_wired=$(sysctl -n vm.max_wired)

	if [ "$_count" -lt "$_wired" ]; then return; fi

	echo "increase vm.max_wired > $_count"
	echo "sysctl vm.max_wired $((_count * 2))"
	sysctl vm.max_wired=$((_count * 2))
	tee -a /etc/sysctl.conf <<EO_SYSCTL_MONGO
vm.max_wired="$((_count * 2))"
EO_SYSCTL_MONGO
}

configure_mongod_syslog()
{
	sed -i '' \
		-e '/destination:/ s/file/syslog/' \
		"$STAGE_MNT/data/etc/mongodb.conf"
}

configure_mongod_logging()
{
	stage_enable_newsyslog

	echo '/data/log/mongod.log   mongodb:mongodb 644  7  *  @T00   JC   /var/run/mongod/mongod.pid' \
		> "$STAGE_MNT/usr/local/etc/newsyslog.conf.d/mongod.conf"
}

configure_mongodb()
{
	tell_status "configuring mongodb"

	_data="$STAGE_MNT/data"
	for _d in "$_data/db" "$_data/etc" "$_data/log" "$STAGE_MNT/var/run/mongod"; do
		if [ ! -d "$_d" ]; then
			mkdir -p "$_d"
			chown 922:922 "$_d"
		fi
	done

	if [ ! -f "$STAGE_MNT/data/etc/mongodb.conf" ]; then
		tell_status "installing /data/etc/mongodb.conf"
		sed -e 's|/var/log/mongodb|/data/log|' \
			"$STAGE_MNT/usr/local/etc/mongodb.conf.sample" \
			| sed -e '/logAppend: true$/a\
  #destination: syslog\
  quiet: false\
  verbosity: 0' \
			| sed -e '/dbPath:/ s|/var/lib/mongo|/data/db|' \
			| sed -e '/processManagement:$/a\
  fork: true\
  pidFilePath: /var/run/mongod/mongod.pid' \
			| sed -e '/port: 27017$/a\
  ipv6: true' \
			| sed -e '/bindIp:/ s/127.*/0.0.0.0,::/' \
			> "$STAGE_MNT/data/etc/mongodb.conf"
	fi

	check_max_wired
	configure_mongod_logging
}

start_mongodb()
{
	tell_status "starting mongodb"
	stage_sysrc mongod_enable=YES
	stage_exec service mongod start
}

test_mongodb()
{
	echo "testing mongodb"
	sleep 1
	stage_listening 27017 3
	echo "it worked"
}

post_install_config()
{
	stage_sysrc mongod_config=/data/etc/mongodb.conf
	stage_sysrc mongod_dbpath=/data/db
	stage_sysrc mongod_flags="--logpath /data/log/mongod.log --logappend"
}

base_snapshot_exists
create_staged_fs mongodb
start_staged_jail mongodb
install_mongodb
configure_mongodb
start_mongodb
test_mongodb
post_install_config
promote_staged_jail mongodb
