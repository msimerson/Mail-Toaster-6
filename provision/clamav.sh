#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

install_clamav_fangfrisch()
{
	if [ "$CLAMAV_FANGFRISCH" = "0" ]; then return; fi

	stage_pkg_install python sqlite3 py39-sqlite3 sudo
	_fdir="/usr/local/fangfrisch"
	stage_exec mkdir "$_fdir"
	stage_exec bash -c 'cd /usr/local/fangfrisch && python3 -m venv venv && source venv/bin/activate && pip install fangfrisch'
	stage_exec chown -R clamav:clamav $_fdir
	store_config "${STAGE_MNT}${_fdir}/fangfrisch.conf" <<EO_FANG_CONF
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
	stage_exec sudo -u clamav -- $_fdir/venv/bin/fangfrisch --conf $_fdir/fangfrisch.conf initdb
	stage_exec sudo -u clamav -- $_fdir/venv/bin/fangfrisch --conf $_fdir/fangfrisch.conf refresh
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
	tar -xz -C "$STAGE_MNT/tmp/" -f "$STAGE_MNT/tmp/$CLAMAV_UV.tar.gz"

	local _dist="$STAGE_MNT/tmp/clamav-unofficial-sigs-$CLAMAV_UV"
	local _conf="$STAGE_MNT/etc/clamav-unofficial-sigs"

	tell_status "installing config files"
	mkdir -p "$_conf"
	cp -r "$_dist/config/" "$_conf/"
	cp "$_conf/os/os.freebsd.conf" "$_conf/os.conf"

	if [ -f "$ZFS_JAIL_MNT/clamav/etc/clamav-unofficial-sigs/user.conf" ]; then
		tell_status "preserving user.conf"
		cp "$ZFS_JAIL_MNT/clamav/etc/clamav-unofficial-sigs/user.conf" "$_conf/"
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
	chmod 755 "$_sigs_sh"
	cp "$_sigs_sh" "$STAGE_MNT/usr/local/bin"

	mkdir -p "$STAGE_MNT/var/log/clamav-unofficial-sigs"
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

	tell_status "installing nagios plugin (includes check_clamd)"
	stage_pkg_install nagios-plugins

	tell_status "installing clamav nrpe plugin"
	stage_pkg_install nagios-check_clamav || stage_port_install net-mgmt/nagios-check_clamav
	sed -i .bak \
		-e 's|clamd_cmd -V|clamd_cmd --datadir=/data/db -V|' \
		"$STAGE_MNT/usr/local/libexec/nagios/check_clamav"

	fetch -m -o "$ZFS_DATA_MNT/clamav/check_clamav_signatures" \
		https://raw.githubusercontent.com/tommarshall/nagios-check-clamav-signatures/master/check_clamav_signatures
	sed -i.bak \
		-e 's|^#!/usr/bin/env bash|#!/usr/local/bin/bash\
PATH="$PATH:/usr/local/bin"|' \
		-e '/^CLAM_LIB_DIR/ s|=.*$|=/data/db|' \
		"$ZFS_DATA_MNT/clamav/check_clamav_signatures"
	chmod 755 "$ZFS_DATA_MNT/clamav/check_clamav_signatures"

	if [ -f /usr/local/etc/nrpe.cfg ]; then
		if ! grep -q 'command[check_clamav' /usr/local/etc/nrpe.cfg; then
			echo 'command[check_clamav]=/usr/local/bin/sudo /usr/sbin/jexec clamav /usr/local/libexec/nagios/check_clamav -w3 -c5' \
				| tee -a /usr/local/etc/nrpe.cfg
		fi
#		if ! grep -q check_clamav_signatures /usr/local/etc/nrpe.cfg; then
#			echo 'command[check_clamav]=/usr/local/bin/sudo jexec clamav /data/check_clamav_signatures -p /data/db' \
#				| tee -a /usr/local/etc/nrpe.cfg
#		fi
 	fi
}

install_clamav_port()
{
	stage_pkg_install arc arj curl cmake expat gmake gettext curl json-c libmspack libpsl libxml2 ninja pcre2 perl5 portconfig python3
	stage_port_install security/clamav
}

install_clamav()
{
	stage_pkg_install clamav || install_clamav_port
	echo "done"

	for _d in etc db log; do
		_path="$STAGE_MNT/data/$_d"
		[ -d "$_path" ] || mkdir "$_path"
	done

	stage_exec chown clamav:clamav /data/log /data/db

	install_clamav_nrpe
	install_clamav_unofficial
	install_clamav_fangfrisch
}

configure_clamd()
{
	tell_status "configuring clamd"
	local _conf="$STAGE_MNT/data/etc/clamd.conf"
	if [ ! -f "$_conf" ]; then
		cp "$STAGE_MNT/usr/local/etc/clamd.conf" "$_conf"
	fi

	sed -i.bak \
		-e 's/^#TCPSocket/TCPSocket/' \
		-e 's/^#LogFacility/LogFacility/' \
		-e 's/^#LogSyslog no/LogSyslog yes/' \
		-e 's/LogFile \/var\/log\/clamav/LogFile \/data\/log/' \
		-e 's/^#DetectPUA/DetectPUA/' \
		-e 's/DatabaseDirectory \/var\/db\/clamav/DatabaseDirectory \/data\/db/' \
		-e 's/^#ExtendedDetectionInfo/ExtendedDetectionInfo/' \
		-e 's/^#DetectBrokenExecutables/DetectBrokenExecutables/' \
		-e 's/^#StructuredDataDetection/StructuredDataDetection/' \
		-e 's/^#ArchiveBlockEncrypted no/ArchiveBlockEncrypted yes/' \
		-e 's/^#OLE2BlockMacros no/OLE2BlockMacros yes/' \
		-e 's/^#PhishingSignatures /PhishingSignatures /' \
		-e 's/^#PhishingScanURLs/PhishingScanURLs/' \
		-e 's/^#HeuristicScanPrecedence yes/HeuristicScanPrecedence no/' \
		-e 's/^#StructuredDataDetection/StructuredDataDetection/' \
		-e 's/^#StructuredMinCreditCardCount 5/StructuredMinCreditCardCount 10/' \
		-e 's/^#StructuredMinSSNCount 5/StructuredMinSSNCount 10/' \
		-e 's/^#StructuredSSNFormatStripped yes/StructuredSSNFormatStripped no/' \
		-e '/^#ScanArchive/ s/^#ScanArchive/ScanArchive/' \
		"$_conf"

	echo "done"

	sed -i '' \
		-e 's/\/usr\/local\/etc/\/data\/etc/g' \
		-e 's/\/var\/db\/clamav/\/data\/db/g' \
		"$STAGE_MNT/usr/local/etc/rc.d/clamav_clamd"
}

configure_freshclam()
{
	local _conf="$STAGE_MNT/data/etc/freshclam.conf"
	if [ -f "$_conf" ]; then
		tell_status "freshclam already configured"
	else
		tell_status "configuring freshclam"
		cp "$STAGE_MNT/usr/local/etc/freshclam.conf" "$_conf"

		sed -i.bak \
			-e 's/DatabaseDirectory \/var\/db\/clamav/DatabaseDirectory \/data\/db/' \
			-e 's/^UpdateLogFile \/var\/log\/clamav/UpdateLogFile \/data\/log/' \
			-e 's/^#LogSyslog/LogSyslog/' \
			-e 's/^#LogFacility/LogFacility/' \
			-e 's/^#SafeBrowsing/SafeBrowsing/' \
			-e 's/^#DatabaseMirror/DatabaseMirror/; s/XY/us/' \
			"$_conf"
	fi

	echo "done"
	sed -i '' \
		-e 's/\/usr\/local\/etc/\/data\/etc/g' \
		-e 's/\/var\/db\/clamav/\/data\/db/g' \
		"$STAGE_MNT/usr/local/etc/rc.d/clamav_freshclam"
}

configure_clamav()
{
	configure_clamd
	configure_freshclam
}

start_clamav()
{
	tell_status "downloading virus definition databases"
	if ! pgrep -q freshclam; then
		stage_exec freshclam --config-file=/data/etc/freshclam.conf --datadir=/data/db
	fi

	tell_status "starting ClamAV daemons"
	stage_sysrc clamav_clamd_enable=YES
	stage_sysrc clamav_clamd_flags="-c /data/etc/clamd.conf"
	stage_exec service clamav_clamd start

	stage_sysrc clamav_freshclam_enable=YES
	stage_sysrc clamav_freshclam_flags="--config-file=/data/etc/freshclam.conf --datadir=/data/db"
	stage_exec service clamav_freshclam start
}

migrate_clamav_dbs()
{
	if [ ! -f "$ZFS_DATA_MNT/clamav/daily.cld" ]; then
		# no clamav dbs or already migrated
		return
	fi

	local _confirm_msg="
	clamav db migration required. Choosing yes will:

	1. stop the running clamav jail
	2. move the clamav dbs into 'data/db'
	3. promote this newly build clamav jail

	Proceed?
	"
	dialog --yesno "$_confirm_msg" 13 70

	if [ ! -d "$ZFS_DATA_MNT/clamav/db" ]; then
		mkdir "$ZFS_DATA_MNT/clamav/db"
	fi

	service jail stop clamav

	for _suffix in cdb cld cvd dat fp ftm hsb ldb ndb yara; do
		for _db in "$ZFS_DATA_MNT"/clamav/*."$_suffix"; do
			echo "mv $_db $ZFS_DATA_MNT/clamav/db/"
			mv "$_db" "$ZFS_DATA_MNT/clamav/db/"
		done
	done
}

test_clamav()
{
	echo "testing ClamAV clamd"
	stage_listening 3310 2
	echo "It works! (clamd is listening)"
}

base_snapshot_exists || exit 1
migrate_clamav_dbs
create_staged_fs clamav
start_staged_jail clamav
install_clamav
configure_clamav
start_clamav
test_clamav
promote_staged_jail clamav
