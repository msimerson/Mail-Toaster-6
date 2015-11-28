#!/bin/sh

. mail-toaster.sh

# Modify to suit
#export BASE_JAIL_NET="lo0|127.0.0.2"
export BASE_JAIL_NET="lo0|127.0.0.7"

export SAFE_NAME=`safe_jailname $BASE_NAME`

create_zfs_jail_root()
{
	if [ ! -d "$ZFS_JAIL_MNT" ];
	then
		echo "creating $ZFS_JAIL_MNT"
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
		fetch $FBSD_MIRROR/pub/FreeBSD/releases/$FBSD_ARCH/$FBSD_REL_VER/base.txz || exit
	fi

	tar -C $BASE_MNT -xvpJf base.txz || exit
}

update_freebsd()
{
	sed -i .bak -e 's/^Components.*/Components world kernel/' $BASE_MNT/etc/freebsd-update.conf
	freebsd-update -b $BASE_MNT -f $BASE_MNT/etc/freebsd-update.conf fetch install
}

configure_base()
{
	mkdir $BASE_MNT/usr/ports || exit
	mkdir $BASE_MNT/etc/ssl/certs $BASE_MNT/etc/ssl/private
	chmod o-r $BASE_MNT/etc/ssl/private

	cp /etc/resolv.conf $BASE_ETC || exit
	cp /etc/localtime $BASE_ETC || exit

	tee -a $BASE_ETC/make.conf <<EO_MAKE_CONF
WITH_PKGNG=yes
WRKDIRPREFIX?=/tmp/portbuild
EO_MAKE_CONF

	sysrc -f $BASE_ETC/rc.conf \
		sendmail_enable=NONE \
		cron_flags='\\$cron_flags -J 15' \
		syslogd_flags=-ss
}

install_bash()
{
	pkg -j $SAFE_NAME install -y bash
	jexec $SAFE_NAME chpass -s /usr/local/bin/bash
	tee -a $BASE_MNT/root/.bash_profile <<EO_BASH_PROFILE
export HISTCONTROL=erasedups
export HISTIGNORE="&:[bf]g:exit"
shopt -s cdspell
bind Space:magic-space
alias h="history 25"
alias ls="ls -FG"
alias ll="ls -alFG"
EO_BASH_PROFILE
}

base_snapshot_exists \
	&& (echo "$BASE_SNAP snapshot already exists" && exit 0)
create_zfs_jail_root
create_base_filesystem
install_freebsd
update_freebsd
configure_base

# service jail start $SAFE_NAME || exit
start_staged_jail $SAFE_NAME
pkg -j $SAFE_NAME install -y pkg vim-lite sudo ca_root_nss

# comment out this line if you hate bash
install_bash

service jail stop $SAFE_NAME
zfs snapshot ${BASE_VOL}@${FBSD_PATCH_VER}
