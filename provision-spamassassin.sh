#!/bin/sh

. mail-toaster.sh || exit

install_geoip()
{
	tell_status "install GeoIP & dbs"
	stage_pkg_install p5-Geo-IP
	local _geodb="http://geolite.maxmind.com/download/geoip/database"
	local _lgeo="$STAGE_MNT/usr/local/share/GeoIP"
	fetch -o $_lgeo $_geodb/GeoLiteCountry/GeoIP.dat.gz
	fetch -o $_lgeo $_geodb/GeoIPv6.dat.gz
	gunzip $_lgeo/*.gz

	tell_status "install GeoIP updater"
	mkdir -p $STAGE_MNT/usr/local/share/GeoIP/download
	stage_pkg_install p5-PerlIO-gzip
	fetch -o $STAGE_MNT/usr/local/etc/periodic/weekly/geolite-mirror-simple.pl \
		https://raw.githubusercontent.com/maxmind/geoip-api-perl/master/example/geolite-mirror-simple.pl
	chmod 755 $STAGE_MNT/usr/local/etc/periodic/weekly/geolite-mirror-simple.pl
}

install_dcc_cleanup()
{
	tell_status "adding DCC cleanup periodic task"
	mkdir -p $STAGE_MNT/usr/local/etc/periodic/daily
	cat <<EO_DCC > $STAGE_MNT/usr/local/etc/periodic/daily/501.dccd
#!/bin/sh
/usr/local/dcc/libexec/cron-dccd
EO_DCC
	chmod 755 $STAGE_MNT/usr/local/etc/periodic/daily/501.dccd
}

install_sa_update()
{
	tell_status "adding sa-update periodic task"
	mkdir -p $STAGE_MNT/usr/local/etc/periodic/daily
	cat <<EO_SAUPD > $STAGE_MNT/usr/local/etc/periodic/daily/502.sa-update
#!/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin
/usr/local/bin/perl -T /usr/local/bin/sa-update --gpgkey 6C6191E3 --channel sought.rules.yerp.org --channel updates.spamassassin.org
/usr/local/bin/perl -T /usr/local/bin/sa-compile
/usr/local/etc/rc.d/sa-spamd reload
EO_SAUPD
	chmod 755 $STAGE_MNT/usr/local/etc/periodic/daily/502.sa-update
}

install_sought_rules() {
	tell_status "installing sought rules"
	fetch -o - http://yerp.org/rules/GPG.KEY | jexec $SAFE_NAME sa-update --import -
	stage_exec sa-update --gpgkey 6C6191E3 --channel sought.rules.yerp.org
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
mail_spamassassin_UNSET=SSL PGSQL"

	if [ ! "-d $STAGE_MNT/usr/ports/mail/spamassassin" ]; then
		echo "ports aren't mounted!" && exit
	fi

	stage_exec make -C /usr/ports/mail/spamassassin deinstall install clean
}

install_spamassassin()
{
	tell_status "install SpamAssassin optional dependencies"
	stage_pkg_install p5-Mail-SPF p5-Mail-DKIM p5-Net-Patricia p5-libwww || exit
	stage_pkg_install gnupg1 re2c libidn dcc-dccd razor-agents || exit

	if [ "$TOASTER_MYSQL" = "1" ]; then
		stage_pkg_install mysql56-client p5-DBI p5-DBD-mysql
	fi

	install_geoip
	install_spamassassin_port
}

configure_spamassassin_redis_bayes()
{
	# TODO: enable in local.cf

	echo "
bayes_store_module  Mail::SpamAssassin::BayesStore::Redis
bayes_sql_dsn       server=$JAIL_NET_PREFIX.15:6379;database=2
bayes_token_ttl 21d
bayes_seen_ttl   8d
bayes_auto_expire 1
    " | tee $STAGE_MNT/usr/local/etc/mail/spamassassin/redis-bayes.cf
}

configure_spamassassin()
{
	local _local_etc="$STAGE_MNT/usr/local/etc"

	sed -i .bak -e \
		's/#loadplugin Mail::SpamAssassin::Plugin::TextCat/loadplugin Mail::SpamAssassin::Plugin::TextCat/' \
		$STAGE_MNT/usr/local/etc/mail/spamassassin/v310.pre

	install_sought_rules
	install_sa_update
	install_dcc_cleanup
	#configure_spamassassin_redis_bayes

	# SASQL ?
	# create database spamassassin;
	# $GRANT spamassassin.* to 'spamassassin'@'$JAIL_NET_PREFIX.6' IDENTIFIED BY '`$RANDPASS`';
}

start_spamassassin()
{
	tell_status "starting up spamd"
	stage_sysrc spamd_enable=YES
	sysrc -j $SAFE_NAME spamd_flags="-v -q -x -u spamd -H /var/spool/spamd -A $JAIL_NET_PREFIX.0/24"
	stage_exec service sa-spamd start
}

test_spamassassin()
{
	tell_status "testing spamassassin"
	stage_exec sockstat -l -4 | grep 783 || exit
	echo "it worked"
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_staged_fs spamassassin
stage_sysrc hostname=spamassassin
start_staged_jail
install_spamassassin
configure_spamassassin
start_spamassassin
test_spamassassin
promote_staged_jail spamassassin
