#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

RSPAMD_ETC="$STAGE_MNT/usr/local/etc/rspamd"

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
	tee "$RSPAMD_ETC/local.d/redis.conf" <<EO_REDIS
	servers = "$(get_jail_ip redis):6379";
	db    = "5";
EO_REDIS
}

configure_dcc() {
	tell_status "enabling DCC"
	tee "$RSPAMD_ETC/local.d/dcc.conf" <<EO_DCC
	enabled = true;
	servers = $(get_jail_ip dcc):1025;
	timeout = 5s;
EO_DCC
}

configure_phishing()
{
	local _physmem; _physmem=$(sysctl -n hw.physmem)
	if [ "$_physmem" -le "4294967296" ]; then
		tell_status "skipping phish, too little RAM"
		return
	fi

	tell_status "enabling phish detection"
	tee "$RSPAMD_ETC/local.d/phishing.conf" <<EO_PHISH
	openphish_enabled = true;
	phishtank_enabled = true;
EO_PHISH
}

configure_dmarc()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/redis"; then
		return
	fi

	tell_status "add Redis address, for DMARC stats"
	tee -a "$RSPAMD_ETC/local.d/dmarc.conf" <<EO_DMARC

	# Enables storing reporting information to redis
	reporting = true;
	actions = {
		quarantine = "add_header";
		reject = "reject";
	}
	send_reports = true;
	report_settings {
		org_name = "$TOASTER_ORG_NAME";
		domain = "$TOASTER_MAIL_DOMAIN";
		email = "$TOASTER_ADMIN_EMAIL";
		# uncomment this when the reports are working
		override_address = "$TOASTER_ADMIN_EMAIL";
	}
	smtp = "$(get_jail_ip haraka)";
EO_DMARC
}

configure_enable()
{
	tell_status "enabling $1"
	echo 'enabled = true;' > "$RSPAMD_ETC/local.d/$1.conf"
}

configure_stats()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/redis"; then
		return
	fi

	tell_status "add Redis address, for Bayes stats"
	tee "$RSPAMD_ETC/override.d/statistic.conf"  << EO_RSPAMD_STAT
	classifier "bayes" {

		tokenizer {
			name = "osb";
		}

		backend = "redis";
		servers = "$(get_jail_ip redis):6379";
		database = "6";

		min_tokens = 11;
		min_learns = 200;

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
	tee "$RSPAMD_ETC/local.d/logging.inc" <<EO_SYSLOG
type = "syslog";
facility = "LOG_MAIL";
level = "notice";
EO_SYSLOG
}

configure_surbl()
{
	tee "$RSPAMD_ETC/local.d/surbl.conf" <<EO_SURBL
redirector_hosts_map = "/usr/local/etc/rspamd/redirectors.inc";
EO_SURBL
}

configure_worker()
{
	tee "$RSPAMD_ETC/local.d/worker-normal.inc" <<EO_WORKER
	bind_socket = "*v6:11333";
	count = 4;
EO_WORKER
}

configure_controller()
{
	tee "$RSPAMD_ETC/local.d/worker-controller.inc" <<EO_CONTROLLER
password = "$(openssl rand -base64 15)";
secure_ip = $(get_jail_ip dovecot);
secure_ip = $(get_jail_ip6 dovecot);
EO_CONTROLLER
}

configure_rspamd()
{
	tell_status "configuring rspamd"

	for _d in "local.d" "override.d"; do
		if [ ! -d "$RSPAMD_ETC/${_d}" ]; then
			mkdir "$RSPAMD_ETC/${_d}"
		fi
	done

	#configure_logging
  	configure_redis
	configure_dmarc
	configure_stats
	configure_dcc
	configure_enable mxcheck
	configure_phishing
	configure_enable url_reputation
	configure_enable url_tags
	configure_surbl
	configure_worker
	configure_controller

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
	stage_exec /usr/local/bin/rspamadm configtest
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
