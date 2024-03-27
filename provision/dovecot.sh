#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA="allow.sysvipc=1"
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB="$ZFS_DATA_MNT/vpopmail/home $ZFS_JAIL_MNT/dovecot/usr/local/vpopmail nullfs rw 0 0"

mt6-include vpopmail
mt6-include mua

allow_sysvipc_stage()
{
    tell_status "allow sysvipc for the staged jail"
    jail -m name=stage allow.sysvipc=1
}

install_dovecot()
{
	tell_status "installing dovecot package"
	stage_pkg_install dovecot dovecot-pigeonhole curl perl5 gmake mysql80-client

	tell_status "configure dovecot port options"
	stage_make_conf dovecot2_SET 'mail_dovecot2_SET=MYSQL LIBWRAP EXAMPLES'
	stage_make_conf dovecot_SET 'mail_dovecot_SET=MYSQL LIBWRAP EXAMPLES'

	tell_status "creating vpopmail user & group"
	stage_exec pw groupadd -n vpopmail -g 89
	stage_exec pw useradd -n vpopmail -s /nonexistent -d /usr/local/vpopmail -u 89 -g 89 -m -h-

	if [ "$TLS_LIBRARY" = "libressl" ]; then
		echo 'DEFAULT_VERSIONS+=ssl=libressl' >> "$STAGE_MNT/etc/make.conf"
	fi

	tell_status "building dovecot"

	export BATCH=${BATCH:="1"}
	stage_port_install mail/dovecot
	stage_port_install mail/dovecot-pigeonhole
}

configure_dovecot_local_conf() {
	local _localconf="$ZFS_DATA_MNT/dovecot/etc/local.conf"

	store_config "$_localconf" <<'EO_DOVECOT_LOCAL'
#mail_debug = yes
listen = *, ::
auth_verbose=yes
auth_mechanisms = plain login digest-md5 cram-md5 scram-sha-1 scram-sha-256
auth_username_format = %Lu
disable_plaintext_auth = no
first_valid_gid = 89
first_valid_uid = 89
last_valid_gid = 89
last_valid_uid = 89
mail_privileged_group = 89
login_greeting = Mail Toaster (Dovecot) ready.
mail_plugins = $mail_plugins quota
protocols = imap pop3 lmtp sieve
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

service lmtp {
  user = vpopmail
  inet_listener lmtp {
    port = 24
  }
  unix_listener lmtp {
    #mode = 0666
  }
}

passdb {
  driver = sql
  args = /data/etc/dovecot-sql.conf.ext
}
userdb {
  driver = prefetch
}
userdb {
  # This userdb is used only by lda.
  driver = sql
  args = /data/etc/dovecot-sql.conf.ext
}

shutdown_clients = no
verbose_proctitle = yes
protocol imap {
  imap_client_workarounds = delay-newmail  tb-extra-mailbox-sep
  mail_max_userip_connections = 45
  mail_plugins = $mail_plugins imap_quota trash imap_sieve
}
protocol pop3 {
  pop3_client_workarounds = outlook-no-nuls oe-ns-eoh
  pop3_uidl_format = %08Xu%08Xv
}
protocol lmtp {
  mail_fsync = optimized
  mail_plugins = $mail_plugins sieve
}

# default TLS certificate (no SNI)
ssl_cert = </data/etc/ssl/certs/dovecot.pem
ssl_key = </data/etc/ssl/private/dovecot.pem

# example TLS SNI (see https://wiki.dovecot.org/SSL/DovecotConfiguration)
#local_name mail.example.com {
#  ssl_cert = </data/etc/ssl/certs/mail.example.com.pem
#  ssl_key = </data/etc/ssl/private/mail.example.com.pem
#}

# dovecot 2.3+ supports a ssl_dh file
ssl_dh = </etc/ssl/dhparam.pem

# recommended settings for high security (2019)
ssl_prefer_server_ciphers = yes
ssl_cipher_list = AES128+EECDH:AES128+EDH

login_access_sockets = tcpwrap

service tcpwrap {
  unix_listener login/tcpwrap {
    mode = 0600
    user = $default_login_user
    group = $default_login_user
  }
  user = root
}
service managesieve-login {
  inet_listener sieve {
    port = 4190
  }
}
plugin {
  quota = maildir:User quota
  quota_rule = *:storage=1G
  quota_rule2 = Trash:storage=+10%%
  quota_rule3 = Spam:storage=+20%%

  sieve_plugins = sieve_imapsieve sieve_extprograms

  # From elsewhere to Junk, train as Spam
  imapsieve_mailbox1_name = Junk
  imapsieve_mailbox1_causes = COPY
  imapsieve_mailbox1_after  = file:/usr/local/lib/dovecot/sieve/report-spam.sieve

  # From elsewhere to Spam, train as Spam
  imapsieve_mailbox2_name = Spam
  imapsieve_mailbox2_causes = COPY
  imapsieve_mailbox2_after  = file:/usr/local/lib/dovecot/sieve/report-spam.sieve

  # From Junk to elsewhere, train as Ham
  imapsieve_mailbox3_name = *
  imapsieve_mailbox3_from = Junk
  imapsieve_mailbox3_causes = COPY
  imapsieve_mailbox3_after  = file:/usr/local/lib/dovecot/sieve/report-ham.sieve

  # From Spam to elsewhere, train as Ham
  imapsieve_mailbox4_name = *
  imapsieve_mailbox4_from = Spam
  imapsieve_mailbox4_causes = COPY
  imapsieve_mailbox4_after  = file:/usr/local/lib/dovecot/sieve/report-ham.sieve

  # From elsewhere to Archive, train as Ham
  imapsieve_mailbox5_name = Archive
  imapsieve_mailbox5_causes = COPY
  imapsieve_mailbox5_after  = file:/usr/local/lib/dovecot/sieve/report-ham.sieve

  sieve_pipe_bin_dir = /usr/local/lib/dovecot/sieve

  sieve_global_extensions = +vnd.dovecot.pipe
}

namespace inbox {
  mail_location = maildir:~/Maildir
  mailbox Spam {
    auto = no
    special_use = \Junk
  }
  mailbox Archive {
    special_use = \Archive
  }
}
EO_DOVECOT_LOCAL

}

configure_dovecot_sql_conf()
{
	local _localconf="$ZFS_DATA_MNT/dovecot/etc/local.conf"
	if grep -q -E 'driver[[:space:]]*=[[:space:]]*sql' $_localconf; then
		tell_status "passdb conversion to SQL already complete"
	else
		tell_status "converting dovecot passdb to SQL"
		jexec stage perl -i.bak -0777 -pe 's/passdb \{.*?\}/passdb {
  driver = sql
  args = \/data\/etc\/dovecot-sql.conf.ext
 }/sg;
 s/userdb \{.*?\}/userdb {
   driver = prefetch
 }
 userdb {
   # used only by lda.
   driver = sql
   args = \/data\/etc\/dovecot-sql.conf.ext
 }/sg' /data/etc/local.conf
	fi

	_localconf="$ZFS_DATA_MNT/dovecot/etc/dovecot-sql.conf.ext"
	if grep -q -E 'driver[[:space:]]*=[[:space:]]mysql' $_localconf; then
		tell_status "SQL configured."
	else
		tell_status "configuring SQL"
		local _sqlconf="$ZFS_DATA_MNT/dovecot/etc/dovecot-sql.conf.ext"

		# shellcheck disable=SC2034
		_vpass=$(grep -v ^# "$ZFS_DATA_MNT/vpopmail/home/etc/vpopmail.mysql" | head -n1 | cut -f4 -d'|')

		store_config "$_sqlconf" "overwrite" <<EO_DOVECOT_SQL
  driver = mysql
  default_pass_scheme = PLAIN
  connect = host=mysql user=vpopmail password=$_vpass dbname=vpopmail

  password_query = SELECT \\
    CONCAT(v.pw_name, '@', v.pw_domain) AS user \\
    ,v.pw_clear_passwd AS password \\
    ,v.pw_dir AS userdb_home \\
    ,89 AS userdb_uid \\
    ,89 AS userdb_gid \\
    ,CONCAT('*:bytes=', REPLACE(SUBSTRING_INDEX(v.pw_shell, 'S', 1), 'NOQUOTA', '0')) AS userdb_quota_rule \\
    FROM vpopmail v \\
      LEFT JOIN aliasdomains a ON a.alias='%d' \\
    WHERE v.pw_name = '%n' \\
      AND (v.pw_domain='%d' OR v.pw_domain=a.domain) \\
      AND ('%a'!='995' OR !(v.pw_gid & 2)) \\
      AND ('%a'!='993' OR !(v.pw_gid & 8))

  user_query = SELECT pw_dir as home \\
    ,89 AS uid ,89 AS gid \\
    ,CONCAT('*:bytes=', REPLACE(SUBSTRING_INDEX(pw_shell, 'S', 1), 'NOQUOTA', '0')) AS quota_rule \\
    FROM vpopmail \\
    WHERE pw_name = '%n' \\
      AND pw_domain = '%d'

  iterate_query = SELECT CONCAT(pw_name, '@', pw_domain) AS user FROM vpopmail
EO_DOVECOT_SQL
	fi
}

configure_example_config()
{
	local _dcdir="$ZFS_DATA_MNT/dovecot/etc"

	if [ -f "$_dcdir/dovecot.conf" ]; then
		tell_status "dovecot config files already present"
		return
	fi

	tell_status "installing example config files"
	cp -R "$STAGE_MNT/usr/local/etc/dovecot/example-config/" "$_dcdir/"
	sed -i.bak \
		-e 's/^#listen = \*, ::/listen = \*/' \
		"$_dcdir/dovecot.conf"
}

configure_system_auth()
{
	local _authconf="$ZFS_DATA_MNT/dovecot/etc/conf.d/10-auth.conf"
	if ! grep -qs '^!include auth\-system' "$_authconf"; then
		tell_status "system auth already disabled"
		return
	fi

	tell_status "disabling auth-system"
	sed -i.bak \
		-e '/^\!include auth-system/ s/\!/#!/' \
		"$_authconf"
}

configure_vsz_limit()
{
	local _master="$ZFS_DATA_MNT/dovecot/etc/conf.d/10-master.conf"
	if grep -q ^default_vsz_limit "$_master"; then
		tell_status "vsz_limit already configured"
		return
	fi

	tell_status "bumping up default_vsz_limit 256 -> 384"
	sed -i.bak \
		-e '/^#default_vsz_limit/ s/#//; s/256/384/' \
		"$_master"
}

configure_tls_certs()
{
	local _sslconf="$ZFS_DATA_MNT/dovecot/etc/conf.d/10-ssl.conf"
	if grep -qs ^ssl_cert "$_sslconf"; then
		tell_status "removing ssl_cert from 10-ssl.conf"
		sed -i.bak \
			-e '/ssl_cert/ s/^s/#s/' \
			-e '/ssl_key/ s/^s/#s/' \
			"$_sslconf"
	fi

	local _localconf="$ZFS_DATA_MNT/dovecot/etc/local.conf"
	if grep -qs dovecot.pem "$_localconf"; then
		sed -i.bak \
			-e "/^ssl_cert/ s/dovecot/${TOASTER_MAIL_DOMAIN}/" \
			-e "/^ssl_key/ s/dovecot/${TOASTER_MAIL_DOMAIN}/" \
			"$_localconf"
	fi

	local _ssldir="$ZFS_DATA_MNT/dovecot/etc/ssl"
	if [ ! -d "$_ssldir/certs" ]; then
		mkdir -p "$_ssldir/certs"
		chmod 644 "$_ssldir/certs"
	fi

	if [ ! -d "$_ssldir/private" ]; then
		mkdir "$_ssldir/private"
		chmod 644 "$_ssldir/private"
	fi

	local _installed_crt="$_ssldir/certs/${TOASTER_MAIL_DOMAIN}.pem"
	if [ -f "$_installed_crt" ]; then
		tell_status "dovecot TLS certificates already installed"
		return
	fi

	tell_status "installing dovecot TLS certificates"
	cp /etc/ssl/certs/server.crt "$_ssldir/certs/${TOASTER_MAIL_DOMAIN}.pem"
	# sunset after Dovecot 2.3 released
	cat /etc/ssl/dhparam.pem >> "$_ssldir/certs/${TOASTER_MAIL_DOMAIN}.pem"
	# /sunset
	cp /etc/ssl/private/server.key "$_ssldir/private/${TOASTER_MAIL_DOMAIN}.pem"
}

configure_postfix_with_sasl()
{
	# ignore this, it doesn't exist. Yet. Maybe not ever. It's one way to
	# configure a MSA with dovecot auth.
	stage_pkg_install postfix

	stage_exec postconf -e "relayhost = $TOASTER_MSA"
	stage_exec postconf -e 'smtpd_sasl_type = dovecot'
	stage_exec postconf -e 'smtpd_sasl_path = private/auth'
	stage_exec postconf -e 'smtpd_sasl_auth_enable = yes'
	stage_exec postconf -e 'smtpd_recipient_restrictions = permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination'
	stage_exec postconf -e "smtpd_tls_cert_file = /data/etc/ssl/certs/$TOASTER_HOSTNAME.pem"
	stage_exec postconf -e "smtpd_tls_key_file = /data/etc/ssl/private/$TOASTER_HOSTNAME.pem"
	stage_exec postconf -e 'smtp_tls_security_level = may'

	for _s in 512 1024 2048; do
		openssl dhparam -out /tmp/dh$_s.tmp $_s
		chmod 644 /tmp/dh${_s}.tmp
		mv /tmp/dh${_s}.tmp "$STAGE_MNT/usr/local/etc/postfix/dh${_s}.pem"
		stage_exec postconf -e "smtpd_tls_dh${_s}_param_file = \${config_directory}/dh${_s}.pem"
	done

	stage_sysrc postfix_enable="YES"
	stage_exec service postfix start
}

compile_sieve()
{
	stage_exec /usr/local/bin/sievec -c /data/etc/dovecot.conf "/usr/local/lib/dovecot/sieve/$1"
}

configure_sieve_report_ham()
{
	if [ -x "$SIEVE_DIR/report-ham.sieve" ]; then
		return
	fi

	store_config "$SIEVE_DIR/report-ham.sieve" <<'EO_REPORT_HAM'
require ["vnd.dovecot.pipe", "copy", "imapsieve", "environment", "variables"];

if environment :matches "imap.mailbox" "*" {
  set "mailbox" "${1}";
}

if string "${mailbox}" "Trash" {
  stop;
}

if environment :matches "imap.user" "*" {
  set "username" "${1}";
}

EO_REPORT_HAM
}

configure_sieve_report_spam()
{
	if [ -x "$SIEVE_DIR/report-spam.sieve" ]; then
		return
	fi

	store_config "$SIEVE_DIR/report-spam.sieve" <<'EO_REPORT_SPAM'
# https://wiki2.dovecot.org/Pigeonhole/Sieve
require ["vnd.dovecot.pipe", "copy", "imapsieve", "environment", "variables"];

if environment :matches "imap.user" "*" {
  set "username" "${1}";
}

EO_REPORT_SPAM
}

configure_sieve_learn_rspamd()
{
	if ! grep ^jail_list /etc/rc.conf | grep -q rspamd; then
		echo "skip rspamd learning: it is not enabled"
		return
	fi

	tell_status "adding learn-ham-rspamd.sh"
	tee "$SIEVE_DIR/learn-ham-rspamd.sh" <<EO_RSPAM_LEARN_HAM
exec /usr/local/bin/curl -s -S -XPOST --data-binary @- http://$(get_jail_ip rspamd):11334/learnham
EO_RSPAM_LEARN_HAM
	chmod +x "$SIEVE_DIR/learn-ham-rspamd.sh"

	if ! grep rspamd "$SIEVE_DIR/report-ham.sieve"; then
		tell_status "enabling rspamd learning in report-ham.sieve"
		tee -a "$SIEVE_DIR/report-ham.sieve" <<'EO_REPORT_HAM_RSPAMD'
pipe :copy "learn-ham-rspamd.sh" [ "${username}" ];
EO_REPORT_HAM_RSPAMD
		compile_sieve report-ham.sieve
	fi

	tell_status "adding learn-spam-rspamd.sh"
	tee "$SIEVE_DIR/learn-spam-rspamd.sh" <<EO_RSPAM_LEARN_SPAM
exec /usr/local/bin/curl -s -S -XPOST --data-binary @- http://$(get_jail_ip rspamd):11334/learnspam
EO_RSPAM_LEARN_SPAM
	chmod +x "$SIEVE_DIR/learn-spam-rspamd.sh"

	if ! grep rspamd "$SIEVE_DIR/report-spam.sieve"; then
		tell_status "enabling rspamd learning in report-spam.sieve"
		tee -a "$SIEVE_DIR/report-spam.sieve" <<'EO_REPORT_SPAM_RSPAMD'
pipe :copy "learn-spam-rspamd.sh" [ "${username}" ];
EO_REPORT_SPAM_RSPAMD
		compile_sieve report-spam.sieve
	fi
}

configure_sieve_learn_spamassassin()
{
	if ! grep ^jail_list /etc/rc.conf | grep -q spamassassin; then
		echo "skip spamassassin learning: it is not enabled"
		return
	fi

	if [ ! -x "$ZFS_DATA_MNT/dovecot/bin/spamc" ]; then
		tell_status "copying spamc into /data/bin"
		cp "$ZFS_JAIL_MNT/spamassassin/usr/local/bin/spamc" \
			"$ZFS_DATA_MNT/dovecot/bin/spamc"
	fi

	tell_status "creating learn-ham-sa.sh"
	tee "$SIEVE_DIR/learn-ham-sa.sh" <<EO_RSPAM_LEARN_HAM
exec /data/bin/spamc -d $(get_jail_ip spamassassin) --learntype=ham -u \${1}
EO_RSPAM_LEARN_HAM
	chmod +x "$SIEVE_DIR/learn-ham-sa.sh"

	if ! grep learn-ham-sa "$SIEVE_DIR/report-ham.sieve"; then
		tell_status "enabling spamassassin learning in report-ham.sieve"
		tee -a "$SIEVE_DIR/report-ham.sieve" <<'EO_REPORT_HAM_SA'
pipe :copy "learn-ham-sa.sh" [ "${username}" ];
EO_REPORT_HAM_SA
		compile_sieve report-ham.sieve
	fi

	tell_status "creating learn-spam-sa.sh"
	tee "$SIEVE_DIR/learn-spam-sa.sh" <<EO_RSPAM_LEARN_SPAM
exec /data/bin/spamc -d $(get_jail_ip spamassassin) --learntype=spam -u \${1}
EO_RSPAM_LEARN_SPAM
	chmod +x "$SIEVE_DIR/learn-spam-sa.sh"

	if ! grep learn-spam-sa "$SIEVE_DIR/report-spam.sieve"; then
		tell_status "enabling spamassassin learning in report-spam.sieve"
		tee -a "$SIEVE_DIR/report-spam.sieve" <<'EO_REPORT_SPAM_SA'
pipe :copy "learn-spam-sa.sh" [ "${username}" ];
EO_REPORT_SPAM_SA
		compile_sieve report-spam.sieve
	fi
}

configure_sieve()
{
	SIEVE_DIR="$STAGE_MNT/usr/local/lib/dovecot/sieve"
	if [ ! -d "$SIEVE_DIR" ]; then
		mkdir "$SIEVE_DIR"
	fi

	local _lc="$ZFS_DATA_MNT/dovecot/etc/local.conf"
	if [ -f "$_lc" ] && ! grep -q sieve "$_lc"; then
		tell_status "sieve not configured. Update local.conf and reinstall dovecot to enable"
		return
	fi

	configure_sieve_report_ham
	configure_sieve_report_spam

	configure_sieve_learn_rspamd
	configure_sieve_learn_spamassassin
}

configure_dovecot_pf()
{
	_pf_etc="$ZFS_DATA_MNT/dovecot/etc/pf.conf.d"

	store_config "$_pf_etc/insecure_mua" <<EO_PF_INSECURE
# 10.0.0.0/8
# 172.16.0.0/12
# 192.168.0.0/16
EO_PF_INSECURE

	store_config "$_pf_etc/rdr.conf" <<EO_PF_RDR
int_ip4 = "$(get_jail_ip dovecot)"
int_ip6 = "$(get_jail_ip6 dovecot)"

# to permit legacy users to access insecure POP3 & IMAP, add their IPs/masks
table <insecure_mua> persist file "$_pf_etc/insecure_mua"

rdr inet  proto tcp from any to <ext_ip4> port { 993 995 } -> $int_ip4
rdr inet6 proto tcp from any to <ext_ip6> port { 993 995 } -> $int_ip6

rdr inet  proto tcp from <insecure_mua> to <ext_ip4> port { 110 143 } -> $int_ip4
rdr inet6 proto tcp from <insecure_mua> to <ext_ip6> port { 110 143 } -> $int_ip6
EO_PF_RDR

	store_config "$_pf_etc/allow.conf" <<EO_PF_RDR
int_ip4 = "$(get_jail_ip dovecot)"
int_ip6 = "$(get_jail_ip6 dovecot)"

table <dovecot_int> persist { \$int_ip4, \$int_ip6 }

pass in quick proto tcp from any to <ext_ip> port { 993 995 }
pass in quick proto tcp from any to <dovecot_int> port { 993 995 }

pass in quick proto tcp from <insecure_mua> to <dovecot_int> port { 110 143 }
EO_PF_RDR
}

configure_dovecot()
{
	for _d in etc bin; do
		local _dcdir="$ZFS_DATA_MNT/dovecot/${_d}"

		if [ ! -d "$_dcdir" ]; then
			tell_status "creating $_dcdir"
			echo "mkdir $_dcdir"
			mkdir "$_dcdir"
		fi
	done

	configure_dovecot_local_conf
	configure_example_config
	configure_dovecot_sql_conf
	configure_system_auth
	configure_vsz_limit
	configure_tls_certs
	configure_sieve
	configure_dovecot_pf

	mkdir -p "$STAGE_MNT/var/spool/postfix/private"
}

start_dovecot()
{
	tell_status "starting dovecot"
	stage_sysrc dovecot_enable=YES
	stage_sysrc dovecot_config="/data/etc/dovecot.conf"
	stage_exec service dovecot start
}

test_dovecot()
{
	tell_status "testing dovecot"
	stage_listening 993 3
	stage_listening 995 3

	MUA_TEST_USER="postmaster@${TOASTER_MAIL_DOMAIN}"
	MUA_TEST_PASS=$(jexec vpopmail /usr/local/vpopmail/bin/vuserinfo -C "${MUA_TEST_USER}")
	MUA_TEST_HOST=$(get_jail_ip stage)
	export MUA_TEST_HOST; export MUA_TEST_USER; export MUA_TEST_PASS

	test_imap
	test_pop3
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs dovecot
mkdir -p "$STAGE_MNT/usr/local/vpopmail"
start_staged_jail dovecot
allow_sysvipc_stage
install_dovecot
configure_dovecot
stage_resolv_conf
start_dovecot
test_dovecot
promote_staged_jail dovecot
