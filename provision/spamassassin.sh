#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/spamassassin \$path/data nullfs rw 0 0\";"

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
	stage_pkg_install dialog4ports p5-Encode-Detect p5-Test-NoWarnings || exit

	local _SA_OPTS="DCC DKIM RAZOR RELAY_COUNTRY SPF_QUERY GNUPG_NONE"
	if [ "$TOASTER_MYSQL" = "1" ]; then
		_SA_OPTS="MYSQL $_SA_OPTS"
	fi

	stage_make_conf mail_spamassassin "mail_spamassassin_SET=$_SA_OPTS
mail_spamassassin_UNSET=SSL PGSQL GNUPG GNUPG2"

	if [ ! -d "$STAGE_MNT/usr/ports/mail/spamassassin" ]; then
		echo "ports aren't mounted!" && exit 1
	fi

	#export BATCH=1  # if set, GPG key importing will fail
	if [ -x "$STAGE_MNT/usr/local/bin/perl5.26.2" ]; then
		stage_exec ln /usr/local/bin/perl5.26.2 /usr/local/bin/perl5.26.1
	fi
	stage_port_install mail/spamassassin || exit 1
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
	tell_status "install SpamAssassin optional dependencies"
	stage_pkg_install p5-Mail-SPF p5-Mail-DKIM p5-Net-Patricia p5-libwww p5-GeoIP2 p5-Net-CIDR-Lite p5-IO-Socket-INET6 || exit
	stage_pkg_install gnupg1 re2c libidn || exit
	install_spamassassin_razor

	if [ "$TOASTER_MYSQL" = "1" ]; then
		tell_status "installing mysql deps for spamassassin"
		stage_pkg_install mysql57-client p5-DBI p5-DBD-mysql
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

	local _should_install=""
	if [ ! -f "$_sa_etc/local.cf" ]; then
		_should_install="yes"
	fi

	if [ -z "$_should_install" ]; then
		if diff -q "$_sa_etc/local.cf" "$_sa_etc/local.cf.sample"; then
			echo "they're different"
		else
			_should_install="yes"
		fi
	fi

	if [ "$_should_install" = "yes" ]; then
		tell_status "updating local.cf"
		tee -a "$_sa_etc/local.cf" <<EO_LOCAL_CONF
report_safe 			0
trusted_networks $JAIL_NET_PREFIX.

skip_rbl_checks         0
use_razor2              1
use_dcc                 1
dcc_dccifd_path 		$(get_jail_ip dcc):1025

ok_languages            en
ok_locales              en

add_header all Status _YESNO_, score=_SCORE_ required=_REQD_ autolearn=_AUTOLEARN_
add_header all DCC _DCCB_: _DCCR_
add_header all Checker-Version SpamAssassin _VERSION_ (_SUBVERSION_) on _HOSTNAME_
add_header all Tests _TESTS_
EO_LOCAL_CONF
	fi

	tell_status "initialize sa-update"
	stage_exec sa-update

	#install_sought_rules
	install_sa_update
	configure_spamassassin_redis_bayes
	configure_geoip
	configure_spamassassin_mysql
}

configure_spamassassin_mysql()
{
	if [ "$TOASTER_MYSQL" != "1" ]; then return; fi
	if [ -f "$_sa_etc/sql.cf" ]; then return; fi

	tell_status "configuring MySQL for SpamAssassin (SASQL, Bayes, AWL)"
	local _my_pass; _my_pass=$(openssl rand -hex 18)

	tee -a "$_sa_etc/sql.cf" <<EO_MYSQL_CONF
	# Users scores is useful with the Squirrelmail SASQL plugin
    # user_scores_dsn                 DBI:mysql:spamassassin:$(get_jail_ip mysql)
    # user_scores_sql_username        spamassassin
    # user_scores_sql_password        $_my_pass

    # default query
    #SELECT preference, value FROM _TABLE_ WHERE username = _USERNAME_ OR username = '\@GLOBAL' ORDER BY username ASC
    # global, then domain level
    #SELECT preference, value FROM _TABLE_ WHERE username = _USERNAME_ OR username = '\@GLOBAL' OR username = '@~'||_DOMAIN_ ORDER BY username ASC
    # global overrides user prefs
    #SELECT preference, value FROM _TABLE_ WHERE username = _USERNAME_ OR username = '\@GLOBAL' ORDER BY username DESC
    # from the SA SQL README
    #user_scores_sql_custom_query     SELECT preference, value FROM _TABLE_ WHERE username = _USERNAME_ OR username = '\$GLOBAL' OR username = CONCAT('%',_DOMAIN_) ORDER BY username ASC

    # Bayes in Redis now, by default. Likely a bad choice to enable this.
    # bayes_store_module              Mail::SpamAssassin::BayesStore::SQL
    # bayes_sql_dsn                   DBI:mysql:spamassassin:$(get_jail_ip mysql)
    # bayes_sql_username              spamassassin
    # bayes_sql_password              $_my_pass
    # bayes_sql_override_username     someusername

    # Not commonly enabled.
    # auto_whitelist_factory       Mail::SpamAssassin::SQLBasedAddrList
    # user_awl_dsn                 DBI:mysql:spamassassin:$(get_jail_ip mysql)
    # user_awl_sql_username        spamassassin
    # user_awl_sql_password        $_my_pass
    # user_awl_sql_table           awl
EO_MYSQL_CONF

	echo 'CREATE DATABASE spamassassin;' | jexec mysql /usr/local/bin/mysql;
	for _import_file in awl_mysql bayes_mysql userpref_mysql;
	do
		local _f="$STAGE_MNT/usr/local/share/doc/spamassassin/sql/${_import_file}.sql"
		# shellcheck disable=SC2002
		cat "$_f" | jexec mysql /usr/local/bin/mysql spamassassin
	done

	for _jail in spamassassin stage;
	do
		for _ip in $(get_jail_ip "$_jail") $(get_jail_ip6 "$_jail");
		do
			echo "GRANT spamassassin.* to 'spamassassin'@'$_ip' IDENTIFIED BY '$_my_pass'" \
				| jexec mysql /usr/local/bin/mysql
		done
	done
}

start_spamassassin()
{
	tell_status "starting up spamd"
	stage_sysrc spamd_enable=YES

	SPAMD_ALLOW="-A 127.0.0.0/8"
	if ! echo "$JAIL_NET_PREFIX" | grep -q ^127; then
		SPAMD_ALLOW="$SPAMD_ALLOW -A $JAIL_NET_PREFIX.0$JAIL_NET_MASK"
	fi
	SPAMD_ALLOW="$SPAMD_ALLOW -A $JAIL_NET6::/64"

	sysrc -j stage spamd_flags="--siteconfigpath /data/etc -v -q -x -u spamd -H /var/spool/spamd $SPAMD_ALLOW --listen=* --min-spare=3 --max-spare=6 --max-conn-per-child=25 --allow-tell"
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
