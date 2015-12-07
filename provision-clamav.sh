#!/bin/sh

. mail-toaster.sh || exit

install_clamav()
{
	stage_pkg_install clamav || exit
}

install_clamav_unofficial()
{
	local CLAMAV_UV=4.8
	stage_pkg_install gnupg1 rsync bind-tools
	fetch -m -o $STAGE_MNT/tmp/ \
	  https://github.com/extremeshok/clamav-unofficial-sigs/archive/$CLAMAV_UV.tar.gz
	tar -xz -C $STAGE_MNT/tmp/ -f $STAGE_MNT/tmp/$CLAMAV_UV.tar.gz || exit

	local _dist="$STAGE_MNT/tmp/clamav-unofficial-sigs-4.8"
	local _sigs_conf="$_dist/clamav-unofficial-sigs.conf"
	sed -i .bak -e 's/\/var\/lib/\/var\/db/' $_sigs_conf
	sed -i .bak -e 's/^clam_user="clam"/clam_user="clamav"/' $_sigs_conf
	sed -i .bak -e 's/^clam_group="clam"/clam_group="clamav"/' $_sigs_conf

	local _sigs_sh="$_dist/clamav-unofficial-sigs.sh"
	sed -i .bak -e 's/^#!\/bin\/bash/#!\/usr\/local\/bin\/bash/' $_sigs_sh
	chmod 755 $_sigs_sh || exit

	cp $_sigs_sh $STAGE_MNT/usr/local/bin || exit
	cp $_sigs_conf $STAGE_MNT/usr/local/etc/ || exit
	cp $_dist/clamav-unofficial-sigs.8 $STAGE_MNT/usr/local/man/man8 || exit
	mkdir -p $STAGE_MNT/var/log/clamav-unofficial-sigs || exit
	mkdir -p $STAGE_MNT/usr/local/etc/periodic/daily || exit

	tee $STAGE_MNT/usr/local/etc/periodic/daily/clamav-unofficial-sigs <<EOSIG
#!/bin/sh
/usr/local/bin/clamav-unofficial-sigs.sh -c /usr/local/etc/clamav-unofficial-sigs.conf
EOSIG
	chmod 755 $STAGE_MNT/usr/local/etc/periodic/daily/clamav-unofficial-sigs || exit
	mkdir -p $STAGE_MNT/usr/local/etc/newsyslog.conf.d || exit
	echo '/var/log/clamav-unofficial-sigs.log root:wheel 640  3 1000 * J' \
		> $STAGE_MNT/usr/local/etc/newsyslog.conf.d/clamav-unofficial-sigs
	jexec $SAFE_NAME /usr/local/etc/periodic/daily/clamav-unofficial-sigs
}

configure_clamav()
{
	local _clamconf="$STAGE_MNT/usr/local/etc/clamd.conf"

	sed -i .bak -e 's/#TCPAddr 127.0.0.1/TCPAddr 0.0.0.0/' $_clamconf
	sed -i .bak -e 's/#TCPSocket 3310/TCPSocket 3310/' $_clamconf
	sed -i .bak -e 's/#LogFacility LOG_MAIL/LogFacility LOG_MAIL/' $_clamconf
	sed -i .bak -e 's/#LogSyslog yes/LogSyslog yes/' $_clamconf
	sed -i .bak -e 's/^LogFile /#LogFile /' $_clamconf

	# these are more prone to FPs
	sed -i .bak -e 's/#DetectPUA/DetectPUA/' $_clamconf
	sed -i .bak -e 's/#DetectBrokenExecutables/DetectBrokenExecutables/' $_clamconf
	sed -i .bak -e 's/#StructuredDataDetection/StructuredDataDetection/' $_clamconf
	sed -i .bak -e 's/#ArchiveBlockEncrypted no/ArchiveBlockEncrypted yes/' $_clamconf

	#tell_status "installing ClamAV unofficial"
	#install_clamav_unofficial
}

start_clamav()
{
	tell_status "downloading virus definition databases"
	stage_exec freshclam

	tell_status "starting ClamAV daemons"
	stage_sysrc clamav_clamd_enable=YES
	stage_exec service clamav-clamd start

	stage_sysrc clamav_freshclam_enable=YES
	stage_exec service clamav-freshclam start
}

test_clamav()
{
	echo "testing ClamAV..."
	stage_exec sockstat -l -4 | grep 3310 || exit
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_staged_fs clamav
stage_sysrc hostname=clamav
start_staged_jail
install_clamav
configure_clamav
start_clamav
test_clamav
promote_staged_jail clamav
