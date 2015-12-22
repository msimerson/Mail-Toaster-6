#!/bin/sh

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

    local _email="postmaster@$TOASTER_MAIL_DOMAIN"
    tell_status "sending an email to $_email"
    stage_exec swaks -to "$_email" -server "$(get_jail_ip haraka)" || exit

    tell_status "sending a TLS encrypted and authenticated email"
    local _pass
    _pass=$(jexec vpopmail /usr/local/vpopmail/bin/vuserinfo -C "$_email")
    stage_exec swaks -tls -to "$_email" -server "$(get_jail_ip haraka)" \
        -au "$_email" -ap "$_pass" || exit

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
