#!/bin/sh

. mail-toaster.sh || exit

export SAFE_NAME=`safe_jailname $BASE_NAME`

create_zfs_jail_root()
{
	if [ ! -d "$ZFS_JAIL_MNT" ];
	then
		echo "creating $ZFS_JAIL_MNT fs"
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
	if [ ! -f "base.txz" ];
	then
		fetch -m $FBSD_MIRROR/pub/FreeBSD/releases/$FBSD_ARCH/$FBSD_REL_VER/base.txz || exit
	fi

	tar -C $BASE_MNT -xvpJf base.txz || exit

	# export BSDINSTALL_DISTSITE="$FBSD_MIRROR/pub/FreeBSD/releases/$FBSD_ARCH/$FBSD_ARCH/$FBSD_REL_VER"
	# bsdinstall jail $BASE_MNT
}

update_freebsd()
{
	sed -i .bak -e 's/^Components.*/Components world kernel/' $BASE_MNT/etc/freebsd-update.conf
	freebsd-update -b $BASE_MNT -f $BASE_MNT/etc/freebsd-update.conf fetch install
}

configure_base()
{
	mkdir $BASE_MNT/usr/ports || exit
	mkdir $BASE_ETC/ssl/certs $BASE_ETC/ssl/private
	chmod o-r $BASE_MNT/etc/ssl/private

	cp /etc/resolv.conf $BASE_ETC || exit
	cp /etc/localtime $BASE_ETC || exit

	tee -a $BASE_ETC/make.conf <<EO_MAKE_CONF
WITH_PKGNG=yes
WRKDIRPREFIX?=/tmp/portbuild
EO_MAKE_CONF

	sysrc -f $BASE_MNT/etc/rc.conf \
		hostname=base \
		sendmail_enable=NONE \
		cron_flags='$cron_flags -J 15' \
		syslogd_flags=-ss

	echo 'zfs_enable="YES"' | tee -a $BASE_MNT/boot/loader.conf

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

	grep -q PS1 $_profile || tee -a $_profile <<EO_BOURNE

alias ls='ls -FG'
alias ll="ls -alFG"
PS1="\`whoami\`@`hostname -s`:\\w # "
EO_BOURNE

	grep -q PS1 /root/.profile || tee -a /root/.profile <<EO_BOURNE2

alias ls='ls -FG'
alias ll="ls -alFG"
PS1="\`whoami\`@`hostname -s`:\\w # "
EO_BOURNE2

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

# service jail start $SAFE_NAME || exit
start_staged_jail $SAFE_NAME $BASE_MNT || exit
pkg -j $SAFE_NAME install -y pkg vim-lite sudo ca_root_nss || exit
jexec $SAFE_NAME newaliases || exit
jexec $SAFE_NAME pkg update || exit

use_bourne_shell

service jail stop $SAFE_NAME
echo "zfs snapshot ${BASE_VOL}@${FBSD_PATCH_VER}"
zfs snapshot ${BASE_VOL}@${FBSD_PATCH_VER} || exit

proclaim_success base