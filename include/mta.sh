#!/bin/sh

configure_mta()
{
	local _base=${1:-""}
	local _mta=${2:-"$TOASTER_BASE_MTA"}

	if [ "$_mta" = "dma" ] && [ -x "$_base/usr/libexec/dma" ]; then
		disable_sendmail
		enable_dma
	elif [ "$_mta" = "sendmail" ]; then
		enable_sendmail
	elif [ -x "$_base/usr/libexec/dma" ]; then
		disable_sendmail
		enable_dma
	else
		disable_sendmail
		install_ssmtp
	fi
}

enable_sendmail()
{
	sysrc -f "$_base/etc/rc.conf" sendmail_enable=YES sendmail_outbound_enable=YES

	if jail_is_running stage; then
		stage_exec service sendmail start
	else
		service sendmail start
	fi

	set_root_alias

	cp "$_base/usr/share/examples/sendmail/mailer.conf" "$_base/etc/mail/mailer.conf"
}

disable_sendmail()
{
	if jail_is_running stage; then
		if pgrep -j stage sendmail; then stage_exec service sendmail onestop; fi
	else
		if pgrep -j none sendmail; then service sendmail onestop; fi
	fi

	sysrc -f "$_base/etc/rc.conf" sendmail_enable=NONE sendmail_outbound_enable=NONE
}

set_root_alias()
{
	local _aliases="$_base/etc/mail/aliases"

	if grep -q my.domain "$_aliases"; then
		tell_status "setting root email in $_aliases to $TOASTER_ADMIN_EMAIL"

		sed -i '' \
			-e "/^# root:/ s/^# //" \
			-e "/^root/ s/me@my.domain/$TOASTER_ADMIN_EMAIL/" \
			"$_aliases"
	fi
}

enable_dma()
{
	tell_status "setting up dma"
	cp "$_base/usr/share/examples/dma/mailer.conf" "$_base/etc/mail/mailer.conf"

	echo "dma.conf: $_base/etc/dma/dma.conf"
	sed -i '' \
		-e "s/^#SMARTHOST/SMARTHOST $TOASTER_MSA/" \
		"$_base/etc/dma/dma.conf"

	set_root_alias
}

install_ssmtp()
{
	tell_status "installing ssmtp"

	if jail_is_running stage; then
		stage_pkg_install ssmtp
	else
		pkg install ssmtp
	fi

	tell_status "configuring ssmtp"
	if [ ! -f "$_base/usr/local/etc/ssmtp/revaliases" ]; then
		cp "$_base/usr/local/etc/ssmtp/revaliases.sample" \
		   "$_base/usr/local/etc/ssmtp/revaliases"
	fi

	sed -e "/^root=/ s/postmaster/$TOASTER_ADMIN_EMAIL/" \
		-e "/^mailhub=/ s/=mail/=$TOASTER_MSA/" \
		-e "/^rewriteDomain=/ s/=\$/=$TOASTER_MAIL_DOMAIN/" \
		-e '/^#FromLineOverride=YES/ s/#//' \
		"$_base/usr/local/etc/ssmtp/ssmtp.conf.sample" \
		> "$_base/usr/local/etc/ssmtp/ssmtp.conf" || exit

	tee "$_base/etc/mail/mailer.conf" <<EO_MAILER_CONF
sendmail	/usr/local/sbin/ssmtp
send-mail	/usr/local/sbin/ssmtp
mailq		/usr/local/sbin/ssmtp
newaliases	/usr/local/sbin/ssmtp
hoststat	/usr/bin/true
purgestat	/usr/bin/true
EO_MAILER_CONF

}
