#!/bin/sh

# commands: list, start, stop, reset, suspend, pause, unpause
#           listSnapshot, snapshot, deleteSnapshot, revertToSnapshot
#           runProgramInGuest
#           upgradevm, installTools, checkToolsState, deleteVM, clone
# vmrun -T fusion start

FREEBSD="/Users/Shared/Virtual Machines/FreeBSD 13 GitLab Runner.vmwarevm"
VERSION="13.2p0"
VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"
GUESTUSER="root"
GUESTPASS="passWord"

_err()
{
	echo "ERROR: $1"
	exit 1
}

start()
{
	"$VMRUN" -T fusion start "$FREEBSD" || _err "start failed"
	echo "started"
}

stop()
{
	_is_running=$("/Applications/VMware Fusion.app/Contents/Library/vmrun" -T fusion list "/Users/Shared/Virtual Machines/FreeBSD 13 GitLab Runner.vmwarevm" | grep running | awk '{ print $4 }')
	if [ $_is_running = "1" ]; then
		"$VMRUN" -T fusion stop "$FREEBSD" || _err "stop failed"
	fi
	echo "stopped"
}

listSnapshots()
{
	"$VMRUN" listSnapshots "$FREEBSD"
}

runProgramInGuest()
{
	PROG="$1"
	if [ -z "$PROG" ]; then
		PROG="/home/matt/hi.sh"
	fi

	"$VMRUN" -gu "$GUESTUSER" -gp "$GUESTPASS" runProgramInGuest "$FREEBSD" "$PROG"
}

revertToSnapshot()
{
	"$VMRUN" revertToSnapshot "$FREEBSD" "$1" || _err "revert failed"
	echo "reverted to $1"
}

listProcessesInGuest()
{
	"$VMRUN" -gu "$GUESTUSER" -gp "$GUESTPASS" listProcessesInGuest "$FREEBSD"
}

cleanstart() {
	stop
	revertToSnapshot "$VERSION"
	start
}

vm_setup() {
	# install, no options, Auto ZFS, 8gb swap, sshd & powerd
	pkg install -y vim-tiny sudo open-vm-tools-nox11 git-lite
	chpass -s sh root
	echo 'autoboot_delay="1"' >> /boot/loader.conf

	if ! grep -q PermitRootLogin /etc/rc.conf; then
		sysrc sshd_flags+=" -o PermitRootLogin=without-password"
	fi
	service sshd restart

	for d in usr/src var/audit var/crash var/mail var/tmp; do
		zfs destroy "zroot/${d}"
		mkdir "/${d}"
	done

	echo "All set, install your SSH keys, shut down & snapshot!"
}

if [ "$1" = "cleanstart" ] || [ "$1" = "freshstart" ]; then
	cleanstart
elif [ "$1" ]; then
	$1
else
	echo "$0 cleanstart"
fi
