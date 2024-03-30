#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

_dkim_private_key="$ZFS_DATA_MNT/mailman/dkim/$TOASTER_MAIL_DOMAIN.private"
_has_dkim=""
if [ -f "$_dkim_private_key" ]; then _has_dkim=1; fi

install_mailman()
{
	install_postfix

	tell_status "installing mailman"
	stage_pkg_install py39-mailman sassc lynx nginx fcgiwrap || exit
	stage_exec chown -R mailman /usr/local/mailman
	stage_exec chpass -s /bin/sh mailman

	if [ -n "$TOASTER_NRPE" ]; then
		tell_status "installing nagios-plugins"
		stage_pkg_install nagios-plugins || exit
	fi

	tell_status "installing mailman web"
	stage_pkg_install py39-pip rust || exit
	stage_exec pip install postorius hyperkitty mailman-hyperkitty whoosh mailmanclient mailman-web || exit

	_mmhk_pkg="mailman-hyperkitty-1.2.1.tar.gz"
	if [ ! -d "$ZFS_DATA_MNT/$_mmhk_pkg" ]; then
		tell_status "installing mailman-hyperkitty"
		stage_exec fetch -o /data -m "https://files.pythonhosted.org/packages/41/77/352f7f8d1843cd7217d5dffce54fabdfdb403e78870db781c4859a8e9e35/$_mmhk_pkg"
		stage_exec tar -C /data -xvf "/data/$_mmhk_pkg"
	fi

	tell_status "installing hyperkitty"
	tell_status "installing postorius"
	tell_status "installing mailman-suite"
}

install_postfix()
{
	tell_status "installing postfix"
	stage_pkg_install postfix-sasl opendkim portconfig || exit
}

configure_mailman()
{
	configure_opendkim
	configure_postfix
	
	tell_status "configuring mailman"
	stage_sysrc mailman_enable=YES
	stage_sysrc nginx_enable=YES
	stage_sysrc uwsgi_enable=YES
	stage_sysrc uwsgi_socket_owner="www:mailman"
	stage_sysrc fcgiwrap_enable=YES
	stage_sysrc fcgiwrap_socket_owner=www

	_mm_etc="usr/local/mailman/etc"
	if [ -f "$ZFS_JAIL_MNT/mailman/$_mm_etc/mailman.cfg" ]; then
		tell_status "preserving /$_mm_etc/mailman.cfg"
		cp "$ZFS_JAIL_MNT/mailman/$_mm_etc/mailman.cfg" "$STAGE_MNT/$_mm_etc/"
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
		-e '/^Socket/ s/inet:port@localhost/inet:8891/' \
		-e "/^Selector/ s/my-selector-name/$(date '+%b%Y' | tr '[:upper:]' '[:lower:]')/" \
		"$STAGE_MNT/usr/local/etc/mail/opendkim.conf.sample" \
		> "$STAGE_MNT/data/etc/opendkim.conf"
}

configure_postfix()
{
	stage_sysrc postfix_enable=YES
	stage_exec postconf -e "myhostname = mailman.$TOASTER_HOSTNAME"
	stage_exec postconf -e 'smtp_tls_security_level = may'
	stage_exec postconf -e "mynetworks = ${JAIL_NET_PREFIX}.0${JAIL_NET_MASK}"
	stage_exec postconf -e 'owner_request_special=no'
	stage_exec postconf -e 'transport_maps=hash:/usr/local/mailman/data/postfix_lmtp'
	stage_exec postconf -e 'local_recipient_maps=hash:/usr/local/mailman/data/postfix_lmtp'
	stage_exec postconf -e 'relay_domains=hash:/usr/local/mailman/data/postfix_domains'

	if [ -f "$ZFS_DATA_MNT/etc/sasl_passwd" ]; then
		stage_exec postmap /data/etc/sasl_passwd
		stage_exec postconf -e 'smtp_sasl_auth_enable = yes'
		stage_exec postconf -e 'smtp_sasl_password_maps = hash:/data/etc/sasl_passwd'
	fi

	if [ -n "$TOASTER_NRPE" ]; then
		stage_sysrc nrpe3_enable=YES
		stage_sysrc nrpe3_configfile="/data/etc/nrpe.cfg"
	fi

	for _f in master main
	do
		if [ -f "$ZFS_DATA_MNT/postfix/etc/$_f.cf" ]; then
			tell_status "preserving /usr/local/etc/postfix/$_f.cf"
			cp "$ZFS_DATA_MNT/postfix/etc/$_f.cf" "$STAGE_MNT/usr/local/etc/postfix/"
		fi
	done

	if [ -f "$ZFS_JAIL_MNT/mailman/etc/aliases" ]; then
		tell_status "preserving /etc/aliases"
		cp "$ZFS_JAIL_MNT/mailman/etc/aliases" "$STAGE_MNT/etc/aliases"
		stage_exec newaliases
	fi

	if [ ! -f "$ZFS_JAIL_MNT/mailman/usr/local/etc/mail/mailer.conf" ]; then
		if [ ! -d "$ZFS_JAIL_MNT/mailman/usr/local/etc/mail" ]; then
			mkdir -p "$ZFS_JAIL_MNT/mailman/usr/local/etc/mail"
		fi
		stage_exec install -m 0644 /usr/local/share/postfix/mailer.conf.postfix /usr/local/etc/mail/mailer.conf
	fi
}

start_mailman()
{
	if [ -n "$_has_dkim" ]; then
		stage_exec service milter-opendkim start
	fi

	start_postfix

	tell_status "starting mailman"
	stage_exec service fcgiwrap start || exit
	stage_exec service nginx start || exit
	stage_exec service mailman start || exit
}

start_postfix()
{
	tell_status "starting postfix"
	stage_exec service postfix start || exit
}

test_mailman()
{
	tell_status "testing mailman"
	stage_listening 8001
	echo "it worked."

	test_postfix
	test_http
}

test_http()
{
	tell_status "testing postfix"
	stage_test_running master
	stage_listening 25
	echo "it worked."
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
create_staged_fs mailman
start_staged_jail mailman
install_mailman
configure_mailman
start_mailman
test_mailman
promote_staged_jail mailman
