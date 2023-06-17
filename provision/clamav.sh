#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/clamav \$path/var/db/clamav nullfs rw 0 0\";"

install_clamav_fangfrisch()
{
	if [ "$CLAMAV_FANGFRISCH" = "0" ]; then return; fi

	stage_pkg_install python sqlite3 py39-sqlite3 sudo
	_fdir="$STAGE_MNT/usr/local/fangfrisch"
	mkdir "$_fdir"
	stage_exec sh -c "cd /usr/local/fangfrisch && python3 -m venv venv && source venv/bin/activate && pip install fangfrisch" || exit 1
	stage_exec chown -R clamav:clamav /usr/local/fangfrisch
	store_config "$_fdir/fangfrisch.conf" <<EO_FANG_CONF
[DEFAULT]
db_url = sqlite:////usr/local/fangfrisch/db.sqlite

# The following settings are optional. Other sections inherit
# values from DEFAULT and may also overwrite values.

local_directory = /var/db/clamav
max_size = 5MB
on_update_exec = clamdscan --reload
on_update_timeout = 42

[malwarepatrol]
enabled = yes
# Replace with your personal Malwarepatrol receipt
receipt = YOUR-RECEIPT-NUMBER

[sanesecurity]
enabled = yes

[securiteinfo]
enabled = yes
# Replace with your personal SecuriteInfo customer ID
customer_id = abcdef123456

[urlhaus]
enabled = yes
max_size = 2MB
EO_FANG_CONF
	stage_exec sudo -u clamav -- fangfrisch --conf /usr/local/fangfrisch/fangfrisch.conf initdb || exit 1
	stage_exec sudo -u clamav -- fangfrisch --conf /usr/local/fangfrisch/fangfrisch.conf refresh || exit 1
}

install_clamav_unofficial()
{
	if [ "$CLAMAV_UNOFFICIAL" = "0" ]; then return; fi

	if [ -z "$CLAMAV_UNOFFICIAL" ]; then
		local _es_mess="
	eXtremeSHOK maintains the ClamAV UNOFFICIAL project at
		https://github.com/extremeshok/clamav-unofficial-sigs

	ClamAV UNOFFICIAL is a set of scripts that download and update
	a collection of unofficial ClamAV signatures that significantly
	increase ClamAV's virus detection rate. However, they also
	increase the False Positive hits.

	Unofficial DBs are best used with scoring plugins (like karma)
	and with the clamav plugin configured with [reject]virus=false.

	Do you want to install ClamAV UNOFFICIAL?"

		dialog --yesno "$_es_mess" 18 74 || return
	fi

	local CLAMAV_UV=7.2.5
	tell_status "installing ClamAV unofficial $CLAMAV_UV"

	stage_pkg_install gnupg1 rsync bind-tools gtar
	fetch -m -o "$STAGE_MNT/tmp/" \
	  "https://github.com/extremeshok/clamav-unofficial-sigs/archive/$CLAMAV_UV.tar.gz"
	tar -xz -C "$STAGE_MNT/tmp/" -f "$STAGE_MNT/tmp/$CLAMAV_UV.tar.gz" || exit

	local _dist="$STAGE_MNT/tmp/clamav-unofficial-sigs-$CLAMAV_UV"
	local _conf="$STAGE_MNT/etc/clamav-unofficial-sigs"

	tell_status "installing config files"
	mkdir -p "$_conf" || exit
	cp -r "$_dist/config/" "$_conf/" || exit
	cp "$_conf/os/os.freebsd.conf" "$_conf/os.conf" || exit

	if [ -f "$ZFS_JAIL_MNT/clamav/etc/clamav-unofficial-sigs/user.conf" ]; then
		tell_status "preserving user.conf"
		cp "$ZFS_JAIL_MNT/clamav/etc/clamav-unofficial-sigs/user.conf" "$_conf/" || exit
		echo "done"
	else
		tell_status "completing user configuration"
		sed -i.bak \
			-e '/^#user_configuration_complete/ s/^#//' \
			"$_conf/user.conf"
		echo "done"
	fi

	if grep -qs ^Antidebug_AntiVM "$_conf/master.conf"; then
		tell_status "disabling error throwing rules"
		echo "see https://github.com/extremeshok/clamav-unofficial-sigs/issues/151"
		sed -i.bak \
			-e '/^Antidebug_AntiVM/ s/^A/#A/' \
			-e '/^email/ s/^e/#e/' \
			"$_conf/master.conf"
	fi

	tell_status "installing clamav-unofficial-sigs.sh"
	local _sigs_sh="$_dist/clamav-unofficial-sigs.sh"
	sed -i.bak -e 's/^#!\/bin\/bash/#!\/usr\/local\/bin\/bash/' "$_sigs_sh"
	chmod 755 "$_sigs_sh" || exit
	cp "$_sigs_sh" "$STAGE_MNT/usr/local/bin" || exit

	mkdir -p "$STAGE_MNT/var/log/clamav-unofficial-sigs" || exit
	stage_exec /usr/local/bin/clamav-unofficial-sigs.sh --install-cron
	stage_exec /usr/local/bin/clamav-unofficial-sigs.sh --install-logrotate
	stage_exec /usr/local/bin/clamav-unofficial-sigs.sh --install-man

	tell_status "starting a ClamAV UNOFFICIAL update"
	stage_exec /usr/local/bin/clamav-unofficial-sigs.sh

	if [ ! -d "$STAGE_MNT/var/db/clamav-unofficial-sigs/configs" ]; then
		mkdir -p "$STAGE_MNT/var/db/clamav-unofficial-sigs/configs"
		touch "$STAGE_MNT/var/db/clamav-unofficial-sigs/configs/last-version-check.txt"
		chown 106:106 "$STAGE_MNT/var/db/clamav-unofficial-sigs/configs/last-version-check.txt"
	fi

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
	stage_sysrc nrpe_enable=YES
	stage_sysrc nrpe_configfile="/data/etc/nrpe.cfg"
}

install_clamav()
{
	stage_pkg_install clamav || exit
	echo "done"

	install_clamav_nrpe
	install_clamav_unofficial
	install_clamav_fangfrisch
}

configure_clamd()
{
	tell_status "configuring clamd"
	local _conf="$STAGE_MNT/usr/local/etc/clamd.conf"

	sed -i.bak \
		-e '/^#TCPSocket/   s/^#//' \
		-e '/^#LogFacility/ s/^#//' \
		-e '/^#LogSyslog/   s/^#//; s/no/yes/' \
		-e '/^LogFile /     s/^L/#L/' \
		-e '/^#DetectPUA/   s/^#//' \
		-e '/^#ExtendedDetectionInfo/   s/^#//' \
		-e '/^#DetectBrokenExecutables/ s/^#//' \
		-e '/^#StructuredDataDetection/ s/^#//' \
		-e '/^#ArchiveBlockEncrypted/   s/^#//; s/no/yes/' \
		-e '/^#OLE2BlockMacros/         s/^#//; s/no/yes/'  \
		-e '/^#PhishingSignatures yes/  s/^#//' \
		-e '/^#PhishingScanURLs/        s/^#//' \
		-e '/^#HeuristicScanPrecedence/ s/^#//; s/yes/no/' \
		-e '/^#StructuredDataDetection/ s/^#//' \
		-e '/^#StructuredMinCreditCardCount/ s/^#//; s/5/10/' \
		-e '/^#StructuredMinSSNCount/        s/^#//; s/5/10/' \
		-e '/^#StructuredSSNFormatStripped/  s/^#//; s/yes/no/' \
		-e '/^#ScanArchive/ s/^#//' \
		"$_conf" || exit

	echo "done"
}

configure_freshclam()
{
	tell_status "configuring freshclam"
	local _conf="$STAGE_MNT/usr/local/etc/freshclam.conf"

	sed -i.bak \
		-e '/^UpdateLogFile/  s/^#//' \
		-e '/^#LogSyslog/ s/^#//' \
		-e '/^#LogFacility/ s/^#//' \
		-e '/^#SafeBrowsing/ s/^#//' \
		-e '/^#DatabaseMirror/ s/^#//; s/XY/us/' \
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
	stage_listening 3310 2
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
