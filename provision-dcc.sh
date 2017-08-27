#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_dcc_cleanup()
{
	tell_status "adding DCC cleanup periodic task"
	local _periodic="$STAGE_MNT/usr/local/etc/periodic"
	mkdir -p "$_periodic"
	cat <<EO_DCC > $_periodic/daily/501.dccd
#!/bin/sh
/usr/local/dcc/libexec/cron-dccd
/usr/bin/find /usr/local/dcc/log/ -not -newermt '1 days ago' -delete
EO_DCC
	chmod 755 "$_periodic/daily/501.dccd"
}

install_dcc()
{
	tell_status "install dcc"
	stage_pkg_install dcc-dccd || exit

	install_dcc_cleanup
}

configure_dcc()
{
	sed -i .bak \
		-e '/^DCCIFD_ENABLE=/ s/off/on/' \
		-e '/^DCCM_LOG_AT=/ s/5/NEVER/' \
		-e '/^DCCM_REJECT_AT/ s/=.*/=MANY/' \
		-e "/^DCCIFD_ARGS/ s/-SList-ID\"/-SList-ID -p*,1025,$JAIL_NET_PREFIX.0\/24\"/" \
		"$STAGE_MNT/usr/local/dcc/dcc_conf"
}

start_dcc()
{
	tell_status "starting up dcc-ifd"
	stage_sysrc dccifd_enable=YES
	stage_exec service dccifd start
}

test_dcc()
{
	tell_status "testing dcc"
	stage_listening 1025 3
}

base_snapshot_exists || exit
create_staged_fs dcc
start_staged_jail dcc
install_dcc
configure_dcc
start_dcc
test_dcc
promote_staged_jail dcc
