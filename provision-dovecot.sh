#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/vpopmail \$path/usr/local/vpopmail nullfs rw 0 0\";"

install_dovecot()
{
	tell_status "installing dovecot v2 package"
	stage_pkg_install dovecot2 || exit

	tell_status "configure dovecot for vpopmail"
	stage_make_conf dovecot2_SET 'mail_dovecot2_SET=VPOPMAIL LIBWRAP EXAMPLES'
	stage_exec pw groupadd -n vpopmail -g 89
	stage_exec pw useradd -n vpopmail -s /nonexistent -d /usr/local/vpopmail -u 89 -g 89 -m -h-

	stage_exec mkdir -p /var/qmail
	stage_exec ln -s /usr/local/vpopmail/qmail-users /var/qmail/users
	stage_exec ln -s /usr/local/vpopmail/qmail-control /var/qmail/control

	if [ "$TOASTER_MYSQL" = "1" ]; then
		stage_pkg_install mysql56-client
	fi

	tell_status "building dovecot with vpopmail"
	stage_pkg_install dialog4ports
	export BATCH=${BATCH:="1"}
	stage_exec make -C /usr/ports/mail/dovecot2 deinstall install clean || exit
}

configure_dovecot()
{
	tell_status "configuring dovecot"
	local _dcdir="$STAGE_MNT/usr/local/etc/dovecot"
	tee "$_dcdir/local.conf" <<'EO_DOVECOT_LOCAL'
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

	sed -i -e 's/^#listen = \*, ::/listen = \*/' "$_dcdir/dovecot.conf" || exit

	tell_status "switching auth from system to vpopmail"
	sed -i .bak \
		-e 's/^\!include auth-system/#\!include auth-system/' \
		-e 's/^#\!include auth-vpopmail/\!include auth-vpopmail/' \
		"$_dcdir/conf.d/10-auth.conf" || exit

	tell_status "installing dovecot TLS certificates"
	cp -R "$_dcdir/example-config/" "$_dcdir/" || exit
	cp /etc/ssl/certs/server.crt \
		"$STAGE_MNT/etc/ssl/certs/dovecot.pem" || exit
	cp /etc/ssl/private/server.key \
		"$STAGE_MNT/etc/ssl/private/dovecot.pem" || exit

	tell_status "boosting TLS encryption strength"
	sed -i .bak \
		-e '/^#ssl_dh_parameters_length/ s/^#//; s/1024/2048/' \
		-e '/^#ssl_prefer_server_ciphers/ s/^#//; s/no/yes/' \
		-e '/^#ssl_cipher_list/ s/^#//; s/ALL:.*/ALL:!LOW:!SSLv2:!EXP:!aNull:!eNull::!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA'
		"$_dcdir/conf.d/10-ssl.conf"

	tell_status "generating a 2048 bit Diffie-Hellman params file"
	openssl dhparam -out "$STAGE_MNT/etc/ssl/private/dhparams.pem" 2048 || exit
	cat "$STAGE_MNT/etc/ssl/private/dhparams.pem" \
		>> "$STAGE_MNT/etc/ssl/private/dovecot.pem" || exit
}

start_dovecot()
{
    tell_status "starting dovecot"
	stage_sysrc dovecot_enable=YES
	stage_exec service dovecot start || exit
}

test_dovecot()
{
	stage_exec sockstat -l -4 | grep 143 || exit
}

base_snapshot_exists || exit
create_staged_fs dovecot
start_staged_jail dovecot
install_dovecot
configure_dovecot
start_dovecot
test_dovecot
promote_staged_jail dovecot
