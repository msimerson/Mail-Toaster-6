#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

# shellcheck disable=2016
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/nictool \$path/data nullfs rw 0 0\";"

export NICTOOL_VER=${NICTOOL_VER:="2.33"}

install_nt_prereqs()
{
	tell_status "installing NicTool prerequisites"
	stage_pkg_install perl5 mysql56-client apache24 rsync
}

install_nt_from_tarball()
{
	tell_status "downloading NicTool $NICTOOL_VER"
	mkdir -p "$STAGE_MNT/usr/local/nictool"
	cd "$STAGE_MNT/usr/local/nictool" || exit

	fetch "https://github.com/msimerson/NicTool/releases/download/$NICTOOL_VER/NicTool-$NICTOOL_VER.tar.gz"

	tell_status "extracting NicTool $NICTOOL_VER"
	tar -xzf "NicTool-$NICTOOL_VER.tar.gz" || exit
	tar -xzf "server/NicToolServer-$NICTOOL_VER.tar.gz"
	tar -xzf "client/NicToolClient-$NICTOOL_VER.tar.gz"
	rm -rf client server
	mv "NicToolServer-$NICTOOL_VER" server
	mv "NicToolClient-$NICTOOL_VER" client
}

install_nictool_client() {
	tell_status "install NicToolClient $NICTOOL_VER"

	_ntcdir="/usr/local/nictool/client"
	jexec stage bash -c "cd $_ntcdir && perl Makefile.PL"
	stage_exec make -C $_ntcdir
	stage_exec make -C $_ntcdir install clean

	_ntcconf="$STAGE_MNT/usr/local/nictool/client/lib/nictoolclient.conf"
	if [ ! -f "$_ntcconf" ]; then
		tell_status "installing default $_ntcconf"
		cp "${_ntcconf}.dist" "$_ntcconf"
	fi

	tell_status "installing NicToolClient dependencies"
	jexec stage bash -c "cd $_ntcdir; perl bin/install_deps.pl"
}

install_nictool_server() {
	tell_status "install NicToolServer $NICTOOL_VER"

	_ntsdir="/usr/local/nictool/server"
	jexec stage bash -c "cd $_ntsdir; perl Makefile.PL"
	stage_exec make -C $_ntsdir
	stage_exec make -C $_ntsdir install clean

	_ntsconf="$STAGE_MNT/usr/local/nictool/server/lib/nictoolserver.conf"
	if [ ! -f "$_ntsconf" ]; then
		tell_status "installing default $_ntsconf"
		cp "${_ntsconf}.dist" "$_ntsconf"
	fi

	tell_status "installing NicToolServer dependencies"
	jexec stage bash -c "cd $_ntsdir; perl bin/nt_install_deps.pl"
}

install_apache_setup()
{
	fetch -o "$STAGE_MNT/usr/local/etc/apache24/Includes/nictool.conf" \
		http://www.nictool.com/download/nictool-24.conf
}

install_nictool()
{
	install_nt_prereqs
	install_nt_from_tarball
	install_nictool_server
	install_nictool_client
	install_apache_setup
}

start_nictool()
{
	tell_status "starting NicTool"
	stage_sysrc apache24_enable=YES
	stage_exec service apache24 start
}

test_nictool()
{
	tell_status "testing nictool"

	stage_listening 443
	stage_test_running httpd

	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs nictool
start_staged_jail
install_nictool
start_nictool
test_nictool
promote_staged_jail nictool
