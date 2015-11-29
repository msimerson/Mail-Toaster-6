#!/bin/sh

. mail-toaster.sh || exit

install_clamav()
{
	pkg -j $SAFE_NAME install -y clamav || exit
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

}

start_clamav()
{
	sysrc -f $STAGE_MNT/etc/rc.conf clamav_freshclam_enable=YES
	sysrc -f $STAGE_MNT/etc/rc.conf clamav_clamd_enable=YES
	jexec $SAFE_NAME freshclam
	jexec $SAFE_NAME service clamav-clamd start
	jexec $SAFE_NAME service clamav-freshclam start
}

test_clamav()
{
	echo "testing ClamAV"
}

promote_staged_jail()
{
	stop_staged_jail

	rename_fs_staged_to_ready $1
	stop_active_jail $1
	rename_fs_active_to_last $1
	rename_fs_ready_to_active $1

	echo "start jail $1"
	service jail start $1 || exit
	proclaim_success $1
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_staged_fs
sysrc -f $STAGE_MNT/etc/rc.conf hostname=clamav
start_staged_jail
install_clamav
configure_clamav
start_clamav
test_clamav
promote_staged_jail clamav
