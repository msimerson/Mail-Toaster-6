#!/bin/sh

# commands: list, start, stop, reset, suspend, pause, unpause
#           listSnapshot, snapshot, deleteSnapshot, revertToSnapshot
#           runProgramInGuest
#           upgradevm, installTools, checkToolsState, deleteVM, clone
# vmrun -T fusion start

FREEBSD="/Users/Shared/Virtual Machines/FreeBSD 11.vmwarevm"
VERSION="11.1p1"
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
    "$VMRUN" -T fusion stop "$FREEBSD" || _err "start failed"
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

if [ "$1" = "cleanstart" ] || [ "$1" = "freshstart" ]; then
    cleanstart
else
    echo "$0 cleanstart"
fi
