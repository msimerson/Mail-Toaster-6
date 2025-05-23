#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

RSPAMD_ETC="$STAGE_MNT/usr/local/etc/rspamd"

install_rspamd()
{
	tell_status "installing rspamd"
	stage_pkg_install rspamd

	if [ "$TOASTER_USE_TMPFS" = 1 ]; then
		tee -a $STAGE_MNT/etc/rc.local <<'EO_RC_LOCAL'
mkdir -p /var/run/rspamd
chown rspamd:rspamd /var/run/rspamd
EO_RC_LOCAL
		stage_exec service local start
	fi
}

configure_redis()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/redis"; then
		return
	fi

	tell_status "add Redis address, for default Lua modules backend"
	store_config "$RSPAMD_ETC/local.d/redis.conf" <<EO_REDIS
	servers = "$(get_jail_ip redis):6379";
	db    = "5";
EO_REDIS
}

configure_dcc() {
	tell_status "enabling DCC"
	store_config "$RSPAMD_ETC/local.d/dcc.conf" <<EO_DCC
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
	store_config "$RSPAMD_ETC/local.d/phishing.conf" <<EO_PHISH
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

	actions = {
		quarantine = "add_header";
		reject = "reject";
	}
	send_reports = true;
	# Enables storing reporting information to redis
	report_settings {
		enabled = true;
		org_name = "$TOASTER_ORG_NAME";
		domain = "$TOASTER_MAIL_DOMAIN";
		email = "$TOASTER_ADMIN_EMAIL";
		# uncomment this when the reports are working
		override_address = "$TOASTER_ADMIN_EMAIL";
		smtp = "$(get_jail_ip haraka)";
	}
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
	store_config "$RSPAMD_ETC/override.d/statistic.conf"  << EO_RSPAMD_STAT
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
	if [ "$RSPAMD_SYSLOG" = "1" ]; then
		tell_status "configuring syslog logging"
		store_config "$RSPAMD_ETC/local.d/logging.inc" <<EO_SYSLOG
type = "syslog";
facility = "LOG_MAIL";
level = "notice";
EO_SYSLOG
	else
		tell_status "configuring log rotation"
		stage_enable_newsyslog
	fi
}

configure_rbl()
{
	store_config "$RSPAMD_ETC/local.d/rbl.conf" <<EO_RBL
redirector_hosts_map = "/usr/local/etc/rspamd/redirectors.inc";
EO_RBL
}

configure_worker()
{
	store_config "$RSPAMD_ETC/local.d/worker-normal.inc" <<EO_WORKER
	bind_socket = "*:11333";
	count = 4;
EO_WORKER
}

configure_controller()
{
	_pass=$(jexec vpopmail /usr/local/vpopmail/bin/vuserinfo -C "postmaster@${TOASTER_MAIL_DOMAIN}")

	store_config "$RSPAMD_ETC/local.d/worker-controller.inc" <<EO_CONTROLLER
password = "$(jexec stage rspamadm pw -p "$_pass")";
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

	configure_logging
  	configure_redis
	configure_dmarc
	configure_stats
	configure_dcc
	configure_enable mxcheck
	configure_phishing
	configure_enable url_reputation
	configure_enable url_tags
	configure_rbl
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

base_snapshot_exists || exit 1
create_staged_fs rspamd
start_staged_jail rspamd
install_rspamd
configure_rspamd
start_rspamd
test_rspamd
promote_staged_jail rspamd
