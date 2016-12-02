#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/tinydns \$path/data nullfs rw 0 0\";"

install_tinydns()
{
	tell_status "installing tinydns"
	stage_pkg_install djbdns || exit
}

configure_tinydns()
{
	if [ ! -d "$STAGE_MNT/var/service" ]; then
		tell_status "creating daemontools service dir"
		mkdir -p "$STAGE_MNT/var/service" || exit
	fi

	tell_status "creating tinydns server"
	stage_exec tinydns-conf bind bin /var/service/tinydns "$(get_jail_ip stage)"

	tell_status "configuring tinydns data"
	if [ ! -d "$ZFS_DATA_MNT/tinydns/root" ]; then
		mv "$STAGE_MNT/var/service/tinydns/root" "$ZFS_DATA_MNT/tinydns/root"
		stage_exec sh -c 'cd /data/root && make'
	fi

	echo "/data/root" > "$STAGE_MNT/var/service/tinydns/env/ROOT" || exit
}

start_tinydns()
{
	tell_status "starting tinydns"
	stage_sysrc svscan_enable="YES"
	stage_exec service svscan start || exit
}

test_tinydns()
{
	tell_status "testing tinydns"
	stage_test_running tinydns

	stage_listening 53
	echo "it worked."

	tell_status "switching tinydns IP to deployment IP"
	$(get_jail_ip tinydns) > "$STAGE_MNT/var/service/tinydns/env/IP"
}

base_snapshot_exists || exit
create_staged_fs tinydns
start_staged_jail
install_tinydns
configure_tinydns
start_tinydns
test_tinydns
promote_staged_jail tinydns
