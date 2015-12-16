#!/bin/sh

. mail-toaster.sh || exit

export BASE_MNT="$ZFS_JAIL_MNT/$BASE_NAME"

create_zfs_jail_root()
{
	if [ -d "$ZFS_JAIL_MNT" ]; then return; fi

}

create_base_filesystem()
{
	if [ -e "$BASE_MNT/dev/null" ];
	then
		echo "unmounting $BASE_MNT/dev"
		umount "$BASE_MNT/dev"
	fi

	if [ -d "$BASE_MNT" ];
	then
		echo "destroying $BASE_MNT"
		zfs destroy "$BASE_VOL" || exit
	fi

	zfs_create_fs "$BASE_VOL"
}

install_freebsd()
{
	tell_status "getting base.tgz"
	fetch -m "$FBSD_MIRROR/pub/FreeBSD/releases/$FBSD_ARCH/$FBSD_REL_VER/base.txz" || exit

	if [ -n "$USE_BSDINSTALL" ]; then
		export BSDINSTALL_DISTSITE="$FBSD_MIRROR/pub/FreeBSD/releases/$FBSD_ARCH/$FBSD_ARCH/$FBSD_REL_VER"
		bsdinstall jail "$BASE_MNT"
	else
		tell_status "extracting base.tgz"
		tar -C "$BASE_MNT" -xvpJf base.txz || exit
	fi

	tell_status "apply FreeBSD patches to base jail"
	sed -i .bak -e 's/^Components.*/Components world kernel/' "$BASE_MNT/etc/freebsd-update.conf"
	freebsd-update -b "$BASE_MNT" -f "$BASE_MNT/etc/freebsd-update.conf" fetch install
}

configure_tls_certs()
{
	mkdir "$BASE_MNT/etc/ssl/certs" "$BASE_MNT/etc/ssl/private"
	chmod o-r "$BASE_MNT/etc/ssl/private"

	local _ssl_cnf; _ssl_cnf="$BASE_MNT/etc/ssl/openssl.cnf"
	grep -q commonName_default "$_ssl_cnf" || \
		sed -i.bak -e "/^commonName_max.*/ a\ 
commonName_default = $TOASTER_HOSTNAME \
" "$_ssl_cnf"

	grep -q commonName_default /etc/ssl/openssl.cnf || \
		sed -i.bak -e "/^commonName_max.*/ a\ 
commonName_default = $TOASTER_HOSTNAME \
" /etc/ssl/openssl.cnf

	echo
	echo "A number of daemons use TLS to encrypt connections. Setting up TLS now"
	echo "	saves having to do it multiple times later."
	echo
	echo "Generating self-signed SSL certificates"
	echo
	openssl req -x509 -nodes -days 2190 \
	    -newkey rsa:2048 \
	    -keyout "$BASE_MNT/etc/ssl/private/server.key" \
	    -out "$BASE_MNT/etc/ssl/certs/server.crt"

	if [ ! -f "$BASE_MNT/etc/ssl/private/server.key" ]; then
		"ERROR: no TLS key was generated!"
		exit
	fi
}

configure_base()
{
	mkdir "$BASE_MNT/usr/ports" || exit

	tell_status "adding base jail resolv.conf"
	cp /etc/resolv.conf "$BASE_MNT/etc" || exit

	tell_status "setting base jail's timezone (to hosts)"
	cp /etc/localtime "$BASE_MNT/etc" || exit

	tell_status "setting base jail make.conf variables"
	tee -a "$BASE_MNT/etc/make.conf" <<EO_MAKE_CONF
WITH_PKGNG=yes
WRKDIRPREFIX?=/tmp/portbuild
EO_MAKE_CONF

	sysrc -f "$BASE_MNT/etc/rc.conf" \
		hostname=base \
		sendmail_enable=NONE \
		cron_flags='$cron_flags -J 15' \
		syslogd_flags=-ss

#	echo 'zfs_enable="YES"' | tee -a "$BASE_MNT/boot/loader.conf"
}

install_bash()
{
	pkg -j stage install -y bash || exit
	jexec stage chpass -s /usr/local/bin/bash

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

use_bourne_shell()
{
	local _profile=$BASE_MNT/root/.profile
	local _bconf='
alias ls="ls -FG"
alias ll="ls -alFG"
PS1="$(whoami)@$(hostname -s):\\w # "
'
	grep -q PS1 "$_profile" || echo "$_bconf" | tee -a "$_profile"
	grep -q PS1 /root/.profile || echo "$_bconf" | tee -a /root/.profile

	if [ "$BOURNE_SHELL" = "bash" ]; then
		install_bash
	fi
}

install_base()
{
	pkg -j stage install -y pkg vim-lite sudo ca_root_nss || exit
	jexec stage newaliases || exit
}

zfs_snapshot_exists "$BASE_SNAP" && exit 0
jail -r stage
zfs_create_fs "$ZFS_JAIL_VOL" "$ZFS_JAIL_MNT"
create_base_filesystem
install_freebsd
configure_base
configure_tls_certs
use_bourne_shell
start_staged_jail base "$BASE_MNT" || exit
install_base
jail -r stage
umount "$BASE_MNT/dev"
rm -rf "$BASE_MNT/var/cache/pkg/*"
echo "zfs snapshot ${BASE_SNAP}"
zfs snapshot "${BASE_SNAP}" || exit

proclaim_success base