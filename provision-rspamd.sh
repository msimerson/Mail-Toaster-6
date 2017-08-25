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

configure_redis()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/redis"; then
		return
	fi

	tell_status "add Redis address, for default Lua modules backend"
	tee -a "$_etc/rspamd/rspamd.conf" <<  EO_REDIS
	redis {
		servers = "$(get_jail_ip redis):6379";
		db    = "5";
	}
EO_REDIS

}

configure_dcc() {
	if [ ! -d "$STAGE_MNT/usr/local/etc/rspamd/local.d" ]; then
		mkdir "$STAGE_MNT/usr/local/etc/rspamd/local.d"
	fi

	tee "$STAGE_MNT/usr/local/etc/rspamd/local.d/dcc.conf" <<EO_DCC
	host = $(get_jail_ip dcc);
	port = 1025;
EO_DCC
}

configure_dmarc()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/redis"; then
		return
	fi

	tell_status "add Redis address, for DMARC stats"
	tee -a "$_etc/rspamd/rspamd.conf" <<EO_DMARC
	dmarc {
		# Enables storing reporting information to redis
		reporting = true;
		actions = {
			quarantine = "add_header";
			reject = "reject";
		}
}
EO_DMARC

}

configure_stats()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/redis"; then
		return
	fi

	tell_status "add Redis address, for Bayes stats"
	tee "$_etc/rspamd/statistic.conf"  << EO_RSPAMD_STAT
classifier "bayes" {
	tokenizer {
		name = "osb";
	}

	backend = "redis";
	servers = "$(get_jail_ip redis):6379";
	min_tokens = 11;
	min_learns = 200;

	#write_servers = "localhost:6379"; # If needed another servers for learning
	#password = "xxx"; # Optional password
	database = "6"; # Optional database id

	cache {
		type = "redis";
	}

	statfile {
		symbol = "BAYES_SPAM";
		spam = true;
	}
	statfile {
		symbol = "BAYES_HAM";
		spam = false;
	}
	#per_user = true;
	autolearn = [-5, 5];
}
EO_RSPAMD_STAT

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
  	configure_redis
	configure_dmarc
	configure_stats
	configure_dcc

	# configure admin password?
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
