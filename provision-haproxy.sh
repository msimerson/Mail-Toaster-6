#!/bin/sh

. mail-toaster.sh || exit

install_haproxy()
{
	stage_pkg_install haproxy || exit
}

configure_haproxy()
{
	fetch -o $STAGE_MNT/usr/local/etc/haproxy.conf http://mail-toaster.org/install/mt6-haproxy.txt

	local _jail_ssl="$STAGE_MNT/etc/ssl"
	if [ -f "$_jail_ssl/private/server.key"]; then
		cat $_jail_ssl/private/server.key $_jail_ssl/certs/server.crt > $_jail_ssl/private/server.pem
		return
	fi

	local _base_ssl="$BASE_MNT/etc/ssl"
	cat $_base_ssl/private/server.key $_base_ssl/certs/server.crt > $_jail_ssl/private/server.pem || exit
}

start_haproxy()
{
	stage_sysrc haproxy_enable=YES
	stage_exec service haproxy start
}

test_haproxy()
{
	echo "testing haproxy..."
	stage_exec sockstat -l -4 | grep 443 || exit
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_staged_fs haproxy
stage_sysrc hostname=haproxy
start_staged_jail
install_haproxy
configure_haproxy
start_haproxy
test_haproxy
promote_staged_jail haproxy
