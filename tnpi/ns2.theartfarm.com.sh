#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

mt6-include user

install_knot()
{
	tell_status "installing Knot DNS 3"
	stage_pkg_install knot3 rsync

	install_nrpe
}

install_nrpe()
{
	if [ -z "$TOASTER_NRPE" ]; then
		echo "TOASTER_NRPE unset, skipping nrpe plugin"
		return
	fi

	tell_status "installing nrpe plugin"
	stage_pkg_install nrpe
	stage_sysrc nrpe_enable=YES
	stage_sysrc nrpe_configfile="/data/etc/nrpe.cfg"
}

configure_knot()
{
	for _d in etc home home/knot; do
		if [ ! -d "$STAGE_MNT/data/$_d" ]; then
			mkdir "$STAGE_MNT/data/$_d"
		fi
	done

	chown -R 553:553 "$STAGE_MNT/data/home/knot"

	local _cfg="$STAGE_MNT/usr/local/etc/knot/knot.conf"
	if [ ! -f "$_cfg" ] && [ -f "$_cfg.sample" ]; then
		tell_status "installing default $_cfg"
		cp "$_cfg.sample" "$_cfg"
	fi

	if grep -qs '^#[[:space:]]*listen' "$_cfg"; then
		sed -i '' \
			-e '/^#[[:space:]]*listen:/ s/^#//' \
			"$_cfg"
	fi

	stage_sysrc sshd_enable=YES
	stage_sysrc sshd_flags="-o KbdInteractiveAuthentication=no -o ListenAddress=172.16.16.2"
	stage_sysrc knot_enable=YES

	preserve_passdb knot
	stage_exec pw user mod knot -d /data/home/knot -s /bin/sh
}

start_knot()
{
	tell_status "starting knot daemon"
	stage_exec service knot start
}

test_knot()
{
	tell_status "testing knot"
	stage_test_running knot

	stage_listening 53 4 2
	echo "it worked."

	tell_status "testing UDP DNS query"
	drill -Q   www.example.com @"$(get_jail_ip stage)"

	tell_status "testing TCP DNS query"
	drill -Q -t www.example.com @"$(get_jail_ip stage)"

	if [ -f "$STAGE_MNT/data/etc/knot.conf" ]; then
		tell_status "switching knot config to /data/etc/knot.conf"
		stage_sysrc knot_config=/data/etc/knot.conf

		#stage_exec service knot restart
		#drill    ns2.theartfarm.com @"$(get_jail_ip stage)"
		#drill -t ns2.theartfarm.com @"$(get_jail_ip stage)"
	fi
}

base_snapshot_exists
create_staged_fs ns2.theartfarm.com
start_staged_jail ns2.theartfarm.com
install_knot
configure_knot
start_knot
test_knot
promote_staged_jail ns2.theartfarm.com
