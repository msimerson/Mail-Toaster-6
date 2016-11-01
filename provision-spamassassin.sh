#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/spamassassin \$path/data nullfs rw 0 0\";"

install_dcc_cleanup()
{
	tell_status "adding DCC cleanup periodic task"
	local _periodic="$STAGE_MNT/usr/local/etc/periodic"
	mkdir -p "$_periodic"
	cat <<EO_DCC > $_periodic/daily/501.dccd
#!/bin/sh
/usr/local/dcc/libexec/cron-dccd
EO_DCC
	chmod 755 "$_periodic/daily/501.dccd"
}

install_sa_update()
{
	tell_status "adding sa-update periodic task"
	local _periodic="$STAGE_MNT/usr/local/etc/periodic"
	mkdir -p "$_periodic/daily"
	cat <<EO_SAUPD > $_periodic/daily/502.sa-update
#!/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin
/usr/local/bin/perl -T /usr/local/bin/sa-update \
	--gpgkey 6C6191E3 \
	--channel sought.rules.yerp.org \
	--channel updates.spamassassin.org
/usr/local/bin/perl -T /usr/local/bin/sa-compile
/usr/local/etc/rc.d/sa-spamd reload
EO_SAUPD
	chmod 755 "$_periodic/daily/502.sa-update"
}

install_sought_rules() {
	if [ -f "$ZFS_DATA_MNT/spamassassin/var/3.004001/sought_rules_yerp_org.cf" ]; then
		return
	fi

	tell_status "installing sought rules"
	fetch -o - http://yerp.org/rules/GPG.KEY | stage_exec sa-update --import - || exit
	stage_exec sa-update --gpgkey 6C6191E3 --channel sought.rules.yerp.org || exit
}

install_spamassassin_port()
{
	tell_status "install SpamAssassin from ports (w/opts)"
	stage_pkg_install dialog4ports p5-Encode-Detect || exit

	local _SA_OPTS="DCC DKIM RAZOR RELAY_COUNTRY SPF_QUERY UPDATE_AND_COMPILE GNUPG_NONE"
	if [ "$TOASTER_MYSQL" = "1" ]; then
		_SA_OPTS="MYSQL $_SA_OPTS"
	fi

	stage_make_conf mail_spamassassin "mail_spamassassin_SET=$_SA_OPTS
mail_spamassassin_UNSET=SSL PGSQL GNUPG GNUPG2"

	if [ ! -d "$STAGE_MNT/usr/ports/mail/spamassassin" ]; then
		echo "ports aren't mounted!" && exit
	fi

	#export BATCH=1  # if set, GPG key importing will fail
	stage_exec make -C /usr/ports/mail/spamassassin deinstall install clean || exit
}

install_spamassassin_nrpe()
{
	if [ -z "$TOASTER_NRPE" ]; then
		echo "TOASTER_NRPE unset, skipping nrpe plugin"
		return
	fi

	tell_status "installing nrpe spamd plugin"
	stage_pkg_install nagios-spamd-plugin
}

install_spamassassin_data_fs()
{
	for _d in $ZFS_DATA_MNT/spamassassin/etc $ZFS_DATA_MNT/spamassassin/var $STAGE_MNT/usr/local/etc/mail; do
		if [ ! -d "$_d" ]; then
			tell_status "creating $_d"
			mkdir "$_d" || exit
		fi
	done

	stage_exec ln -s /data/etc /usr/local/etc/mail/spamassassin
	stage_exec ln -s /data/var /var/db/spamassassin
}

install_spamassassin_razor()
{
	stage_pkg_install razor-agents || exit

	stage_exec razor-admin -home=/etc/razor -create -d
	stage_exec razor-admin -home=/etc/razor -register -d

	if [ ! -f "$STAGE_MNT/etc/razor/razor-agent.conf" ]; then
		echo "razor failed to register"
		exit
	fi

	sed -i .bak -e \
		'/^logfile/ s/= /= \/var\/log\//' \
		"$STAGE_MNT/etc/razor/razor-agent.conf"

	tell_status "setting up razor-agent log rotation"
	if [ ! -d "$STAGE_MNT/etc/newsyslog.conf.d" ]; then
		mkdir "$STAGE_MNT/etc/newsyslog.conf.d" || exit
	fi

	tee "$STAGE_MNT/etc/newsyslog.conf.d/razor-agent" <<EO_RAZOR
/var/log/razor-agent.log    600 5   1000 *  Z
EO_RAZOR
}

install_spamassassin()
{
	if grep -qs ^spamassassin /etc/jail.conf && ! grep -qs data/spamassassin /etc/jail.conf; then
		tell_status "exploding"
		echo "You MUST add this line to the spamassassin section in /etc/jail.conf to continue:"
		echo
		echo 'mount += "/data/spamassassin $path/data nullfs rw 0 0";'
		echo
		exit
	fi

	tell_status "install SpamAssassin optional dependencies"
	stage_pkg_install p5-Mail-SPF p5-Mail-DKIM p5-Net-Patricia p5-libwww p5-Geo-IP || exit
	stage_pkg_install gnupg1 re2c libidn dcc-dccd || exit
	install_spamassassin_razor

	if [ "$TOASTER_MYSQL" = "1" ]; then
		tell_status "installing mysql deps for spamassassin"
		stage_pkg_install mysql56-client p5-DBI p5-DBD-mysql
	fi

	install_spamassassin_data_fs
	install_spamassassin_nrpe
	install_spamassassin_port
}

configure_spamassassin_redis_bayes()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/redis"; then
		tell_status "redis jail missing, bayes not enabled"
		return
	fi

	tell_status "configuring redis backed bayes"
	echo "
use_bayes               1
use_bayes_rules         1
allow_user_rules	1
bayes_auto_learn        1
bayes_auto_learn_threshold_spam 7.0
bayes_auto_learn_threshold_nonspam -5.0
bayes_journal_max_size  1024000
bayes_expiry_max_db_size 1024000

bayes_store_module  Mail::SpamAssassin::BayesStore::Redis
bayes_sql_dsn       server=$(get_jail_ip redis):6379;database=2
bayes_token_ttl 21d
bayes_seen_ttl   8d
bayes_auto_expire 1

bayes_ignore_header X-Bogosity
bayes_ignore_header X-Spam-Flag
bayes_ignore_header X-Spam-Status
bayes_ignore_header X-Spam-DCC
bayes_ignore_header X-Spam-Checker-Version
bayes_ignore_header X-Spam-Tests
bayes_ignore_header X-Spam-Spammy
bayes_ignore_header X-Spam-Hammy
    " | tee "$_sa_etc/redis-bayes.cf"
}

configure_geoip()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL/geoip"; then
		tell_status "GeoIP jail not present, SKIPPING geoip plugin"
		return
	fi

	JAIL_CONF_EXTRA="$JAIL_CONF_EXTRA
		mount += \"$ZFS_DATA_MNT/geoip \$path/usr/local/share/GeoIP nullfs ro 0 0\";"
}

configure_spamassassin()
{
	_sa_etc="$ZFS_DATA_MNT/spamassassin/etc"

	if [ ! -f "$_sa_etc/local.pre" ]; then
		tell_status "installing local.pre"
		tee -a "$_sa_etc/local.pre" <<EO_LOCAL_PRE
loadplugin Mail::SpamAssassin::Plugin::TextCat
loadplugin Mail::SpamAssassin::Plugin::ASN
loadplugin Mail::SpamAssassin::Plugin::PDFInfo
EO_LOCAL_PRE
	fi

	if [ ! -f "$_sa_etc/local.cf" ]; then
		tell_status "installing local.cf"
		tee -a "$_sa_etc/local.cf" <<EO_LOCAL_CONF
report_safe 			0
trusted_networks $JAIL_NET_PREFIX.

skip_rbl_checks         0
use_razor2              1
use_dcc                 1

ok_languages            en
ok_locales              en

add_header all Status _YESNO_, score=_SCORE_ required=_REQD_ autolearn=_AUTOLEARN_
add_header all DCC _DCCB_: _DCCR_
add_header all Checker-Version SpamAssassin _VERSION_ (_SUBVERSION_) on _HOSTNAME_
add_header all Tests _TESTS_
EO_LOCAL_CONF
	fi

	install_sought_rules
	install_sa_update
	install_dcc_cleanup
	configure_spamassassin_redis_bayes
	configure_geoip

	# SASQL ?
	# create database spamassassin;
	# $GRANT spamassassin.* to 'spamassassin'@'$(get_jail_ip spamassassin)' IDENTIFIED BY '`$RANDPASS`';
}

start_spamassassin()
{
	tell_status "starting up spamd"
	stage_sysrc spamd_enable=YES
	sysrc -j stage spamd_flags="--siteconfigpath /data/etc -v -q -x -u spamd -H /var/spool/spamd -A 127.0.0.0/8 -A $JAIL_NET_PREFIX.0$JAIL_NET_MASK --listen=0.0.0.0 --min-spare=3 --max-spare=6 --max-conn-per-child=25"
	stage_exec service sa-spamd start
}

test_spamassassin()
{
	tell_status "testing spamassassin"
	stage_test_running perl
	stage_listening 783
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs spamassassin
start_staged_jail spamassassin
install_spamassassin
configure_spamassassin
start_spamassassin
test_spamassassin
promote_staged_jail spamassassin
