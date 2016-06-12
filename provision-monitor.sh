#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

install_monitor()
{
	tell_status "installing monitoring apps"
	stage_pkg_install nagios nrpe swaks p5-Net-SSLeay || exit
}

configure_monitor()
{
	tell_status "configuring monitor"
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
start_staged_jail
install_monitor
configure_monitor
start_monitor
test_monitor
promote_staged_jail monitor
