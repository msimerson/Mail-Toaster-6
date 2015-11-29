#!/bin/sh

. mail-toaster.sh || exit

install_rspamd()
{
	pkg -j $SAFE_NAME install -y rspamd || exit
}

configure_rspamd()
{
	local _local_etc="$STAGE_MNT/usr/local/etc"

	mkdir -p $local_etc/newsyslog.conf.d/
	echo '/var/log/rspamd/rspamd.log   nobody:nobody     644   7    *     @T00     JC   /var/run/rspamd/rspamd.pid  30' \
  		> $local_etc/newsyslog.conf.d/rspamd
}

start_rspamd()
{
	sysrc -f $STAGE_MNT/etc/rc.conf rspamd_enable=YES
	jexec $SAFE_NAME service rspamd start
}

test_rspamd()
{
	echo "testing rspamd..."
	jexec $SAFE_NAME sockstat -l -4 | grep 11334 || exit
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_staged_fs
sysrc -f $STAGE_MNT/etc/rc.conf hostname=rspamd
start_staged_jail
install_rspamd
configure_rspamd
start_rspamd
test_rspamd
promote_staged_jail rspamd
