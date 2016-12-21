#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

create_base_filesystem()
{
	if [ -e "$BASE_MNT/dev/null" ];
	then
		echo "unmounting $BASE_MNT/dev"
		umount "$BASE_MNT/dev" || exit
	fi

	if zfs_filesystem_exists "$BASE_VOL";
	then
		echo "$BASE_VOL already exists"
		return
	fi

	zfs_create_fs "$BASE_VOL"
}

freebsd_update()
{
	tell_status "apply FreeBSD security updates to base jail"
	sed -i .bak -e 's/^Components.*/Components world/' "$BASE_MNT/etc/freebsd-update.conf"
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
		BSDINSTALL_DISTSITE="$FBSD_MIRROR/pub/FreeBSD/releases/$(uname -m)/$(uname -m)/$FBSD_REL_VER"
		bsdinstall jail "$BASE_MNT"
	else
		stage_fbsd_package base "$BASE_MNT"
	fi
}

install_ssmtp()
{
	tell_status "installing ssmtp"
	stage_pkg_install ssmtp || exit

	tell_status "configuring ssmtp"
	cp "$BASE_MNT/usr/local/etc/ssmtp/revaliases.sample" \
	   "$BASE_MNT/usr/local/etc/ssmtp/revaliases" || exit

	sed -e "/^root=/ s/postmaster/$TOASTER_ADMIN_EMAIL/" \
		-e "/^mailhub=/ s/=mail/=vpopmail/" \
		-e "/^rewriteDomain=/ s/=\$/=$TOASTER_MAIL_DOMAIN/" \
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

	tell_status "disabling newsyslog"
	sysrc -f "$BASE_MNT/etc/rc.conf" newsyslog_enable=NO
	sed -i .bak \
		-e '/^0.*newsyslog/ s/^0/#0/' \
		"$BASE_MNT/etc/crontab"
}

disable_syslog()
{
	tell_status "disabling syslog"
	sysrc -f "$BASE_MNT/etc/rc.conf" newsyslog_enable=NO syslogd_enable=NO
	sed -i .bak \
		-e '/^0.*newsyslog/ s/^0/#0/' \
		"$BASE_MNT/etc/crontab"
}

disable_root_password()
{
	if ! grep -q '^root::' "$BASE_MNT/etc/master.passwd"; then
		return
	fi

	# prevent a nightly email notice about the empty root password
	tell_status "disabling passwordless root account"
	sed -i .bak -e 's/^root::/root:*:/' "$BASE_MNT/etc/master.passwd"
	stage_exec pwd_mkdb /etc/master.passwd || exit
}

disable_cron_jobs()
{
	if grep -q '^1.*adjkerntz' "$BASE_MNT/etc/crontab"; then
		tell_status "cron jobs already configured"
		return
	fi

	tell_status "disabling adjkerntz, save-entropy, & atrun"
	# nobody uses atrun, safe-entropy is done by the host, and
	# the jail doesn't have permission to run adjkerntz.
	sed -i .bak \
		-e '/^1.*adjkerntz/ s/^1/#1/'  \
		-e '/^\*.*atrun/    s/^\*/#*/' \
		-e '/^\*.*entropy/  s/^\*/#*/' \
		"$BASE_MNT/etc/crontab" || exit

	echo "done"
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

	sysrc -f "$BASE_MNT/etc/rc.conf" \
		hostname=base \
		cron_flags='$cron_flags -J 15' \
		syslogd_flags="-s -cc" \
		sendmail_enable=NONE \
		update_motd=NO

	configure_ssl_dirs
	disable_cron_jobs
	configure_syslog
}

install_bash()
{
	tell_status "installing bash"
	stage_pkg_install bash || exit
	stage_exec chpass -s /usr/local/bin/bash

	local _profile="$BASE_MNT/root/.bash_profile"
	if [ -f "$_profile" ]; then
		return
	fi

	tee -a "$_profile" <<'EO_BASH_PROFILE'

export HISTCONTROL=erasedups
export HISTIGNORE="&:[bf]g:exit"
shopt -s cdspell
bind Space:magic-space
alias h="history 25"
alias ls="ls -FG"
alias ll="ls -alFG"
EO_BASH_PROFILE
}

install_zsh()
{
	tell_status "installing zsh"
	stage_pkg_install zsh || exit
	stage_exec chpass -s /usr/local/bin/zsh

}

config_bourne_shell()
{
	tell_status "making bourne sh more comfy"
	local _profile="$BASE_MNT/etc/profile"
	local _bconf='
	alias ls="ls -FG"
	alias ll="ls -alFG"
	PS1="$(whoami)@$(hostname -s):\\w # "
	'
	grep -q PS1 "$_profile" || echo "$_bconf" | tee -a "$_profile"
	grep -q PS1 /etc/profile || echo "$_bconf" | tee -a /etc/profile
}

config_csh_shell()
{
	local _cconf='
alias h         history 25
alias j         jobs -l
alias la        ls -aF
alias lf        ls -FA
alias ll        ls -lAF

setenv  EDITOR  vi
setenv  PAGER   more
setenv  BLOCKSIZE       K

if ($?prompt) then
        # An interactive shell -- set some stuff up
        set prompt = "%N@%m:%~ %# "
        set promptchars = "%#"

        set filec
        set history = 1000
        set savehist = (1000 merge)
        set autolist = ambiguous
        # Use history to aid expansion
        set autoexpand
        set autorehash
        if ( $?tcsh ) then
                bindkey "^W" backward-delete-word
                bindkey -k up history-search-backward
                bindkey -k down history-search-forward
        endif

endif
'
EO_CSH_SHELL

	_cshrc="$BASE_MNT/etc/csh.cshrc"
	grep -q PS1 "$_cshrc"      || echo "$_cconf" | tee -a "$_cshrc"
	grep -q PS1 /etc/csh.cshrc || echo "$_cconf" | tee -a /etc/csh.cshrc
}

config_zsh_shell()
{
	tell_status "makeing zsh more comfy with ZIM"

    #fetch -o "$BASE_MNT/root/zim-master.zip" https://github.com/Eriner/zim/archive/master.zip
    fetch -o "$BASE_MNT/root/zim.tar.gz" https://github.com/Eriner/zim/archive/master.zip

    cd "$BASE_MNT/root" || exit
    unzip zim-master.zip
    rm -rf .zim .zimrc .zlogin .zshrc
    mv -f zim-master .zim/
 	local _profile="$BASE_MNT/root/.zshrc"
	#if [ -f "$_profile" ]; then
	#	return
	#fi
stage_exec cp /root/.zim/templates/zimrc /root/.zimrc
stage_exec cp /root/.zim/templates/zlogin /root/.zlogin
stage_exec cp /root/.zim/templates/zshrc /root/.zshrc
stage_exec zsh -c '. /root/.zshrc;  source /root/.zlogin'
stage_exec zsh
    #stage_exec zsh -c 'setopt EXTENDED_GLOB'
    #stage_exec zsh -c 'setopt EXTENDED_GLOB  && for rcfile in "/root/.zprezto/runcoms/^README.md(.N); do ln -s "$rcfile" "root/.${rcfile:t}" done'

}


install_periodic_conf()
{
	tell_status "installing /etc/periodic.conf"
	tee "$BASE_MNT/etc/periodic.conf" <<EO_PERIODIC
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
security_status_pkgaudit_enable="YES"
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
daily_clean_disks_enable="NO"
daily_clean_disks_verbose="NO"
daily_clean_hoststat_enable="NO"
daily_clean_tmps_enable="YES"
daily_clean_tmps_verbose="NO"
daily_news_expire_enable="NO"

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

install_base()
{
	tell_status "installing packages desired in every jail"
	stage_pkg_install pkg vim-lite ca_root_nss || exit

	stage_exec newaliases || exit

	if [ "$BOURNE_SHELL" = "bash" ]; then
		install_bash
    elif [ "$BOURNE_SHELL" = "zsh" ]; then
		install_zsh
	    config_zsh_shell
    fi

	install_ssmtp
	disable_root_password
	install_periodic_conf
	stage_exec pkg upgrade -y
}

zfs_snapshot_exists "$BASE_SNAP" && exit 0
jail -r stage 2>/dev/null
create_base_filesystem
install_freebsd
#freebsd_update
configure_base
config_bourne_shell
config_csh_shell
start_staged_jail base "$BASE_MNT" || exit
install_base
jail -r stage
umount "$BASE_MNT/dev"
rm -rf "$BASE_MNT/var/cache/pkg/*"
echo "zfs snapshot ${BASE_SNAP}"
zfs snapshot "${BASE_SNAP}" || exit

proclaim_success base
