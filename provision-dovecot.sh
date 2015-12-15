#!/bin/sh

. mail-toaster.sh || exit

export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/vpopmail \$path/usr/local/vpopmail nullfs rw 0 0\";"

install_dovecot()
{
    stage_pkg_install dovecot2 || exit

    tell_status "configure for vpopmail"
    stage_make_conf dovecot2_SET 'mail_dovecot2_SET=VPOPMAIL LIBWRAP EXAMPLES'
    stage_exec pw groupadd -n vpopmail -g 89
    stage_exec pw useradd -n vpopmail -s /nonexistent -d /usr/local/vpopmail -u 89 -g 89 -m -h-

    stage_exec mkdir -p /var/qmail
    stage_exec ln -s /usr/local/vpopmail/qmail-users /var/qmail/users
    stage_exec ln -s /usr/local/vpopmail/qmail-control /var/qmail/control

    if [ "$TOASTER_MYSQL" = "1" ]; then
        stage_pkg_install mysql56-client
    fi

    stage_pkg_install dialog4ports
    export BATCH=${BATCH:="1"}
    stage_exec make -C /usr/ports/mail/dovecot2 deinstall install clean || exit
}

configure_dovecot()
{
    local _dcdir="$STAGE_MNT/usr/local/etc/dovecot"
    tee "$_dcdir/local.conf" <<'EO_DOVECOT_LOCAL'
listen = *
#mail_debug = yes
auth_mechanisms = plain login digest-md5 cram-md5
auth_username_format = %Lu
disable_plaintext_auth = no
first_valid_gid = 89
first_valid_uid = 89
last_valid_gid = 89
last_valid_uid = 89
login_greeting = Mail Toaster (Dovecot) ready.
mail_privileged_group = mail
mail_plugins = $mail_plugins quota
passdb {
  driver = vpopmail
}
protocols = imap pop3
service auth {
  unix_listener auth-client {
    mode = 0660
  }
  unix_listener auth-master {
    mode = 0600
  }
}

shutdown_clients = no
ssl_cert = </etc/ssl/certs/server.crt
ssl_key = </etc/ssl/private/server.key
userdb {
  driver = vpopmail
  # [quota_template=<template>] - %q expands to Maildir++ quota
  args = quota_template=quota_rule=*:backend=%q
}
verbose_proctitle = yes
protocol imap {
  imap_client_workarounds = delay-newmail  tb-extra-mailbox-sep
  mail_max_userip_connections = 45
  mail_plugins = $mail_plugins imap_quota
}
protocol pop3 {
  pop3_client_workarounds = outlook-no-nuls oe-ns-eoh
  pop3_uidl_format = %08Xu%08Xv
}

login_access_sockets = tcpwrap

service tcpwrap {
  unix_listener login/tcpwrap {
    mode = 0600
    user = $default_login_user
    group = $default_login_user
  }
  user = root
}
EO_DOVECOT_LOCAL

    cp -R "$_dcdir/example-config/" "$_dcdir/" || exit
    sed -i .bak -e 's/^#listen = \*, ::/listen = \*/' "$_dcdir/dovecot.conf"
    sed -i .bak -e 's/certs\/dovecot.pem/certs\/server.crt/' "$_dcdir/conf.d/10-ssl.conf"
    sed -i .bak -e 's/private\/dovecot.pem/private\/server.key/' "$_dcdir/conf.d/10-ssl.conf"
    sed -i .bak -e 's/^\!include auth-system/#\!include auth-system/' "$_dcdir/conf.d/10-auth.conf"
}

start_dovecot()
{
    stage_sysrc dovecot_enable=YES
    stage_exec service dovecot start || exit
}

test_dovecot()
{
    stage_exec sockstat -l -4 | grep 143 || exit
}

base_snapshot_exists || exit
create_staged_fs dovecot
stage_sysrc hostname=dovecot
start_staged_jail
install_dovecot
configure_dovecot
start_dovecot
test_dovecot
promote_staged_jail dovecot
