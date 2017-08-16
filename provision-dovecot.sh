#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/dovecot \$path/data nullfs rw 0 0\";
		mount += \"$ZFS_DATA_MNT/vpopmail \$path/usr/local/vpopmail nullfs rw 0 0\";"

mt6-include vpopmail

install_dovecot()
{
	tell_status "installing dovecot v2 package"
	stage_pkg_install dovecot2 || stage_pkg_install dovecot || exit

	tell_status "configure dovecot port options"
	stage_make_conf dovecot2_SET 'mail_dovecot2_SET=VPOPMAIL LIBWRAP EXAMPLES'
	stage_make_conf dovecot_SET 'mail_dovecot_SET=VPOPMAIL LIBWRAP EXAMPLES'

	install_qmail
	install_vpopmail_port

	tell_status "mounting shared vpopmail fs"
	mount_data vpopmail

	if [ "$TLS_LIBRARY" = "libressl" ]; then
		echo 'DEFAULT_VERSIONS+=ssl=libressl' >> "$STAGE_MNT/etc/make.conf"
	fi

	tell_status "building dovecot with vpopmail support"
	stage_pkg_install dialog4ports

	export BATCH=${BATCH:="1"}
	stage_port_install mail/dovecot || exit 1
}

configure_dovecot_local_conf() {
	local _localconf="$ZFS_DATA_MNT/dovecot/etc/local.conf"

	if [ -f "$_localconf" ]; then
		tell_status "preserving $_localconf"
		return
	fi

	tell_status "installing $_localconf"
	tee "$_localconf" <<'EO_DOVECOT_LOCAL'
#mail_debug = yes
auth_verbose=yes
auth_mechanisms = plain login digest-md5 cram-md5
auth_username_format = %Lu
disable_plaintext_auth = no
first_valid_gid = 89
first_valid_uid = 89
last_valid_gid = 89
last_valid_uid = 89
mail_privileged_group = 89
login_greeting = Mail Toaster (Dovecot) ready.
mail_plugins = $mail_plugins quota
protocols = imap pop3
service auth {
  unix_listener auth-client {
    mode = 0660
  }
  unix_listener auth-master {
    mode = 0600
  }
#  unix_listener /var/spool/postfix/private/auth {
#    # SASL for Postfix smtp-auth
#    mode = 0666
#  }
}

passdb {
  driver = vpopmail
}
userdb {
  driver = vpopmail
  args = quota_template=quota_rule=*:backend=%q
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

# default TLS certificate (no SNI)
ssl_cert = </data/etc/ssl/certs/dovecot.pem
ssl_key = </data/etc/ssl/private/dovecot.pem

# example TLS SNI (see https://wiki.dovecot.org/SSL/DovecotConfiguration)
#local_name mail.example.com {
#  ssl_cert = </data/etc/ssl/certs/mail.example.com.pem
#  ssl_key = </data/etc/ssl/private/mail.example.com.pem
#}

# sunset when dovecot 2.3 is in ports/pkg
# dovecot 2.2 generates dhparams on-the-fly
ssl_dh_parameters_length = 2048
# /sunset

# dovecot 2.3 will support a ssl_dh file
#ssl_dh = </etc/ssl/dhparams.pem

# recommended settings for high security (mid-2017)
ssl_prefer_server_ciphers = yes
ssl_cipher_list = AES128+EECDH:AES128+EDH
ssl_protocols = !SSLv2 !SSLv3

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

}

configure_example_config()
{
	local _dcdir="$ZFS_DATA_MNT/dovecot/etc"

	if [ -f "$_dcdir/dovecot.conf" ]; then
		tell_status "dovecot config files already present"
		return
	fi

	tell_status "installing example config files"
	cp -R "$STAGE_MNT/usr/local/etc/dovecot/example-config/" "$_dcdir/" || exit
	sed -i .bak \
		-e 's/^#listen = \*, ::/listen = \*/' \
		"$_dcdir/dovecot.conf" || exit
}

configure_system_auth()
{
	local _authconf="$ZFS_DATA_MNT/dovecot/etc/conf.d/10-auth.conf"
	if ! grep -qs '^!include auth\-system' "$_authconf"; then
		tell_status "system auth already disabled"
		return
	fi

	tell_status "disabling auth-system"
	sed -i .bak \
		-e '/^\!include auth-system/ s/\!/#!/' \
		"$_authconf" || exit
}

configure_vsz_limit()
{
	local _master="$ZFS_DATA_MNT/dovecot/etc/conf.d/10-master.conf"
	if grep -q ^default_vsz_limit "$_master"; then
		tell_status "vsz_limit already configured"
		return
	fi

	tell_status "bumping up default_vsz_limit 256 -> 384"
	sed -i .bak \
		-e '/^#default_vsz_limit/ s/#//; s/256/384/' \
		"$_master"
}

configure_tls_certs()
{
	local _sslconf="$ZFS_DATA_MNT/dovecot/etc/conf.d/10-ssl.conf"
	if grep -qs ^ssl_cert "$_sslconf"; then
		tell_status "removing ssl_cert from 10-ssl.conf"
		sed -i .bak \
			-e '/ssl_cert/ s/^s/#s/' \
			-e '/ssl_key/ s/^s/#s/' \
			"$_sslconf"
	fi

	local _localconf="$ZFS_DATA_MNT/dovecot/etc/local.conf"
	if grep -qs dovecot.pem "$_localconf"; then
		sed -i .bak \
			-e "/^ssl_cert/ s/dovecot/${TOASTER_MAIL_DOMAIN}/" \
			-e "/^ssl_key/ s/dovecot/${TOASTER_MAIL_DOMAIN}/" \
			"$_localconf"
	fi

	local _ssldir="$ZFS_DATA_MNT/dovecot/etc/ssl"
	if [ ! -d "$_ssldir/certs" ]; then
		mkdir -p "$_ssldir/certs" || exit
		chmod 644 "$_ssldir/certs" || exit
	fi

	if [ ! -d "$_ssldir/private" ]; then
		mkdir "$_ssldir/private" || exit
		chmod 644 "$_ssldir/private" || exit
	fi

	local _installed_crt="$_ssldir/certs/${TOASTER_MAIL_DOMAIN}.pem"
	if [ -f "$_installed_crt" ]; then
		tell_status "dovecot TLS certificates already installed"
		return
	fi

	tell_status "installing dovecot TLS certificates"
	cp /etc/ssl/certs/server.crt "$_ssldir/certs/${TOASTER_MAIL_DOMAIN}.pem" || exit
	cp /etc/ssl/private/server.key "$_ssldir/private/${TOASTER_MAIL_DOMAIN}.pem" || exit

}

configure_dovecot()
{
	local _dcdir="$ZFS_DATA_MNT/dovecot/etc"

	if [ ! -d "$_dcdir" ]; then
		tell_status "creating $_dcdir"
		echo "mkdir $_dcdir"
		mkdir "$_dcdir" || exit
	fi

	configure_dovecot_local_conf
	configure_example_config
	configure_system_auth
	configure_vsz_limit
	configure_tls_certs

	mkdir -p "$STAGE_MNT/var/spool/postfix/private"
}

start_dovecot()
{
	tell_status "starting dovecot"
	stage_sysrc dovecot_enable=YES
	stage_sysrc dovecot_config="/data/etc/dovecot.conf"
	stage_exec service dovecot start || exit
}

test_dovecot()
{
	tell_status "testing dovecot"
	stage_listening 143
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs dovecot
start_staged_jail dovecot
install_dovecot
configure_dovecot
start_dovecot
test_dovecot
unmount_data vpopmail
promote_staged_jail dovecot
