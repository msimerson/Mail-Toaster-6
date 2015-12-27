#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/clamav \$path/var/db/clamav nullfs rw 0 0\";"

install_clamav()
{
	stage_pkg_install clamav || exit
	echo "done"

	install_clamav_unofficial
}

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

	tell_status "installing ClamAV unofficial 4.8"
	local CLAMAV_UV=4.8
	local STAGE_ETC="$STAGE_MNT/usr/local/etc"

	stage_pkg_install gnupg1 rsync bind-tools
	fetch -m -o "$STAGE_MNT/tmp/" \
	  "https://github.com/extremeshok/clamav-unofficial-sigs/archive/$CLAMAV_UV.tar.gz"
	tar -xz -C "$STAGE_MNT/tmp/" -f "$STAGE_MNT/tmp/$CLAMAV_UV.tar.gz" || exit

	local _dist="$STAGE_MNT/tmp/clamav-unofficial-sigs-4.8"
	local _conf="$STAGE_ETC/clamav-unofficial-sigs.conf"

	if [ ! -f "$_conf" ]; then
		if [ -f "clamav-unofficial-sigs.conf" ]; then
			tell_status "installing local clamav-unofficial-sigs.conf"
			cp "clamav-unofficial-sigs.conf" "$STAGE_ETC/"
		fi
	fi

	if [ ! -f "$_conf" ]; then
		if [ -f "$ZFS_JAIL_MNT/clamav/usr/local/etc/clamav-unofficial-sigs.conf" ]; then
			tell_status "preserving clamav-unofficial-sigs.conf"
			cp "$ZFS_JAIL_MNT/clamav/usr/local/etc/clamav-unofficial-sigs.conf" \
				"$STAGE_ETC/"
		fi
	fi

	if [ ! -f "$_conf" ]; then
		tell_status "updating clamav-unofficial-sigs.conf"
		local _dist_conf="$_dist/clamav-unofficial-sigs.conf"
		sed -i .bak \
			-e 's/\/var\/lib/\/var\/db/' \
			-e 's/^clam_user="clam"/clam_user="clamav"/' \
			-e 's/^clam_group="clam"/clam_group="clamav"/' \
			"$_dist_conf"
		cp "$_dist_conf" "$_conf" || exit
	fi

	local _sigs_sh="$_dist/clamav-unofficial-sigs.sh"
	sed -i .bak -e 's/^#!\/bin\/bash/#!\/usr\/local\/bin\/bash/' "$_sigs_sh"
	chmod 755 "$_sigs_sh" || exit

	cp "$_sigs_sh" "$STAGE_MNT/usr/local/bin" || exit
	cp "$_dist/clamav-unofficial-sigs.8" "$STAGE_MNT/usr/local/man/man8" || exit
	mkdir -p "$STAGE_MNT/var/log/clamav-unofficial-sigs" || exit
	mkdir -p "$STAGE_ETC/periodic/daily" || exit

	tee "$STAGE_ETC/periodic/daily/clamav-unofficial-sigs" <<EOSIG
#!/bin/sh
/usr/local/bin/clamav-unofficial-sigs.sh -c /usr/local/etc/clamav-unofficial-sigs.conf
EOSIG
	chmod 755 "$STAGE_ETC/periodic/daily/clamav-unofficial-sigs" || exit
	mkdir -p "$STAGE_ETC/newsyslog.conf.d" || exit
	echo '/var/log/clamav-unofficial-sigs.log root:wheel 640  3 1000 * J' \
		> "$STAGE_ETC/newsyslog.conf.d/clamav-unofficial-sigs"
	stage_exec /usr/local/etc/periodic/daily/clamav-unofficial-sigs

	dialog --msgbox "ClamAV UNOFFICIAL is installed. Be sure to visit
	 https://github.com/extremeshok/clamav-unofficial-sigs and follow
	 the steps *after* the Quick Install Guide." 10 70
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
		-e 's/^#StructuredMinCreditCardCount 5/StructuredMinCreditCardCount 5/' \
		-e 's/^#StructuredMinSSNCount 5/StructuredMinSSNCount 5/' \
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
	echo "testing ClamAV..."
	stage_exec sockstat -l -4 | grep 3310 || exit
}

base_snapshot_exists || exit
create_staged_fs clamav
start_staged_jail
install_clamav
configure_clamav
start_clamav
test_clamav
promote_staged_jail clamav
