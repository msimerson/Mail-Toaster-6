#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include user

install_knot()
{
	tell_status "installing Knot DNS 3"
	stage_pkg_install knot3 rsync dialog4ports || exit

	install_nrpe
	install_sentry
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
			mkdir "$STAGE_MNT/data/$_d" || exit
		fi
	done

	chown -R 553:553 "$STAGE_MNT/data/home/knot"

	local _cfg="$STAGE_MNT/data/etc/knot.conf"
	if [ -f $_cfg ]; then
		tell_status "preserving knot.conf"
	else
		tell_status "installing default knot.conf"
		cp "$STAGE_MNT/usr/local/etc/knot/knot.conf.sample" "$_cfg" || exit 1
		sed -i '' \
			-e '/^#[[:space:]]*listen:/ s/^#//' \
			"$_cfg"
	fi

	stage_sysrc sshd_enable=YES
	stage_sysrc knot_enable=YES
	stage_sysrc knot_config=/data/etc/knot.conf
	stage_exec pw user mod knot -d /data/home/knot -s /bin/sh

	preserve_passdb knot
}

start_knot()
{
	tell_status "starting knot daemon"
	stage_exec service knot start || exit 1
}

test_knot()
{
	tell_status "testing knot"
	stage_test_running knot

	stage_listening 53 4 2
	echo "it worked."

	tell_status "testing UDP DNS query"
	drill -Q   www.example.com @"$(get_jail_ip stage)" || exit 1

	tell_status "testing TCP DNS query"
	drill -Q -t www.example.com @"$(get_jail_ip stage)" || exit 1
}

base_snapshot_exists || exit
create_staged_fs knot
start_staged_jail knot
install_knot
configure_knot
start_knot
test_knot
promote_staged_jail knot
