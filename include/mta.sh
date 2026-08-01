#!/bin/sh

configure_mta()
{
	local _base=${1:-""}
	local _mta=${2:-"$TOASTER_BASE_MTA"}

	if [ "$_mta" = "dma" ]; then
		disable_sendmail
		enable_dma
	elif [ "$_mta" = "sendmail" ]; then
		enable_sendmail
	elif [ "$_mta" = "postfix" ]; then
		disable_sendmail
		enable_postfix
	elif has_dma; then
		disable_sendmail
		enable_dma
	else
		disable_sendmail
		install_ssmtp
	fi
}

has_dma()
{
	if [ -x "$_base/usr/libexec/dma" ] || [ -x "$_base/usr/local/libexec/dma" ]; then
		return 0
	else
		return 1
	fi
}

enable_sendmail()
{
	local _sysrc="sysrc -f $_base/etc/rc.conf"

	if [ "$($_sysrc -n sendmail_enable)" != "YES" ]; then
		$_sysrc sendmail_enable=YES
	fi

	if [ "$($_sysrc -n sendmail_outbound_enable)" != "YES" ]; then
		$_sysrc sendmail_outbound_enable=YES
	fi

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

	local _sysrc="sysrc -f $_base/etc/rc.conf"

	if [ "$($_sysrc -n sendmail_enable)" != "NONE" ]; then
		$_sysrc sendmail_enable=NONE
	fi

	if [ "$($_sysrc -n sendmail_outbound_enable)" != "NO" ]; then
		$_sysrc sendmail_outbound_enable=NO
	fi

	local _periodic="sysrc -f $_base/etc/periodic.conf"
	for _c in daily_clean_hoststat_enable daily_status_mail_rejects_enable daily_status_include_submit_mailq daily_submit_queuerun
	do
		if [ "$($_periodic -i -n "$_c")" != "NO" ]; then $_periodic "$_c=NO"; fi
	done
}

set_root_alias()
{
	local _aliases="$_base/etc/mail/aliases"

	if grep -q my.domain "$_aliases"; then
		tell_status "setting root email in $_aliases to $TOASTER_ADMIN_EMAIL"

		sed_inplace \
			-e "/^# root:/ s/^# //" \
			-e "/^root/ s/me@my.domain/$TOASTER_ADMIN_EMAIL/" \
			"$_aliases"
	fi
}

enable_dma()
{
	local _dma_path="$_base/usr/local/libexec/dma"

	if [ ! -x "$_dma_path" ]; then _dma_path="$_base/usr/libexec/dma"; fi
	if [ ! -x "$_dma_path" ]; then
		stage_pkg_install dma
		_dma_path="$_base/usr/local/libexec/dma"
	fi

	tell_status "pointing mailer.conf at dma"
	_relative_path="${_dma_path#"$_base"}"
	tee "$_base/etc/mail/mailer.conf" <<EO_MAILER_CONF
sendmail        $_relative_path
mailq           $_relative_path
newaliases      $_relative_path
EO_MAILER_CONF

	tell_status "configuring dma"
	echo "editing $_base/etc/dma/dma.conf"
	tee "$_base/etc/dma/dma.conf" <<EO_DMA_CONF
SMARTHOST $TOASTER_MSA
MAILNAME $TOASTER_HOSTNAME
NULLCLIENT
EO_DMA_CONF

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

enable_postfix()
{
	tell_status "setting up postfix"
	cp "$_base/usr/local/share/postfix/mailer.conf.postfix" "$_base/etc/mail/mailer.conf"

	set_root_alias

	stage_pkg_install postfix
	stage_sysrc postfix_enable=YES
	stage_exec /usr/local/bin/newaliases
	stage_exec service postfix start
}
