#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

_dkim_private_key="$ZFS_DATA_MNT/postfix/dkim/$TOASTER_MAIL_DOMAIN.private"
_has_dkim=""
if [ -f "$_dkim_private_key" ]; then _has_dkim=1; fi

install_postfix()
{
	tell_status "installing postfix"
	stage_pkg_install postfix-sasl opendkim || exit

	if [ -n "$TOASTER_NRPE" ]; then
		tell_status "installing nagios-plugins"
		stage_pkg_install nrpe nagios-plugins || exit
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
		echo "opendkim config retained"
		return
	fi

	sed \
		-e "/^Domain/ s/example.com/$TOASTER_MAIL_DOMAIN/"  \
		-e "/^KeyFile/ s/\/.*$/\/data\/dkim\/$TOASTER_MAIL_DOMAIN.private/"  \
		-e '/^Socket/ s/inet:port@localhost/inet:2016/' \
		-e "/^Selector/ s/my-selector-name/$(date '+%b%Y' | tr '[:upper:]' '[:lower:]')/" \
		"$STAGE_MNT/usr/local/etc/mail/opendkim.conf.sample" \
		> "$STAGE_MNT/data/etc/opendkim.conf"
}

configure_postfix()
{
	stage_sysrc postfix_enable=YES
	stage_exec postconf -e "myhostname = postfix.$TOASTER_HOSTNAME"
	stage_exec postconf -e 'smtp_use_tls=yes'
	stage_exec postconf -e 'smtp_tls_security_level = encrypt'
	stage_exec postconf -e 'smtp_tls_wrappermode = yes'
	stage_exec postconf -e "mynetworks = ${JAIL_NET_PREFIX}.0${JAIL_NET_MASK}"

	if [ -f "$ZFS_DATA_MNT/postfix/etc/sasl_passwd" ]; then
		stage_exec postmap /data/etc/sasl_passwd
		stage_exec postconf -e 'smtp_sasl_auth_enable = yes'
		stage_exec postconf -e 'smtp_sasl_password_maps = hash:/data/etc/sasl_passwd'
	fi

	if [ -n "$TOASTER_NRPE" ]; then
		stage_sysrc nrpe_enable=YES
		stage_sysrc nrpe_configfile="/data/etc/nrpe.cfg"
	fi

	if [ -f "$ZFS_DATA_MNT/postfix/etc/transport" ]; then
		stage_exec postmap /data/etc/transport
		stage_exec postconf -e 'transport_maps = hash:/data/etc/transport'
	fi

	for _f in master main
	do
		if [ -f "$ZFS_DATA_MNT/postfix/etc/$_f.cf" ]; then
			tell_status "preserving /usr/local/etc/postfix/$_f.cf"
			cp "$ZFS_DATA_MNT/postfix/etc/$_f.cf" "$STAGE_MNT/usr/local/etc/postfix/" || exit 1
		fi
	done

	if [ -f "$ZFS_JAIL_MNT/postfix/etc/aliases" ]; then
		tell_status "preserving /etc/aliases"
		cp "$ZFS_JAIL_MNT/postfix/etc/aliases" "$STAGE_MNT/etc/aliases"
		stage_exec /usr/bin/newaliases
	elif [ -f "$ZFS_DATA_MNT/postfix/etc/aliases" ]; then
		cp "$ZFS_DATA_MNT/postfix/etc/aliases" "$STAGE_MNT/etc/aliases"
		stage_exec /usr/bin/newaliases
	fi

	if [ ! -f "$ZFS_JAIL_MNT/usr/local/etc/mail/mailer.conf" ]; then
		if [ ! -d "$ZFS_JAIL_MNT/usr/local/etc/mail" ]; then
			mkdir "$ZFS_JAIL_MNT/usr/local/etc/mail" || exit 1
		fi
		stage_exec install -m 0644 /usr/local/share/postfix/mailer.conf.postfix /usr/local/etc/mail/mailer.conf
	fi

	configure_opendkim
}

start_postfix()
{
	tell_status "starting postfix"
	if [ -n "$_has_dkim" ]; then
		stage_exec service milter-opendkim start
	fi
	stage_exec service postfix start || exit
}

test_postfix()
{
	if [ -n "$_has_dkim" ]; then
		tell_status "testing opendkim"
		stage_test_running opendkim
		stage_listening 2016
	fi

	tell_status "testing postfix"
	stage_test_running master
	stage_listening 25
	echo "it worked."
}

base_snapshot_exists || exit
create_staged_fs postfix
start_staged_jail postfix
install_postfix
configure_postfix
start_postfix
test_postfix
promote_staged_jail postfix
