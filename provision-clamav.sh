#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/clamav \$path/var/db/clamav nullfs rw 0 0\";"

install_clamav_unofficial()
{
	if [ -z "$CLAMAV_UNOFFICIAL" ]; then
		local _es_mess="
	eXtremeSHOK maintains the ClamAV UNOFFICIAL project at
		https://github.com/extremeshok/clamav-unofficial-sigs

	The project is a set of scripts that download and keep updated
	a collection of unofficial ClamAV signatures that significantly
	increase ClamAV's virus detection rate. However, they also
	increase the False Positive hits.

	Unofficial DBs are best used with Haraka's karma plugin (scoring)
	and with the clamav plugin configured with [reject]virus=false.

	Do you want to install ClamAV UNOFFICIAL?"

		dialog --yesno "$_es_mess" 18 74 || return
	fi

	local CLAMAV_UV=5.4.1
	tell_status "installing ClamAV unofficial $CLAMAV_UV"

	stage_pkg_install gnupg1 rsync bind-tools
	fetch -m -o "$STAGE_MNT/tmp/" \
	  "https://github.com/extremeshok/clamav-unofficial-sigs/archive/$CLAMAV_UV.tar.gz"
	tar -xz -C "$STAGE_MNT/tmp/" -f "$STAGE_MNT/tmp/$CLAMAV_UV.tar.gz" || exit

	local _dist="$STAGE_MNT/tmp/clamav-unofficial-sigs-$CLAMAV_UV"
	local _conf="$STAGE_MNT/etc/clamav-unofficial-sigs"

	tell_status "installing config files"
	mkdir -p "$_conf" || exit
	cp -r "$_dist/config/" "$_conf/" || exit
	cp "$_conf/os.freebsd.conf" "$_conf/os.conf" || exit

	if [ -f "$ZFS_JAIL_MNT/clamav/etc/clamav-unofficial-sigs/user.conf" ]; then
		tell_status "preserving user.conf"
		cp "$ZFS_JAIL_MNT/clamav/etc/clamav-unofficial-sigs/user.conf" \
			"$_conf/" || exit
		echo "done"
	else
		tell_status "completing user configuration"
		sed -i .bak \
			-e '/^#user_configuration_complete/ s/^#//' \
			"$_conf/user.conf"
		echo "done"
	fi

	if grep -qs ^Antidebug_AntiVM "$_conf/master.conf"; then
		tell_status "disabling error throwing rules"
		echo "see https://github.com/extremeshok/clamav-unofficial-sigs/issues/151"
		sed -i .bak \
			-e '/^Antidebug_AntiVM/ s/^A/#A/' \
			-e '/^email/ s/^e/#e/' \
			"$_conf/master.conf"
	fi

	tell_status "installing clamav-unofficial-sigs.sh"
	local _sigs_sh="$_dist/clamav-unofficial-sigs.sh"
	sed -i .bak -e 's/^#!\/bin\/bash/#!\/usr\/local\/bin\/bash/' "$_sigs_sh"
	chmod 755 "$_sigs_sh" || exit
	cp "$_sigs_sh" "$STAGE_MNT/usr/local/bin" || exit

	mkdir -p "$STAGE_MNT/var/log/clamav-unofficial-sigs" || exit
	stage_exec /usr/local/bin/clamav-unofficial-sigs.sh --install-cron
	stage_exec /usr/local/bin/clamav-unofficial-sigs.sh --install-logrotate
	stage_exec /usr/local/bin/clamav-unofficial-sigs.sh --install-man

	tell_status "starting a ClamAV UNOFFICIAL update"
	stage_exec /usr/local/bin/clamav-unofficial-sigs.sh

	for f in EMAIL_Cryptowall.yar antidebug_antivm.yar; do
		if [ -f "$ZFS_DATA_MNT/clamav/$f" ]; then
			rm "$ZFS_DATA_MNT/clamav/$f"
		fi
	done

	if [ -z "$CLAMAV_UNOFFICIAL" ]; then
		dialog --msgbox "ClamAV UNOFFICIAL is installed. Be sure to visit
	 https://github.com/extremeshok/clamav-unofficial-sigs and follow
	 the steps *after* the Quick Install Guide." 10 70
	fi
}

install_clamav_nrpe()
{
	if [ -z "$TOASTER_NRPE" ]; then
		echo "TOASTER_NRPE unset, skipping nrpe plugin"
		return
	fi

	tell_status "installing clamav nrpe plugin"
	stage_pkg_install nagios-check_clamav
}

install_clamav()
{
	stage_pkg_install clamav || exit
	echo "done"

	install_clamav_nrpe
	install_clamav_unofficial
}

configure_clamd()
{
	tell_status "configuring clamd"
	local _conf="$STAGE_MNT/usr/local/etc/clamd.conf"

	sed -i .bak \
		-e 's/^#TCPAddr 127.0.0.1/TCPAddr 0.0.0.0/' \
		-e 's/^#TCPSocket 3310/TCPSocket 3310/' \
		-e 's/^#LogFacility LOG_MAIL/LogFacility LOG_MAIL/' \
		-e 's/^#LogSyslog yes/LogSyslog yes/' \
		-e 's/^LogFile /#LogFile /' \
		-e 's/^#ExtendedDetectionInfo /ExtendedDetectionInfo /' \
		-e 's/^#DetectPUA/DetectPUA/' \
		-e 's/^#DetectBrokenExecutables/DetectBrokenExecutables/' \
		-e 's/^#StructuredDataDetection/StructuredDataDetection/' \
		-e 's/^#ArchiveBlockEncrypted no/ArchiveBlockEncrypted yes/' \
		-e 's/^#OLE2BlockMacros no/OLE2BlockMacros yes/'  \
		-e 's/^#PhishingSignatures yes/PhishingSignatures yes/' \
		-e 's/^#PhishingScanURLs yes/PhishingScanURLs yes/' \
		-e 's/#HeuristicScanPrecedence yes/HeuristicScanPrecedence no/' \
		-e 's/^#StructuredDataDetection yes/StructuredDataDetection yes/' \
		-e 's/^#StructuredMinCreditCardCount 5/StructuredMinCreditCardCount 10/' \
		-e 's/^#StructuredMinSSNCount 5/StructuredMinSSNCount 10/' \
		-e 's/^#StructuredSSNFormatStripped yes/StructuredSSNFormatStripped no/' \
		-e 's/^#ScanArchive yes/ScanArchive yes/' \
		"$_conf" || exit

	echo "done"
}

configure_freshclam()
{
	tell_status "configuring freshclam"
	local _conf="$STAGE_MNT/usr/local/etc/freshclam.conf"

	sed -i .bak \
		-e 's/^UpdateLogFile /#UpdateLogFile /' \
		-e 's/^#LogSyslog yes/LogSyslog yes/' \
		-e 's/^#LogFacility LOG_MAIL/LogFacility LOG_MAIL/' \
		-e 's/^#SafeBrowsing yes/SafeBrowsing yes/' \
		-e 's/^#DatabaseMirror db.XY.clamav.net/DatabaseMirror db.us.clamav.net/' \
		"$_conf" || exit

	echo "done"
}

configure_clamav()
{
	configure_clamd
	configure_freshclam
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
	echo "testing ClamAV clamd"
	stage_listening 3310
	echo "It works! (clamd is listening)"
}

base_snapshot_exists || exit
create_staged_fs clamav
start_staged_jail clamav
install_clamav
configure_clamav
start_clamav
test_clamav
promote_staged_jail clamav
