#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_rspamd()
{
	tell_status "installing rspamd"
	stage_pkg_install rspamd || exit
}

configure_dmarc()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/redis"; then
		return
	fi

	tell_status "add Redis address, for DMARC stats"
	echo "dmarc {
	servers = \"$(get_jail_ip redis):6379\";
}"  | tee -a "$_etc/rspamd/rspamd.conf"
}

configure_logging()
{
	tell_status "configuring syslog logging"
	sed -i .bak \
		-e 's/type = "file"/type = "syslog"/' \
		-e 's/filename = ".*/facility = "LOG_MAIL";/' \
		"$_etc/rspamd/rspamd.conf"

#	mkdir -p "$_etc/newsyslog.conf.d/"
#	echo '/var/log/rspamd/rspamd.log   nobody:nobody   644  7  *  @T00  JC  /var/run/rspamd/rspamd.pid  30' \
#  		> "$_etc/newsyslog.conf.d/rspamd"

}

configure_rspamd()
{
	tell_status "configuring rspamd"
	local _etc="$STAGE_MNT/usr/local/etc"

  	configure_logging
  	configure_dmarc
	# configure admin password?

	sed -i .bak -e '/^filters/ s/spf/spf,dmarc/' "$_etc/rspamd/options.inc"
	echo "done"
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
	stage_listening 11334
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs rspamd
start_staged_jail rspamd
install_rspamd
configure_rspamd
start_rspamd
test_rspamd
promote_staged_jail rspamd
