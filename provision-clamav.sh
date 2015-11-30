#!/bin/sh

. mail-toaster.sh || exit

install_clamav()
{
	pkg -j $SAFE_NAME install -y clamav || exit
}

install_clamav_unofficial()
{
	CLAMAV_UV=4.8
	pkg install -y gnupg1 rsync bind-tools
	fetch https://github.com/extremeshok/clamav-unofficial-sigs/archive/$CLAMAV_UV.tar.gz
	tar -xzf $CLAMAV_UV.tar.gz

	cd clamav-unofficial-sigs-$CLAMAV_UV
	sed -i .bak -e 's/\/var\/lib/\/var\/db/' clamav-unofficial-sigs.conf
	sed -i .bak -e 's/^clam_user="clam"/clam_user="clamav"/' clamav-unofficial-sigs.conf
	sed -i .bak -e 's/^clam_group="clam"/clam_group="clamav"/' clamav-unofficial-sigs.conf
	sed -i .bak -e 's/^#!\/bin\/bash/#!\/usr\/local\/bin\/bash/' clamav-unofficial-sigs.sh

	chmod 755 clamav-unofficial-sigs.sh
	cp clamav-unofficial-sigs.sh  /usr/local/bin
	cp clamav-unofficial-sigs.conf /usr/local/etc/
	cp clamav-unofficial-sigs.8 /usr/local/man/man8
	mkdir -p /var/log/clamav-unofficial-sigs
	mkdir -p /usr/local/etc/periodic/daily

	tee <<EOSIG > /usr/local/etc/periodic/daily/clamav-unofficial-sigs
#!/bin/sh
/usr/local/bin/clamav-unofficial-sigs.sh -c /usr/local/etc/clamav-unofficial-sigs.conf
EOSIG
	chmod 755 /usr/local/etc/periodic/daily/clamav-unofficial-sigs
	mkdir -p /usr/local/etc/newsyslog.conf.d
	echo '/var/log/clamav-unofficial-sigs.log root:wheel 640  3 1000 * J' \
		> /usr/local/etc/newsyslog.conf.d/clamav-unofficial-sigs
	/usr/local/etc/periodic/daily/clamav-unofficial-sigs
}

configure_clamav()
{
	local _clamconf="$STAGE_MNT/usr/local/etc/clamd.conf"

	sed -i .bak -e 's/#TCPAddr 127.0.0.1/TCPAddr 127.0.0.5/' $_clamconf
	sed -i .bak -e 's/#TCPSocket 3310/TCPSocket 3310/' $_clamconf
	sed -i .bak -e 's/#LogFacility LOG_MAIL/LogFacility LOG_MAIL/' $_clamconf
	sed -i .bak -e 's/#LogSyslog yes/LogSyslog yes/' $_clamconf
	sed -i .bak -e 's/^LogFile /#LogFile /' $_clamconf

	# these are more prone to FPs
	sed -i .bak -e 's/#DetectPUA/DetectPUA/' $_clamconf
	sed -i .bak -e 's/#DetectBrokenExecutables/DetectBrokenExecutables/' $_clamconf
	sed -i .bak -e 's/#StructuredDataDetection/StructuredDataDetection/' $_clamconf
	sed -i .bak -e 's/#ArchiveBlockEncrypted no/ArchiveBlockEncrypted yes/' $_clamconf

	echo "installing ClamAV unofficial...TODO"
	# install_clamav_unofficial
}

start_clamav()
{
	stage_rc_conf clamav_freshclam_enable=YES
	stage_rc_conf clamav_clamd_enable=YES
	jexec $SAFE_NAME freshclam
	jexec $SAFE_NAME service clamav-clamd start
	jexec $SAFE_NAME service clamav-freshclam start
}

test_clamav()
{
	echo "testing ClamAV... TODO"
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_staged_fs
stage_rc_conf hostname=clamav
start_staged_jail
install_clamav
configure_clamav
start_clamav
test_clamav
promote_staged_jail clamav
