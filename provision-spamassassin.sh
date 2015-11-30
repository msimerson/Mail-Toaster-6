#!/bin/sh

. mail-toaster.sh || exit

install_geoip()
{
	stage_pkg_install p5-Geo-IP
	echo "install GeoIP data"
	local _geodb="http://geolite.maxmind.com/download/geoip/database"
	local _lgeo="$STAGE_MNT/usr/local/share/GeoIP"
	fetch -o $_lgeo $_geodb/GeoLiteCountry/GeoIP.dat.gz
	fetch -o $_lgeo $_geodb/GeoIPv6.dat.gz
	gunzip $_lgeo/*.gz

	echo "install GeoIP updater"
	mkdir -p $STAGE_MNT/usr/local/share/GeoIP/download
	stage_pkg_install p5-PerlIO-gzip
	fetch -o $STAGE_MNT/usr/local/etc/periodic/weekly/geolite-mirror-simple.pl \
		https://raw.githubusercontent.com/maxmind/geoip-api-perl/master/example/geolite-mirror-simple.pl
	chmod 755 $STAGE_MNT/usr/local/etc/periodic/weekly/geolite-mirror-simple.pl
}

install_dcc_cleanup()
{
	echo "adding DCC cleanup periodic task"
	mkdir -p $STAGE_MNT/usr/local/etc/periodic/daily
	cat <<EO_DCC > $STAGE_MNT/usr/local/etc/periodic/daily/501.dccd
#!/bin/sh
/usr/local/dcc/libexec/cron-dccd
EO_DCC
	chmod 755 $STAGE_MNT/usr/local/etc/periodic/daily/501.dccd
}

install_sa_update()
{
	echo "adding sa-update periodic task"
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
	echo "installing sought rules"
	fetch -o - http://yerp.org/rules/GPG.KEY | stage_exec sa-update --import -
	stage_exec sa-update --gpgkey 6C6191E3 --channel sought.rules.yerp.org
}

install_spamassassin()
{
	stage_pkg_install p5-Mail-SPF p5-Mail-DKIM p5-Net-Patricia p5-libwww
	stage_pkg_install gnupg1 re2c libidn dcc-dccd razor-agents
	stage_pkg_install mysql56-client p5-DBI

	install_geoip

	stage_pkg_install spamassassin dialog4ports || exit

	grep spamassassin /etc/make.conf || cat <<EO_SPAMA >> $STAGE_MNT/etc/make.conf
mail_spamassassin_SET=MYSQL DCC DKIM RAZOR RELAY_COUNTRY SPF_QUERY UPDATE_AND_COMPILE GNUPG_NONE
mail_spamassassin_UNSET=SSL PGSQL
EO_SPAMA
	make -C /usr/ports/mail/spamassassin deinstall install clean
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
}

start_spamassassin()
{
	stage_rc_conf spamd_enable=YES
	stage_rc_conf spamd_flags="-v -q -x -u spamd -H /var/spool/spamd -A 127.0.0.0/24"
	stage_exec service sa-spamd start
}

test_spamassassin()
{
	echo "testing spamassassin..."
	jexec $SAFE_NAME sockstat -l -4 | grep 789 || exit
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_staged_fs
stage_rc_conf hostname=spamassassin
start_staged_jail
install_spamassassin
configure_spamassassin
start_spamassassin
test_spamassassin
promote_staged_jail spamassassin
