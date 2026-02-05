#!/bin/sh

set -e

. mail-toaster.sh

mt6-include linux

export JAIL_START_EXTRA="allow.mount
		allow.mount.devfs
		allow.mount.fdescfs
		allow.mount.procfs
		allow.mount.linprocfs
		allow.mount.linsysfs
		allow.mount.tmpfs
		enforce_statfs=1
"
export JAIL_CONF_EXTRA='
		allow.raw_sockets;'
export JAIL_FSTAB="
devfs     $ZFS_JAIL_MNT/stalwart/compat/linux/dev     devfs     rw,late  0 0
tmpfs     $ZFS_JAIL_MNT/stalwart/compat/linux/dev/shm tmpfs     rw,late,size=1g,mode=1777  0 0
fdescfs   $ZFS_JAIL_MNT/stalwart/compat/linux/dev/fd  fdescfs   rw,late,linrdlnk 0 0
linprocfs $ZFS_JAIL_MNT/stalwart/compat/linux/proc    linprocfs rw,late  0 0
linsysfs  $ZFS_JAIL_MNT/stalwart/compat/linux/sys     linsysfs  rw,late  0 0
$ZFS_DATA_MNT/stalwart/linux $ZFS_JAIL_MNT/stalwart/compat/linux/stalwart nullfs rw,late 0,0
#/tmp      $ZFS_JAIL_MNT/stalwart/compat/linux/tmp     nullfs    rw,late  0 0
#/home     $ZFS_JAIL_MNT/stalwart/compat/linux/home    nullfs    rw,late  0 0"


install_stalwart_freebsd()
{
	# until the port is resurrected and/or builds w/o heroic effort, use Linux compat
	tell_status "installing RocksDB"
	stage_pkg_install rocksdb

	tell_status "installing Stalwart deps"
	stage_pkg_install cmake-core gmake llvm22 portconfig rust sequoia libsieve

	tell_status "installing Stalwart"
	stage_make_conf stalwart_SET "mail_stalwart_SET=ROCKSDB REDIS"
	stage_make_conf stalwart_UNSET "mail_stalwart_UNSET=ENTERPRISE SQLITE FOUNDATIONDB POSTGRES MYSQL S3 AZURE"
	stage_port_install mail/stalwart
}

install_stalwart_linux()
{
	install_linux jammy

	stage_exec fetch -o /compat/linux/install.sh https://get.stalw.art/install.sh
	stage_exec chroot /compat/linux apt install -y curl
	stage_exec chroot /compat/linux /bin/bash /install.sh /stalwart
}

install_stalwart()
{
	#install_stalwart_freebsd
	install_stalwart_linux
}

configure_stalwart_freebsd()
{
	stage_sysrc stalwart_enable="YES"
	stage_sysrc stalwart_user="root"
	stage_sysrc stalwart_group="wheel"
	stage_sysrc stalwart_config="/data/etc/stalwart.toml"
}

configure_stalwart()
{
	tell_status "configuring Stalwart"
}

start_stalwart_freebsd()
{
	tell_status "starting up Stalwart"

	store_exec "$STAGE_MNT/usr/local/etc/rc.d/stalwart" <<'EO_STALWART_RCD'
#!/bin/sh
#
# PROVIDE: stalwart
# REQUIRE: NETWORKING
# KEYWORD: shutdown
#
# Add to rc.conf:
#   stalwart_enable="YES"
#   stalwart_user="stalwart"
#   stalwart_group="stalwart"
#   stalwart_config="/opt/stalwart/etc/config.toml"
#   stalwart_flags=""
#

. /etc/rc.subr

name="stalwart"
rcvar=stalwart_enable

load_rc_config $name

: ${stalwart_enable:="NO"}
: ${stalwart_user:="stalwart"}
: ${stalwart_group:="stalwart"}
: ${stalwart_config:="/opt/stalwart/etc/config.toml"}
: ${stalwart_flags:=""}

command="/usr/sbin/daemon"
procname="/opt/stalwart/bin/stalwart"

pidfile="/var/run/${name}.pid"
logfile="/var/log/${name}.log"

command_args="-p ${pidfile} -o ${logfile} -u ${stalwart_user} \
    ${procname} --config ${stalwart_config} ${stalwart_flags}"

start_precmd="${name}_prestart"
stop_postcmd="rm -f ${pidfile}"

stalwart_prestart()
{
    install -d -o ${stalwart_user} -g ${stalwart_group} /var/run
    install -d -o ${stalwart_user} -g ${stalwart_group} /var/log
}

run_rc_command "$1"
EO_STALWART_RCD

	stage_exec service stalwart start
}

start_stalwart_linux()
{
	store_exec "$STAGE_MNT/compat/linux/etc/init.d/stalwart" <<'EO_STALWART_INITD'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          stalwart
# Required-Start:    $remote_fs $network
# Required-Stop:     $remote_fs $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Stalwart Mail Server
# Description:       Stalwart Mail Server daemon
### END INIT INFO

NAME="stalwart"
DESC="Stalwart Mail Server"

DAEMON="/stalwart/bin/stalwart"
DAEMON_USER="root"

PIDFILE="/var/run/$NAME.pid"
LOGFILE="/var/log/$NAME.log"
CONFIG="/stalwart/etc/config.toml"

. /lib/lsb/init-functions

do_start() {
    log_daemon_msg "Starting $DESC"

    start-stop-daemon --start \
        --background \
        --make-pidfile \
        --pidfile $PIDFILE \
        --chuid $DAEMON_USER \
        --exec $DAEMON -- \
            --config $CONFIG >> $LOGFILE 2>&1

    log_end_msg $?
}

do_stop() {
    log_daemon_msg "Stopping $DESC"

    start-stop-daemon --stop \
        --pidfile $PIDFILE \
        --retry=TERM/30/KILL/5

    rm -f $PIDFILE
    log_end_msg $?
}

case "$1" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_stop
        sleep 1
        do_start
        ;;
    reload)
        start-stop-daemon --stop --signal HUP --pidfile $PIDFILE
        ;;
    status)
        status_of_proc -p $PIDFILE $DAEMON $NAME && exit 0 || exit $?
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|reload|status}"
        exit 1
        ;;
esac

exit 0
EO_STALWART_INITD

	stage_exec chroot /compat/linux update-rc.d stalwart defaults
	stage_exec chroot /compat/linux service stalwart start
}

start_stalwart()
{
	start_stalwart_linux
}

test_stalwart()
{
	tell_status "testing Stalwart"
	stage_test_running stalwart
	stage_listening 993
}

base_snapshot_exists
create_staged_fs stalwart
mkdir -p "$ZFS_DATA_MNT/stalwart/linux"
for _d in dev/shm dev/fd proc sys stalwart; do
	mkdir -p "$STAGE_MNT/compat/linux/$_d"
done
start_staged_jail stalwart
install_stalwart
configure_stalwart
start_stalwart
test_stalwart
promote_staged_jail stalwart
