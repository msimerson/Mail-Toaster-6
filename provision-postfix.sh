#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_postfix()
{
	tell_status "installing postfix"
	stage_pkg_install postfix opendkim dialog4ports || exit
}

configure_postfix()
{
	stage_sysrc postfix_enable=YES
	stage_sysrc sshd_enable=YES
	stage_sysrc milteropendkim_enable=YES
	stage_sysrc milteropendkim_cfgfile=/data/etc/opendkim.conf

	if [ -n "$TOASTER_NRPE" ]; then
		stage_sysrc nrpe3_enable=YES
		stage_sysrc nrpe3_configfile="/data/etc/nrpe.cfg"
	fi

	for _f in master main
	do
		if [ -f "$ZFS_DATA_MNT/postfix/etc/$_f.cf" ]; then
			cp "$ZFS_DATA_MNT/postfix/etc/$_f.cf" "$STAGE_MNT/usr/local/etc/postfix/"
		fi
	done
}

start_postfix()
{
	tell_status "starting postfix"
	stage_exec service milter-opendkim start
	stage_exec service postfix start || exit
}

test_postfix()
{
	tell_status "testing postfix"
	stage_test_running postfix

	stage_listening 25
	echo "it worked."
}

base_snapshot_exists || exit
create_staged_fs postfix
start_staged_jail postfix
install_postfix
configure_postfix
start_postfix
test_postfix
promote_staged_jail postfix
