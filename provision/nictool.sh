#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

export NICTOOL_VER=${NICTOOL_VER:="2.33"}
export NICTOOL_UPGRADE=""

mt6-include mysql
mt6-include user

install_nt_prereqs()
{
	assure_jail mysql

	tell_status "installing NicTool app prerequisites"
	stage_pkg_install perl5 mysql80-client apache24 ap24-mod_perl2 rsync p5-DBD-mysql

	tell_status "installing tools for NicTool exports"
	stage_pkg_install daemontools ucspi-tcp djbdns
	stage_pkg_install knot3

	tell_status "setting up svscan"
	stage_sysrc svscan_enable=YES
	mkdir -p "$STAGE_MNT/var/service"
}

install_nt_from_git()
{
	stage_pkg_install git-tiny || exit
	cd "$STAGE_MNT/usr/local" || exit
	stage_exec git clone --depth=1 https://github.com/msimerson/NicTool.git /usr/local/nictool || exit
	stage_pkg_install p5-App-Cpanminus
	stage_exec sh -c 'cd /usr/local/nictool/server; perl Makefile.PL; cpanm -n .'
	stage_exec sh -c 'cd /usr/local/nictool/client; perl Makefile.PL; cpanm -n .'
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

	_ntc_installed="$ZFS_JAIL_MNT/nictool/usr/local/nictool/client/lib/nictoolclient.conf"
	_ntcconf="$STAGE_MNT/usr/local/nictool/client/lib/nictoolclient.conf"
	if [ -f "$_ntc_installed" ]; then
		tell_status "preserving nictoolclient.conf"
		cp "${_ntcconf}.dist" "$_ntcconf"
	else
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

	_nts_installed="$ZFS_JAIL_MNT/nictool/usr/local/nictool/server/lib/nictoolserver.conf"
	_ntsconf="$STAGE_MNT/usr/local/nictool/server/lib/nictoolserver.conf"
	if [ -f "$_nts_installed" ]; then
		NICTOOL_UPGRADE="1"
		tell_status "preserving nictoolserver.conf"
		cp "${_nts_installed}" "${_ntsconf}"
	else
		tell_status "installing default $_ntsconf"
		cp "${_ntsconf}.dist" "$_ntsconf"
		sed -i.bak -e '/dsn/ s/127.0.0.1/mysql/' "$_ntsconf"

		for _jail in nictool stage; do
			for _ip in $(get_jail_ip "$_jail") $(get_jail_ip6 "$_jail");
			do
				echo "GRANT ALL PRIVILEGES ON nictool.* TO 'nictool'@'${_ip}' IDENTIFIED BY 'lootcin205';" | mysql_query || exit
			done
		done
	fi

	tell_status "installing NicToolServer dependencies"
	jexec stage bash -c "cd $_ntsdir; perl bin/nt_install_deps.pl"
}

install_apache_setup()
{
	_htcnf="$STAGE_MNT/usr/local/etc/apache24/Includes/nictool.conf"
	store_config "$_htcnf" <<EO_NICTOOL_APACHE24
LoadModule perl_module libexec/apache24/mod_perl.so
PerlRequire /usr/local/nictool/client/lib/nictoolclient.conf

<VirtualHost _default_:80>
    ServerName $TOASTER_HOSTNAME
    Alias /images/ "/usr/local/nictool/client/htdocs/images/"
    DocumentRoot /usr/local/nictool/client/htdocs
    DirectoryIndex index.cgi

    <Files "*.cgi">
       SetHandler perl-script
       PerlResponseHandler ModPerl::Registry
       PerlOptions +ParseHeaders
       Options +ExecCGI
    </Files>

    <Directory "/usr/local/nictool/client/htdocs">
        Require all granted
    </Directory>
</VirtualHost>

<IfDefine !MODPERL2>
   PerlFreshRestart On
</IfDefine>
PerlTaintCheck Off

Listen 8082

PerlRequire /usr/local/nictool/server/lib/nictoolserver.conf

<VirtualHost *:8082>
    KeepAlive Off
    <Location />
        SetHandler perl-script
        PerlResponseHandler NicToolServer
    </Location>
    <Location /soap>
        SetHandler perl-script
        PerlResponseHandler Apache::SOAP
        PerlSetVar dispatch_to "/usr/local/nictool/server, NicToolServer::SOAP"
    </Location>
</VirtualHost>
EO_NICTOOL_APACHE24

}

install_nictool_db()
{
	if [ "$NICTOOL_UPGRADE" = "1" ]; then return; fi

	mysql_create_db nictool || exit

	for f in "$STAGE_MNT"/usr/local/nictool/server/sql/*.sql; do
		tell_status "creating nictool table $f"
		# shellcheck disable=SC2002
		cat "$f" | mysql_query nictool || exit
		sleep 1;
	done
}

install_nictool()
{
	install_nt_prereqs
	# install_nt_from_tarball
	install_nt_from_git
	install_nictool_server
	install_nictool_client
	install_apache_setup
	install_nictool_db
	preserve_passdb nictool
}

start_nictool()
{
	tell_status "starting NicTool (apache 24)"
	stage_sysrc apache24_enable=YES
	stage_exec service apache24 start
}

test_nictool()
{
	tell_status "testing nictool"

	stage_listening 80
	stage_test_running httpd

	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs nictool
start_staged_jail nictool
install_nictool
start_nictool
test_nictool
promote_staged_jail nictool
