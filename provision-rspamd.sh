#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

install_rspamd()
{
	tell_status "installing rspamd"
	stage_pkg_install rspamd || exit
}

configure_rspamd()
{
	tell_status "configuring rspamd"
	local _local_etc="$STAGE_MNT/usr/local/etc"

	mkdir -p "$_local_etc/newsyslog.conf.d/"
	echo '/var/log/rspamd/rspamd.log   nobody:nobody   644  7  *  @T00  JC  /var/run/rspamd/rspamd.pid  30' \
  		> "$_local_etc/newsyslog.conf.d/rspamd"

	# add Redis address, for DMARC stats
	echo "dmarc {
	servers = \"$(get_jail_ip redis):6379\";
}"  >> "$_local_etc/rspamd/rspamd.conf"

	# configure admin password?

	sed -i -e '/^filters/ s/spf/spf,dmarc/' "$_local_etc/rspamd/options.inc"
}

start_rspamd()
{
	tell_status "starting rspamd"
	stage_sysrc rspamd_enable=YES
	stage_exec service rspamd start
}

test_rspamd()
{
	tell_status "testing rspamd"
	stage_exec sockstat -l -4 | grep 11334 || exit
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs rspamd
start_staged_jail
install_rspamd
configure_rspamd
start_rspamd
test_rspamd
promote_staged_jail rspamd
