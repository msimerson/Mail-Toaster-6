#!/bin/sh

. mail-toaster.sh || exit

export SAFE_NAME=`safe_jailname $BASE_NAME`

create_zfs_jail_root()
{
	if [ ! -d "$ZFS_JAIL_MNT" ];
	then
		tell_status "creating fs $ZFS_JAIL_MNT"
		echo "zfs create $ZFS_JAIL_MNT"
		zfs create -o mountpoint=$ZFS_JAIL_MNT $ZFS_JAIL_VOL || exit
	fi
}

create_base_filesystem()
{
	if [ -d "$BASE_MNT" ];
	then
		echo "destroying $BASE_MNT"
		zfs destroy $BASE_VOL || exit
	fi

	zfs create $BASE_VOL || exit
}

install_freebsd()
{
	echo "getting base.tgz"
	fetch -m $FBSD_MIRROR/pub/FreeBSD/releases/$FBSD_ARCH/$FBSD_REL_VER/base.txz || exit

	echo "extracting base.tgz"
	tar -C $BASE_MNT -xvpJf base.txz || exit

	# export BSDINSTALL_DISTSITE="$FBSD_MIRROR/pub/FreeBSD/releases/$FBSD_ARCH/$FBSD_ARCH/$FBSD_REL_VER"
	# bsdinstall jail $BASE_MNT
}

update_freebsd()
{
	sed -i .bak -e 's/^Components.*/Components world kernel/' $BASE_MNT/etc/freebsd-update.conf
	freebsd-update -b $BASE_MNT -f $BASE_MNT/etc/freebsd-update.conf fetch install
}

configure_base_tls_certs()
{
	mkdir $BASE_MNT/etc/ssl/certs $BASE_MNT/etc/ssl/private
	chmod o-r $BASE_MNT/etc/ssl/private

    echo
	echo "A number of daemons use TLS to encrypt connections. Setting up TLS now"
	echo "	saves having to do it in each subsequent one."
	echo
	echo "Generating self-signed SSL certificates"
	echo "	hint: use the FQDN of this server for the common name"
	echo
	openssl req -x509 -nodes -days 2190 \
	    -newkey rsa:2048 \
	    -keyout $BASE_MNT/etc/ssl/private/server.key \
	    -out $BASE_MNT/etc/ssl/certs/server.crt
}

configure_base()
{
	mkdir $BASE_MNT/usr/ports || exit

	cp /etc/resolv.conf $BASE_MNT/etc || exit
	cp /etc/localtime $BASE_MNT/etc || exit

	tee -a $BASE_MNT/etc/make.conf <<EO_MAKE_CONF
WITH_PKGNG=yes
WRKDIRPREFIX?=/tmp/portbuild
EO_MAKE_CONF

	sysrc -f $BASE_MNT/etc/rc.conf \
		hostname=base \
		sendmail_enable=NONE \
		cron_flags='$cron_flags -J 15' \
		syslogd_flags=-ss

	echo 'zfs_enable="YES"' | tee -a $BASE_MNT/boot/loader.conf

	configure_base_tls_certs
}

install_bash()
{
	pkg -j $SAFE_NAME install -y bash || exit
	jexec $SAFE_NAME chpass -s /usr/local/bin/bash

	local _profile=$BASE_MNT/root/.bash_profile
	if [ -f "$_profile" ]; then
		return
	fi

	tee -a $_profile <<EO_BASH_PROFILE

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
PS1="`whoami`@`hostname -s`:\\w # "
'
	grep -q PS1 $_profile || echo "$_bconf" | tee -a $_profile
	grep -q PS1 /root/.profile || echo "$_bconf" | tee -a /root/.profile

	if [ $BOURNE_SHELL = "bash" ]; then
		install_bash
	fi
}

base_snapshot_exists && exit 0
create_zfs_jail_root
create_base_filesystem
install_freebsd
update_freebsd
configure_base

start_staged_jail $SAFE_NAME $BASE_MNT || exit
pkg -j $SAFE_NAME install -y pkg vim-lite sudo ca_root_nss || exit
jexec $SAFE_NAME newaliases || exit

use_bourne_shell

jail -r $SAFE_NAME
umount $BASE_MNT/dev
rm -rf $BASE_MNT/var/cache/pkg/*

echo "zfs snapshot ${BASE_VOL}@${FBSD_PATCH_VER}"
zfs snapshot ${BASE_VOL}@${FBSD_PATCH_VER} || exit

proclaim_success base