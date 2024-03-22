#!/bin/sh

set -e

. mail-toaster.sh

mt6-include shell
mt6-include mta
mt6-include editor

create_base_filesystem()
{
	if [ -e "$BASE_MNT/dev/null" ]; then
		echo "unmounting $BASE_MNT/dev"
		umount "$BASE_MNT/dev"
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

	echo "clearing freebsd-update cache"
	rm -rf $BASE_MNT/var/db/freebsd-update/*
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

	configure_fstab
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
	stage_exec pwd_mkdb /etc/master.passwd
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
		"$BASE_MNT/etc/crontab"

	echo "done"
}

enable_security_periodic()
{
	store_exec "$BASE_MNT/usr/local/etc/periodic/daily/auto_security_upgrades" <<'EO_PKG_SECURITY'
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
		openssl dhparam -out "$DHP" 2048
	fi

	cp "$DHP" "$BASE_MNT/etc/ssl/dhparam.pem"
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
	local _sub_dir=${1:-""}
	local _etc_path="$BASE_MNT/${_sub_dir}etc"
	if [ ! -d "$_etc_path" ]; then
		mkdir -p "$_etc_path"
	fi

	tee "$_etc_path/fstab" <<EO_FSTAB
# Device                Mountpoint      FStype  Options         Dump    Pass#
devfs                   $BASE_MNT/dev  devfs   rw              0       0
EO_FSTAB
}

configure_base()
{
	if [ ! -d "$BASE_MNT/usr/ports" ]; then
		mkdir "$BASE_MNT/usr/ports"
	fi

	tell_status "adding base jail resolv.conf"
	cp /etc/resolv.conf "$BASE_MNT/etc"

	tell_status "setting base jail timezone (to hosts)"
	cp /etc/localtime "$BASE_MNT/etc"

	configure_make_conf

	tell_status "adding base rc.conf settings"
	# shellcheck disable=2016
	sysrc -f "$BASE_MNT/etc/rc.conf" \
		hostname=base \
		cron_flags='$cron_flags -J 15' \
		syslogd_flags="-s -cc" \
		update_motd=NO

	configure_pkg_latest "$BASE_MNT"
	configure_ssl_dirs
	configure_tls_dhparams
	disable_cron_jobs
	enable_security_periodic
	configure_syslog
	configure_bourne_shell "$BASE_MNT"
	configure_csh_shell "$BASE_MNT"
	configure_fstab "data/"
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
security_status_chkuid0_enable="NO"
security_status_neggrpperm_enable="NO"
security_status_ipfdenied_enable="NO"
security_status_ipfwlimit_enable="NO"
security_status_ipfwdenied_enable="NO"
security_status_kernelmsg_enable="NO"
security_status_pfdenied_enable="NO"
security_status_tcpwrap_enable="NO"

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
weekly_locate_enable="NO"
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

install_base()
{
	tell_status "installing packages desired in every jail"
	stage_pkg_install $TOASTER_BASE_PKGS

	stage_exec newaliases

	if [ "$BOURNE_SHELL" = "bash" ]; then
		install_bash "$BASE_MNT"
	elif [ "$BOURNE_SHELL" = "zsh" ]; then
		install_zsh
		configure_zsh_shell "$BASE_MNT"
	fi

	configure_mta "$BASE_MNT"
	disable_root_password
	install_periodic_conf
	configure_editor "$BASE_MNT"

	tell_status "updating packages in base jail"
	stage_exec pkg upgrade -y
}

assure_jail_nic()
{
	tell_status "assure_jail_nic: $JAIL_NET_INTERFACE exists"

	if ifconfig ${JAIL_NET_INTERFACE} 2>&1 | grep -q 'does not exist'; then
		echo; echo "ERROR: did you run 'provision host' yet?"; echo;
		exit 1
	else
		echo "ok"
	fi
}

assure_jail_nic
zfs_snapshot_exists "$BASE_SNAP" && exit 0
stop_jail stage
create_base_filesystem
install_freebsd
freebsd_update
configure_base
start_staged_jail base "$BASE_MNT"
install_base
stop_jail stage
if [ -e "$BASE_MNT/dev/null" ]; then umount "$BASE_MNT/dev"; fi
rm -rf "$BASE_MNT/var/cache/pkg/*"
rm -rf "$BASE_MNT/var/db/freebsd-update/*"
echo "zfs snapshot ${BASE_SNAP}"
zfs snapshot "${BASE_SNAP}"
add_jail_conf base

proclaim_success base
