#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

install_dcc_cleanup()
{
	if [ ! -x "$STAGE_MNT/usr/local/libexec/cron-dccd" ]; then
		echo "ERROR: could not find cron-dccd!"
		exit 2
	fi

	if [ ! -d "$STAGE_MNT/var/db/dcc/log" ]; then
		echo "ERROR: could not find dcc log dir!"
		exit 2
	fi

	store_exec "$STAGE_MNT/usr/local/etc/periodic/daily/501.dccd-cleanup" <<EO_DCC
#!/bin/sh
/usr/local/libexec/cron-dccd
/usr/bin/find /var/db/dcc/log/ -not -newermt '1 days ago' -delete
EO_DCC
}

install_dcc_port_options()
{
	local SET=DCCIFD
	local UNSET="DCCGREY DCCD DCCM PORTS_MILTER"

	get_public_ip ipv6
	if [ -z "$PUBLIC_IP6" ]; then
		UNSET="$UNSET IPv6"
	else
		SET="$SET IPV6"
	fi

	stage_make_conf dcc-dccd_SET "mail_dcc-dccd_SET=$SET"
	stage_make_conf dcc-dccd_UNSET "mail_dcc-dccd_UNSET=$UNSET"
	stage_make_conf LICENSES_ACCEPTED 'LICENSES_ACCEPTED=DCC'
}

install_dcc()
{
	install_dcc_port_options

	tell_status "install dcc"
	stage_port_install mail/dcc-dccd

	install_dcc_cleanup
}

configure_dcc()
{
	sed -i.bak \
		-e '/^DCCIFD_ENABLE=/ s/off/on/' \
		-e '/^DCCM_LOG_AT=/ s/5/NEVER/' \
		-e '/^DCCM_REJECT_AT/ s/=.*/=MANY/' \
		-e "/^DCCIFD_ARGS/ s/-SList-ID\"/-SList-ID -p*,1025,$JAIL_NET_PREFIX.0\/24\"/" \
		"$STAGE_MNT/var/db/dcc/dcc_conf"

	_pf_etc="$ZFS_DATA_MNT/dcc/etc/pf.conf.d"

	get_public_ip
	get_public_ip ipv6

	store_config "$_pf_etc/dcc.table" <<EO_DCC_TABLE
$PUBLIC_IP4
$PUBLIC_IP6
$(get_jail_ip dcc)
$(get_jail_ip6 dcc)
EO_DCC_TABLE

	store_config "$_pf_etc/filter.conf" <<EO_PF_FILTER
pass in quick proto udp from any port 6277 to <dcc>
EO_PF_FILTER

	store_config "$_pf_etc/rdr.conf" <<EO_PF_RDR
rdr inet  proto tcp from any to <ext_ip4> port 6277 -> $(get_jail_ip  dcc)
rdr inet6 proto tcp from any to <ext_ip6> port 6277 -> $(get_jail_ip6 dcc)
EO_PF_RDR

}

start_dcc()
{
	tell_status "starting up dcc-ifd"
	stage_sysrc dccifd_enable=YES
	stage_exec service dccifd start
	stage_exec cdcc IPv6=off info
}

test_dcc()
{
	tell_status "testing dcc"
	stage_listening 1025 3
}

base_snapshot_exists || exit 1
create_staged_fs dcc
start_staged_jail dcc
install_dcc
configure_dcc
start_dcc
test_dcc
promote_staged_jail dcc
