#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_mailtest()
{
	tell_status "installing swaks"
	stage_pkg_install swaks p5-Net-SSLeay || exit 1
}

configure_mailtest()
{
	tell_status "configuring"
	echo "yes"
}

start_mailtest()
{
	tell_status "starting"
}

test_mailtest()
{
	tell_status "testing"

	local _email _server _pass
	_email="postmaster@$TOASTER_MAIL_DOMAIN"
	_server=$(get_jail_ip haraka)
	_pass=$(jexec vpopmail /usr/local/vpopmail/bin/vuserinfo -C "$_email")

	tell_status "sending an email to $_email"
	stage_exec swaks -from "$_email" -to "$_email" -server "$_server" -timeout 50 || exit 1

	tell_status "sending a TLS encrypted and authenticated email"
	stage_exec swaks -from "$_email" -to "$_email" -server "$_server" -timeout 50 \
		-tls -au "$_email" -ap "$_pass" || exit 1

	echo "it worked"
}

base_snapshot_exists || exit 1
create_staged_fs mailtest
start_staged_jail mailtest
install_mailtest
configure_mailtest
start_mailtest
test_mailtest
promote_staged_jail mailtest
