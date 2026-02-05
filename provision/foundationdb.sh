#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

install_foundationdb()
{
	tell_status "install FoundationDB"

	stage_pkg_install bash ccache cmake msgpack-cxx toml11 llvm16 mono5.20 ninja python3 \
		libfmt liblz4 boost-libs libeio openssl swift510
	stage_exec git clone https://github.com/apple/foundationdb.git /data/src
	stage_exec mkdir /data/src/.build
	export SWIFTC=/usr/local/swift510/bin/swiftc
	stage_exec sh -c 'cd /data/src/.build && cmake -G Ninja -DUSE_CCACHE=on -DUSE_DTRACE=off ..'
}

configure_foundationdb()
{
	tell_status "configuring FoundationDB"
}

start_foundationdb()
{
	tell_status "starting up FoundationDB"
	#stage_sysrc
	#stage_exec
}

test_foundationdb()
{
	tell_status "testing FoundationDB"
	stage_test_running fdb
	#stage_listening
}

base_snapshot_exists || exit
create_staged_fs foundationdb
start_staged_jail foundationdb
install_foundationdb
configure_foundationdb
start_foundationdb
test_foundationdb
promote_staged_jail foundationdb
