#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_monitor()
{
	tell_status "installing swaks"
	stage_pkg_install swaks p5-Net-SSLeay || exit

	tell_status "installing lighttpd"
	stage_pkg_install lighttpd
	stage_sysrc lighttpd_enable="YES"
	stage_sysrc lighttpd_conf="/data/etc/lighttpd.conf"

	install_nagios
	install_munin
}

install_nagios()
{
	tell_status "installing nagios & nrpe"
	stage_pkg_install nagios nrpe-ssl
}

install_munin()
{
	tell_status "installing munin"
	stage_pkg_install munin-node munin-master
}

configure_munin()
{
	rm -r "$STAGE_MNT/usr/local/etc/munin"
	stage_exec ln -s /data/etc/munin /usr/local/etc/munin

	stage_sysrc munin_node_enable=YES
	stage_sysrc munin_node_config=/data/etc/munin/munin-node.conf
}

configure_nrpe()
{
	if [ -f "$ZFS_DATA_MNT/monitor/etc/nrpe.cfg" ]; then
		tell_status "preserving nrpe.cfg"
		rm "$STAGE_MNT/usr/local/etc/nrpe.cfg"
	else
		tell_status "installing default nrpe.cfg"
		mv "$STAGE_MNT/usr/local/etc/nrpe.cfg" \
			"$ZFS_DATA_MNT/monitor/etc/nrpe.cfg"
	fi

	stage_exec ln -s /data/etc/nrpe.cfg /usr/local/etc/nrpe.cfg
	stage_sysrc nrpe2_enable="YES"
	stage_sysrc nrpe2_configfile=/data/etc/nrpe.cfg
}

configure_monitor()
{
	tell_status "configuring monitor"
	if [ ! -d "$ZFS_DATA_MNT/monitor/etc" ]; then
		mkdir "$ZFS_DATA_MNT/monitor/etc"
	fi

	configure_nrpe
	configure_munin
}

start_monitor()
{
   	tell_status "starting monitor"
}

test_monitor()
{
	tell_status "testing monitor"

	local _email _server _pass
	_email="postmaster@$TOASTER_MAIL_DOMAIN"
	_server=$(get_jail_ip haraka)
	_pass=$(jexec vpopmail /usr/local/vpopmail/bin/vuserinfo -C "$_email")

	tell_status "sending an email to $_email"
	stage_exec swaks -to "$_email" -server "$_server" -timeout 50 || exit

	tell_status "sending a TLS encrypted and authenticated email"
	stage_exec swaks -to "$_email" -server "$_server" -timeout 50 \
		-tls -au "$_email" -ap "$_pass" || exit

	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs monitor
start_staged_jail monitor
install_monitor
configure_monitor
start_monitor
test_monitor
promote_staged_jail monitor
