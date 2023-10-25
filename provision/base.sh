#!/bin/sh

. mail-toaster.sh || exit

ifconfig ${JAIL_NET_INTERFACE} 2>&1 | grep -q 'does not exist' && {
	echo; echo "ERROR: did you run 'provision host' yet?"; echo;
	exit 1
}

mt6-include shell

create_base_filesystem()
{
	if [ -e "$BASE_MNT/dev/null" ]; then
		echo "unmounting $BASE_MNT/dev"
		umount "$BASE_MNT/dev" || exit
	fi

	if zfs_filesystem_exists "$BASE_VOL"; then
		echo "$BASE_VOL already exists"
		return
	fi

	zfs_create_fs "$BASE_VOL"
}

freebsd_update()
{
	if [ ! -t 0 ]; then
		echo "No tty, can't update FreeBSD with freebsd-update"
		return
	fi

	tell_status "apply FreeBSD security updates to base jail"
	sed -i.bak -e 's/^Components.*/Components world/' "$BASE_MNT/etc/freebsd-update.conf"
	freebsd-update -b "$BASE_MNT" -f "$BASE_MNT/etc/freebsd-update.conf" fetch install
}

install_freebsd()
{
	if [ -f "$BASE_MNT/COPYRIGHT" ]; then
		echo "FreeBSD already installed"
		return
	fi

	if [ -n "$USE_BSDINSTALL" ]; then
		export BSDINSTALL_DISTSITE;
		BSDINSTALL_DISTSITE="$(freebsd_release_url_base)/$(uname -m)/$(uname -m)/$FBSD_REL_VER"
		bsdinstall jail "$BASE_MNT"
	else
		stage_fbsd_package base "$BASE_MNT"
	fi

	touch "$BASE_MNT/etc/fstab"
}

install_ssmtp()
{
	tell_status "installing ssmtp"
	stage_pkg_install ssmtp || exit

	tell_status "configuring ssmtp"
	cp "$BASE_MNT/usr/local/etc/ssmtp/revaliases.sample" \
	   "$BASE_MNT/usr/local/etc/ssmtp/revaliases" || exit

	sed -e "/^root=/ s/postmaster/$TOASTER_ADMIN_EMAIL/" \
		-e "/^mailhub=/ s/=mail/=$TOASTER_MSA/" \
		-e "/^rewriteDomain=/ s/=\$/=$TOASTER_MAIL_DOMAIN/" \
		-e '/^#FromLineOverride=YES/ s/#//' \
		"$BASE_MNT/usr/local/etc/ssmtp/ssmtp.conf.sample" \
		> "$BASE_MNT/usr/local/etc/ssmtp/ssmtp.conf" || exit

	tee "$BASE_MNT/etc/mail/mailer.conf" <<EO_MAILER_CONF
sendmail	/usr/local/sbin/ssmtp
send-mail	/usr/local/sbin/ssmtp
mailq		/usr/local/sbin/ssmtp
newaliases	/usr/local/sbin/ssmtp
hoststat	/usr/bin/true
purgestat	/usr/bin/true
EO_MAILER_CONF
}

configure_syslog()
{
	tell_status "forwarding syslog to host"
	tee "$BASE_MNT/etc/syslog.conf" <<EO_SYSLOG
*.*			@syslog
EO_SYSLOG

	disable_newsyslog
}

disable_newsyslog()
{
	tell_status "disabling newsyslog"
	sysrc -f "$BASE_MNT/etc/rc.conf" newsyslog_enable=NO
	sed -i.bak \
		-e '/^0.*newsyslog/ s/^0/#0/' \
		"$BASE_MNT/etc/crontab"
}

disable_syslog()
{
	tell_status "disabling syslog"
	sysrc -f "$BASE_MNT/etc/rc.conf" syslogd_enable=NO
	disable_newsyslog
}

disable_root_password()
{
	if ! grep -q '^root::' "$BASE_MNT/etc/master.passwd"; then
		return
	fi

	# prevent a nightly email notice about the empty root password
	tell_status "disabling passwordless root account"
	sed -i.bak -e 's/^root::/root:*:/' "$BASE_MNT/etc/master.passwd"
	stage_exec pwd_mkdb /etc/master.passwd || exit
}

disable_cron_jobs()
{
	if ! grep -q '^1.*adjkerntz' "$BASE_MNT/etc/crontab"; then
		tell_status "cron jobs already configured"
		return
	fi

	tell_status "disabling adjkerntz, save-entropy, & atrun"
	# nobody uses atrun, safe-entropy is done by the host, and
	# the jail doesn't have permission to run adjkerntz.
	sed -i.bak \
		-e '/^1.*adjkerntz/ s/^1/#1/'  \
		-e '/^\*.*entropy/  s/^\*/#*/' \
		-e '/^\*.*atrun/    s/^\*/#*/' \
		"$BASE_MNT/etc/crontab" || exit

	echo "done"
}

enable_security_periodic()
{
	local _daily="$BASE_MNT/usr/local/etc/periodic/daily"
	if [ ! -d "$_daily" ]; then
		mkdir -p "$_daily"
	fi

	tell_status "setting up auto package security"
	tee "$_daily/auto_security_upgrades" <<'EO_PKG_SECURITY'
#!/bin/sh

auto_remove="vim-console vim-lite"
for _pkg in $auto_remove;
do
  /usr/sbin/pkg delete "$_pkg"
done

# packages to be updated automatically
auto_upgrade="curl expat libxml2 pkg sudo vim-tiny"

# add packages with:
#   sysrc -f /usr/local/etc/periodic/daily/auto_security_upgrades auto_upgrade+=" $NEW"

for _pkg in $auto_upgrade;
do
  /usr/sbin/pkg audit | grep "$_pkg" && pkg install -y "$_pkg"
done
EO_PKG_SECURITY
	chmod 755 "$_daily/auto_security_upgrades"
}

configure_ssl_dirs()
{
	if [ ! -d "$BASE_MNT/etc/ssl/certs" ]; then
		mkdir "$BASE_MNT/etc/ssl/certs"
	fi

	if [ ! -d "$BASE_MNT/etc/ssl/private" ]; then
		mkdir "$BASE_MNT/etc/ssl/private"
	fi

	chmod o-r "$BASE_MNT/etc/ssl/private"
}

configure_tls_dhparams()
{
	if [ -f "$BASE_MNT/etc/ssl/dhparam.pem" ]; then
		return
	fi

	local DHP="/etc/ssl/dhparam.pem"
	if [ ! -f "$DHP" ]; then
		# for upgrade compatibilty
		tell_status "Generating a 2048 bit $DHP"
		openssl dhparam -out "$DHP" 2048 || exit
	fi

	cp "$DHP" "$BASE_MNT/etc/ssl/dhparam.pem" || exit
}

configure_make_conf() {
	local _make="$BASE_MNT/etc/make.conf"
	if grep -qs WRKDIRPREFIX "$_make"; then
		return
	fi

	tell_status "setting base jail make.conf variables"
	tee -a "$_make" <<EO_MAKE_CONF
WITH_PKGNG=yes
WRKDIRPREFIX?=/tmp/portbuild
EO_MAKE_CONF
}

configure_fstab() {
	if [ ! -d "$BASE_MNT/data/etc" ]; then
		mkdir -p "$BASE_MNT/data/etc" || exit 1
	fi
	touch "$BASE_MNT/data/etc/fstab"
}

configure_base()
{
	if [ ! -d "$BASE_MNT/usr/ports" ]; then
		mkdir "$BASE_MNT/usr/ports" || exit
	fi

	tell_status "adding base jail resolv.conf"
	cp /etc/resolv.conf "$BASE_MNT/etc" || exit

	tell_status "setting base jail timezone (to hosts)"
	cp /etc/localtime "$BASE_MNT/etc" || exit

	configure_make_conf

	tell_status "adding base rc.conf settings"
	# shellcheck disable=2016
	sysrc -f "$BASE_MNT/etc/rc.conf" \
		hostname=base \
		cron_flags='$cron_flags -J 15' \
		syslogd_flags="-s -cc" \
		sendmail_enable=NONE \
		update_motd=NO

	configure_pkg_latest "$BASE_MNT"
	configure_ssl_dirs
	configure_tls_dhparams
	disable_cron_jobs
	enable_security_periodic
	configure_syslog
	configure_bourne_shell "$BASE_MNT"
	configure_csh_shell "$BASE_MNT"
	configure_fstab
}

install_periodic_conf()
{
	store_config "$BASE_MNT/etc/periodic.conf" "overwrite" <<EO_PERIODIC
# periodic.conf tuned for periodic inside jails
# increase the signal, decrease the noise

# some versions of FreeBSD bark b/c these are defined in
# /etc/defaults/periodic.conf and do not exist. Hush.
daily_local=""
weekly_local=""
monthly_local=""

# in case /etc/aliases isn't set up properly
daily_output="$TOASTER_ADMIN_EMAIL"
weekly_output="$TOASTER_ADMIN_EMAIL"
monthly_output="$TOASTER_ADMIN_EMAIL"

security_show_success="NO"
security_show_info="NO"
security_status_pkgaudit_enable="NO"
security_status_pkgaudit_quiet="YES"
security_status_tcpwrap_enable="YES"
daily_status_security_inline="NO"
weekly_status_security_inline="NO"
monthly_status_security_inline="NO"

# These are redundant within a jail
security_status_chkmounts_enable="NO"
security_status_chksetuid_enable="NO"
security_status_neggrpperm_enable="NO"
security_status_ipfwlimit_enable="NO"
security_status_ipfwdenied_enable="NO"
security_status_pfdenied_enable="NO"
security_status_kernelmsg_enable="NO"

daily_accounting_enable="NO"
daily_accounting_compress="YES"
daily_backup_gpart_enable="NO"
daily_backup_pkg_enable="NO"
daily_backup_pkgdb_enable="NO"
daily_backup_pkgng_enable="NO"
daily_clean_disks_enable="NO"
daily_clean_disks_verbose="NO"
daily_clean_hoststat_enable="NO"
daily_clean_tmps_enable="YES"
daily_clean_tmps_verbose="NO"
daily_news_expire_enable="NO"
daily_ntpd_leapfile_enable="NO"

daily_show_success="NO"
daily_show_info="NO"
daily_show_badconfig="YES"

daily_status_disks_enable="NO"
daily_status_include_submit_mailq="NO"
daily_status_mail_rejects_enable="NO"
daily_status_mailq_enable="NO"
daily_status_network_enable="NO"
daily_status_rwho_enable="NO"
daily_submit_queuerun="NO"

weekly_accounting_enable="NO"
weekly_show_success="NO"
weekly_show_info="NO"
weekly_show_badconfig="YES"
weekly_whatis_enable="NO"

monthly_accounting_enable="NO"
monthly_show_success="NO"
monthly_show_info="NO"
monthly_show_badconfig="YES"
EO_PERIODIC
}

install_vimrc()
{
	tell_status "installing a jail-wide vimrc"
	local _vimdir="$BASE_MNT/usr/local/etc/vim"
	if [ ! -d "$_vimdir" ]; then
		mkdir -p "$_vimdir" || exit
	fi

	fetch -m -o "$_vimdir/vimrc" https://raw.githubusercontent.com/nandalopes/vim-for-server/main/vimrc
	sed -i '' \
		-e 's/^syntax on/" syntax on/' \
		-e 's/^colorscheme/" colorscheme/' \
		-e 's/^set number/" set number/' \
		-e 's/^set relativenumber/" set relativenumber/' \
		"$_vimdir/vimrc"
}

install_base()
{
	tell_status "installing packages desired in every jail"
	stage_pkg_install pkg vim-tiny ca_root_nss || exit

	stage_exec newaliases

	if [ "$BOURNE_SHELL" = "bash" ]; then
		install_bash "$BASE_MNT"
	elif [ "$BOURNE_SHELL" = "zsh" ]; then
		install_zsh
		configure_zsh_shell "$BASE_MNT"
	fi

	install_ssmtp
	disable_root_password
	install_periodic_conf
	install_vimrc

	tell_status "updating packages in base jail"
	stage_exec pkg upgrade -y
}

zfs_snapshot_exists "$BASE_SNAP" && exit 0
jail -r stage 2>/dev/null
create_base_filesystem
install_freebsd
freebsd_update
configure_base
start_staged_jail base "$BASE_MNT" || exit
install_base
stop_jail stage
umount "$BASE_MNT/dev"
rm -rf "$BASE_MNT/var/cache/pkg/*"
rm -rf "$BASE_MNT/var/db/freebsd-update/*"
echo "zfs snapshot ${BASE_SNAP}"
zfs snapshot "${BASE_SNAP}" || exit
add_jail_conf base

proclaim_success base
