#!/bin/sh

set -e -u

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

_dkim_private_key="$ZFS_DATA_MNT/postfix/dkim/$TOASTER_MAIL_DOMAIN.private"

install_postfix()
{
	tell_status "installing postfix"
	stage_pkg_install postfix-sasl opendkim

	if [ -n "$TOASTER_NRPE" ]; then
		tell_status "installing nagios-plugins"
		stage_pkg_install nrpe nagios-plugins
	fi
}

configure_opendkim()
{
	stage_sysrc milteropendkim_enable=YES
	stage_sysrc milteropendkim_cfgfile=/data/etc/opendkim.conf

	tell_status "See http://www.opendkim.org/opendkim-README"

	if [ ! -d "$STAGE_MNT/data/etc" ]; then mkdir "$STAGE_MNT/data/etc"; fi
	if [ ! -d "$STAGE_MNT/data/dkim" ]; then mkdir "$STAGE_MNT/data/dkim"; fi

	if [ -f "$STAGE_MNT/data/etc/opendkim.conf" ]; then
		tell_status "preserving opendkim config"
	else
		tell_status "configuring opendkim"
		sed \
			-e "/^Domain/ s/example.com/$TOASTER_MAIL_DOMAIN/"  \
			-e "/^KeyFile/ s/\/.*$/\/data\/dkim\/$TOASTER_MAIL_DOMAIN.private/"  \
			-e '/^Socket/ s/inet:port@localhost/inet:8891/' \
			-e "/^Selector/ s/my-selector-name/$(date '+%b%Y' | tr '[:upper:]' '[:lower:]')/" \
			"$STAGE_MNT/usr/local/etc/mail/opendkim.conf.sample" \
			> "$STAGE_MNT/data/etc/opendkim.conf"
	fi
}

configure_postfix_main_cf()
{
	local _main_cf="$ZFS_DATA_MNT/postfix/etc/main.cf"
	if [ -f "$_main_cf" ]; then
		tell_status "preserving $_main_cf"
		return
	fi

	stage_exec install -m 0644 /usr/local/etc/postfix/main.cf /data/etc/main.cf
	stage_exec postconf -e "myhostname = postfix.$TOASTER_HOSTNAME"
	stage_exec postconf -e 'smtp_tls_security_level = may'
	stage_exec postconf -e 'smtpd_tls_security_level = may'
	stage_exec postconf -e 'smtpd_tls_auth_only = yes'
	stage_exec postconf -e 'lmtp_tls_security_level = may'
	stage_exec postconf -e 'lmtpd_tls_security_level = may'
	stage_exec postconf -e "mynetworks = ${JAIL_NET_PREFIX}.0${JAIL_NET_MASK}"

	if [ -f "$ZFS_DATA_MNT/postfix/etc/sasl_passwd" ]; then
		stage_exec postmap /data/etc/sasl_passwd
		stage_exec postconf -e 'smtp_sasl_auth_enable = yes'
		stage_exec postconf -e 'smtp_sasl_password_maps = hash:/data/etc/sasl_passwd'
	fi

	if [ -f "$ZFS_DATA_MNT/postfix/etc/transport" ]; then
		stage_exec postmap /data/etc/transport
		stage_exec postconf -e 'transport_maps = hash:/data/etc/transport'
	fi

	if [ -f "$_dkim_private_key" ]; then
		stage_exec postconf -e 'smtpd_milters = inet:localhost:8891'
		stage_exec postconf -e 'non_smtpd_milters = $smtpd_milters'
	fi
}

configure_postfix_master_cf()
{
	local _master_cf="$ZFS_DATA_MNT/postfix/etc/master.cf"
	if [ -f "$_master_cf" ]; then
		tell_status "preserving $_master_cf"
	else
		tell_status "installing $_master_cf"
		stage_exec install -m 0644 /usr/local/etc/postfix/master.cf /data/etc/master.cf
	fi
}

configure_postfix()
{
	stage_sysrc sendmail_enable=NONE
	stage_sysrc postfix_enable=YES
	stage_sysrc postfix_flags="-c /data/etc"

	if [ -d "$ZFS_DATA_MNT/spool" ]; then
		stage_sysrc postfix_pidfile=/data/spool/pid/master.pid
	fi

	configure_postfix_main_cf
	configure_postfix_master_cf

	# postconf will break symlinks to files. To get all of postfix to always
	# look at /data/etc for config, symlink the config dir
	stage_exec mv /usr/local/etc/postfix /usr/local/etc/postfix.dist
	stage_exec ln -s /data/etc /usr/local/etc/postfix

	if [ -n "$TOASTER_NRPE" ]; then
		stage_sysrc nrpe_enable=YES
		stage_sysrc nrpe_configfile="/data/etc/nrpe.cfg"
	fi

	configure_opendkim

	preserve_file postfix '/etc/mail/aliases'
	stage_exec /usr/local/bin/newaliases

	stage_exec install -m 0644 /usr/local/share/postfix/mailer.conf.postfix /data/etc/mailer.conf
}

start_postfix()
{
	tell_status "starting postfix"
	if [ -f "$_dkim_private_key" ]; then
		stage_exec service milter-opendkim start
	fi
	if [ -d "$ZFS_DATA_MNT/spool/pid/master.pid" ]; then
		jexec postfix service postfix start
	fi
	stage_exec service postfix start
}

test_postfix()
{
	if [ -f "$_dkim_private_key" ]; then
		tell_status "testing opendkim"
		stage_test_running opendkim
		stage_listening 8891
	fi

	tell_status "testing postfix"
	stage_test_running master
	stage_listening 25
	echo "it worked."
}

base_snapshot_exists || exit 1
create_staged_fs postfix
start_staged_jail postfix
install_postfix
configure_postfix
start_postfix
test_postfix
promote_staged_jail postfix
