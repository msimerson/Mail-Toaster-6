#!/bin/sh

# Required settings
export TOASTER_HOSTNAME=${TOASTER_HOSTNAME:="mail.example.com"} || exit
export TOASTER_MAIL_DOMAIN=${TOASTER_MAIL_DOMAIN:="example.com"}

# export these in your environment to customize
export BOURNE_SHELL=${BOURNE_SHELL:="bash"}
export JAIL_NET_PREFIX=${JAIL_NET_PREFIX:="172.16.15"}
export JAIL_NET_MASK=${JAIL_NET_MASK:="/12"}
export JAIL_NET_INTERFACE=${JAIL_NET_INTERFACE:="lo1"}
export JAIL_ORDERED_LIST=${JAIL_ORDERED_LIST:="dns mysql vpopmail dovecot webmail haproxy clamav avg redis rspamd geoip spamassassin haraka monitor"}
export ZFS_VOL=${ZFS_VOL:="zroot"}
export ZFS_JAIL_MNT=${ZFS_JAIL_MNT:="/jails"}
export ZFS_DATA_MNT=${ZFS_DATA_MNT:="/data"}
export FBSD_MIRROR=${FBSD_MIRROR:="ftp://ftp.freebsd.org"}

# See https://github.com/msimerson/Mail-Toaster-6/wiki/MySQL
export TOASTER_MYSQL=${TOASTER_MYSQL:="1"}
if [ "$TOASTER_MYSQL" = "1" ]; then
	echo "mysql enabled"
fi

usage() {
	echo; echo "Oops, you aren't following instructions!"; echo
	echo "See: https://github.com/msimerson/Mail-Toaster-6/wiki/FreeBSD"; echo
	exit
}
if [ "$TOASTER_HOSTNAME" = "mail.example.com" ]; then usage; fi
echo "toaster host: $TOASTER_HOSTNAME"

if [ "$TOASTER_MAIL_DOMAIN" = "example.com" ]; then usage; fi
echo "email domain: $TOASTER_MAIL_DOMAIN"

# shellcheck disable=2009
if ps -o args= -p "$$" | grep csh; then usage; fi
echo "shell: $SHELL"

# very little below here should need customizing. If so, consider opening
# an Issue or PR at https://github.com/msimerson/Mail-Toaster-6
export ZFS_JAIL_VOL="${ZFS_VOL}${ZFS_JAIL_MNT}"
export ZFS_DATA_VOL="${ZFS_VOL}${ZFS_DATA_MNT}"

export FBSD_REL_VER FBSD_PATCH_VER
FBSD_REL_VER=$(/bin/freebsd-version | /usr/bin/cut -f1-2 -d'-')
FBSD_PATCH_VER=$(/bin/freebsd-version | /usr/bin/cut -f3 -d'-')
FBSD_PATCH_VER=${FBSD_PATCH_VER:="p0"}

# the 'base' jail that other jails are cloned from. This will be named as the
# host OS version, ex: base-10.2-RELEASE and the snapshot name will be the OS
# patch level, ex: base-10.2-RELEASE@p7
export BASE_NAME="base-$FBSD_REL_VER"
export BASE_VOL="$ZFS_JAIL_VOL/$BASE_NAME"
export BASE_SNAP="${BASE_VOL}@${FBSD_PATCH_VER}"
export BASE_MNT="$ZFS_JAIL_MNT/$BASE_NAME"

export STAGE_MNT="$ZFS_JAIL_MNT/stage"

fatal_err() {
	echo; echo "FATAL: $1"; echo; exit
}

safe_jailname()
{
	# constrain jail name chars to alpha-numeric and _
	echo "$1" | sed -e 's/[^a-zA-Z0-9]/_/g'
}

export SAFE_NAME; SAFE_NAME=$(safe_jailname stage)
if [ -z "$SAFE_NAME" ]; then echo "unset SAFE_NAME"; exit; fi
echo "safe name: $SAFE_NAME"

zfs_filesystem_exists()
{
	if zfs list -t filesystem "$1" 2>/dev/null | grep -q "^$1"; then
		echo "$1 filesystem exists"
		return 0
	fi

	return 1
}

zfs_snapshot_exists()
{
	if zfs list -t snapshot "$1" 2>/dev/null | grep -q "$1"; then
		echo "$1 snapshot exists"
		return 0
	else
		return 1
	fi
}

zfs_create_fs() {

	if zfs_filesystem_exists "$1"; then return; fi

	if echo "$1" | grep "$ZFS_DATA_VOL"; then
		if ! zfs_filesystem_exists "$ZFS_DATA_VOL"; then
			tell_status "zfs create -o mountpoint=$ZFS_DATA_MNT $ZFS_DATA_VOL"
			zfs create -o mountpoint="$ZFS_DATA_MNT" "$ZFS_DATA_VOL"  || exit
		fi
	fi

	if echo "$1" | grep "$ZFS_JAIL_VOL"; then
		if ! zfs_filesystem_exists "$ZFS_JAIL_VOL"; then
			tell_status "zfs create -o mountpoint=$ZFS_JAIL_MNT $ZFS_JAIL_VOL"
			zfs create -o mountpoint="$ZFS_JAIL_MNT" "$ZFS_JAIL_VOL"  || exit
		fi
	fi

	if [ -z "$2" ]; then
		tell_status "zfs create $1"
		zfs create "$1" || exit
		echo "done"
		return
	fi

	tell_status "zfs create -o mountpoint=$2 $1"
	zfs create -o mountpoint="$2" "$1"  || exit
	echo "done"
}

zfs_destroy_fs()
{
	if ! zfs_filesystem_exists "$1"; then return; fi
	if [ -n "$2" ]; then
		echo "zfs destroy $2 $1"
		zfs destroy "$2" "$1" || exit
	else
		echo "zfs destroy $1"
		zfs destroy "$1" || exit
	fi
}

base_snapshot_exists()
{
	if zfs_snapshot_exists "$BASE_SNAP"; then
		return 0
	fi

	echo "$BASE_SNAP does not exist, use 'provision base' to create it"
	return 1
}

jail_conf_header()
{
	if [ -e /etc/jail.conf ]; then return; fi

	tell_status "adding /etc/jail.conf header"
	tee -a /etc/jail.conf <<EO_JAIL_CONF_HEAD

exec.start = "/bin/sh /etc/rc";
exec.stop = "/bin/sh /etc/rc.shutdown";
exec.clean;
mount.devfs;
path = "$ZFS_JAIL_MNT/\$name";
interface = $JAIL_NET_INTERFACE;
host.hostname = \$name;

EO_JAIL_CONF_HEAD
}

get_jail_ip()
{
	local _start=${JAIL_NET_START:=1}
	local _incr

	case "$1" in
		syslog)       _incr=0 ;;
		base)         _incr=1 ;;
		dns)          _incr=2 ;;
		mysql)        _incr=3 ;;
		clamav)       _incr=4 ;;
		spamassassin) _incr=5 ;;
		dspam)        _incr=6 ;;
		vpopmail)     _incr=7 ;;
		haraka)       _incr=8 ;;
		webmail)      _incr=9 ;;
		monitor)      _incr=10 ;;
		haproxy)      _incr=11 ;;
		rspamd)       _incr=12 ;;
		avg)          _incr=13 ;;
		dovecot)      _incr=14 ;;
		redis)        _incr=15 ;;
		geoip)        _incr=16 ;;
		nginx)        _incr=17 ;;
		lighttpd)     _incr=18 ;;
		apache)       _incr=19 ;;
		postgres)     _incr=20 ;;
		minecraft)    _incr=21 ;;
		joomla)       _incr=22 ;;
		stage)        echo "$JAIL_NET_PREFIX.254"; return;;
	esac

	if echo "$1" | grep -q ^base; then
		_incr=1
	fi

	# return error code if _incr unset
	if [ -z "$_incr" ]; then return 2; fi

	local _octet=$((_start + _incr))
	echo "$JAIL_NET_PREFIX.$_octet"
}

get_reverse_ip()
{
	local _jail_ip; _jail_ip=$(get_jail_ip "$1")
	if [ -z "$_jail_ip" ]; then
		echo "unknown jail: $1"
		exit
	fi

	local _rev_ip
	_rev_ip=$(echo "$_jail_ip" | awk '{split($1,a,".");printf("%s.%s.%s.%s",a[4],a[3],a[2],a[1])}')
	echo "$_rev_ip.in-addr.arpa"
}

add_jail_conf()
{
	local _jail_ip; _jail_ip=$(get_jail_ip "$1");
	if [ -z "$_jail_ip" ]; then
		fatal_err "can't determine IP for $1"
	fi

	jail_conf_header

	if grep -q "^$1" /etc/jail.conf; then return; fi

	local _path=""
	local _safe; _safe=$(safe_jailname "$1")
	if [ "$1" != "$_safe" ]; then
		_path="
		path = $ZFS_JAIL_MNT/${1};"
	fi

	tee -a /etc/jail.conf <<EO_JAIL_CONF

$1	{
		ip4.addr = $JAIL_NET_INTERFACE|${_jail_ip};${_path}${JAIL_CONF_EXTRA}
	}
EO_JAIL_CONF
}

stop_jail()
{
	local _safe; _safe=$(safe_jailname "$1")
	echo "service jail stop $_safe"
	service jail stop "$_safe"

	echo "jail -r $_safe"
	jail -r "$_safe" 2>/dev/null
}

stage_unmount()
{
	stage_unmount_dev
	unmount_ports "$STAGE_MNT"
	unmount_pkg_cache
	if has_data_fs "$1"; then unmount_data "$1"; fi
	unmount_aux_data "$1"
}

cleanup_staged_fs()
{
	tell_status "stage cleanup"
	stop_jail stage
	stage_unmount "$1"
	zfs_destroy_fs "$ZFS_JAIL_VOL/stage" -f
}

create_staged_fs()
{
	cleanup_staged_fs "$1"

	tell_status "stage jail filesystem setup"
	echo "zfs clone $BASE_SNAP $ZFS_JAIL_VOL/stage"
	zfs clone "$BASE_SNAP" "$ZFS_JAIL_VOL/stage" || exit

	stage_sysrc hostname="$1"
	sed -i -e "/^hostname=/ s/_HOSTNAME_/$1/" \
		"$STAGE_MNT/usr/local/etc/ssmtp/ssmtp.conf" || exit

	if has_data_fs "$1"; then
		zfs_create_fs "$ZFS_DATA_VOL/$1" "$ZFS_DATA_MNT/$1"
		mount_data "$1" "$STAGE_MNT"
	fi

	stage_mount_ports
	stage_mount_pkg_cache
	echo
}

unmount_aux_data()
{
	case $1 in
		spamassassin)  unmount_data geoip ;;
		haraka)        unmount_data geoip ;;
		dovecot)       unmount_data vpopmail ;;
	esac
}

mount_aux_data() {
	case $1 in
		spamassassin )  mount_data geoip ;;
		haraka )        mount_data geoip ;;
		dovecot )       mount_data vpopmail ;;
	esac
}

start_staged_jail()
{
	local _name="$1"
	local _path="$2"

	if [ -z "$_name" ]; then _name="$SAFE_NAME"; fi
	if [ -z "$_path" ]; then _path="$STAGE_MNT"; fi

	tell_status "stage jail $_name startup"

        # shellcheck disable=2086
	jail -c \
		name=stage \
		host.hostname="$_name" \
		path="$_path" \
		interface="$JAIL_NET_INTERFACE" \
		ip4.addr="$(get_jail_ip stage)" \
		exec.start="/bin/sh /etc/rc" \
		exec.stop="/bin/sh /etc/rc.shutdown" \
		allow.sysvipc=1 \
		mount.devfs \
		$JAIL_START_EXTRA \
		|| exit

	mount_aux_data "$_name"

	pkg -j stage update
}

rename_staged_to_ready()
{
	local _new_vol="$ZFS_JAIL_VOL/${1}.ready"

	# remove stages that failed promotion
	zfs_destroy_fs "$_new_vol"

	# get the wait over with before shutting down production jail
	local _tries=0
	local _zfs_rename="zfs rename $ZFS_JAIL_VOL/stage $_new_vol"
	echo "$_zfs_rename"
	until $_zfs_rename; do
		if [ "$_tries" -gt 25 ]; then
			echo "trying to force rename"
			_zfs_rename="zfs rename -f $ZFS_JAIL_VOL/stage $_new_vol"
		fi
		echo "waiting for ZFS filesystem to quiet ($_tries)"
		_tries=$((_tries + 1))
		sleep 5
	done
}

rename_active_to_last()
{
	local ACTIVE="$ZFS_JAIL_VOL/$1"
	local LAST="$ACTIVE.last"

	zfs_destroy_fs "$LAST"

	if ! zfs_filesystem_exists "$ACTIVE"; then return; fi

	local _tries=0
	local _zfs_rename="zfs rename $ACTIVE $LAST"
	echo "$_zfs_rename"
	until $_zfs_rename; do
		if [ $_tries -gt 5 ]; then
			echo "trying to force rename ($_tries)"
			_zfs_rename="zfs rename -f $ACTIVE $LAST"
		fi
		echo "waiting for ZFS filesystem to quiet ($_tries)"
		_tries=$((_tries + 1))
		sleep 5
	done
}

rename_ready_to_active()
{
	echo "zfs rename $ZFS_JAIL_VOL/${1}.ready $ZFS_JAIL_VOL/$1"
	zfs rename "$ZFS_JAIL_VOL/${1}.ready" "$ZFS_JAIL_VOL/$1" || exit
}

tell_status()
{
	echo; echo "   ***   $1   ***"; echo
	sleep 1
}

proclaim_success()
{
	echo; echo "Success! A new '$1' jail is provisioned"; echo
}

stage_clear_caches()
{
	echo "clearing pkg cache"
	rm -rf "$STAGE_MNT/var/cache/pkg/*"
}

stage_resolv_conf()
{
	local _nsip; _nsip=$(get_jail_ip dns)
	echo "nameserver $_nsip" | tee "$STAGE_MNT/etc/resolv.conf"
}

promote_staged_jail()
{
	tell_status "promoting jail $1"
	stop_jail stage
	stage_resolv_conf
	stage_unmount "$1"
	ipcrm -W
	#stage_clear_caches

	rename_staged_to_ready "$1"

	stop_jail "$1"
	unmount_data "$1" "$ZFS_JAIL_MNT/$1"
	unmount_ports "$ZFS_JAIL_MNT/$1"

	rename_active_to_last "$1"
	rename_ready_to_active "$1"
	add_jail_conf "$1"

	tell_status "service jail start $1"
	service jail start "$1" || exit
	proclaim_success "$1"
}

stage_pkg_install()
{
	echo "pkg -j $SAFE_NAME install -y $*"
	pkg -j "$SAFE_NAME" install -y "$@"
}

stage_sysrc()
{
	# don't use -j as this is oft called when jail is not running
	echo "sysrc -R $STAGE_MNT $*"
	sysrc -R "$STAGE_MNT" "$@"
}

stage_make_conf()
{
	if grep -s "$1" "$STAGE_MNT/etc/make.conf"; then
		echo "preserving make.conf settings"
		return
	fi

	echo "$2" | tee -a "$STAGE_MNT/etc/make.conf" || exit
}

stage_exec()
{
	echo "jexec $SAFE_NAME $*"
	jexec "$SAFE_NAME" "$@"
}

stage_mount_ports()
{
	echo "mount $STAGE_MNT/usr/ports"
	mount_nullfs /usr/ports "$STAGE_MNT/usr/ports" || exit
}

stage_mount_pkg_cache()
{
	echo "mount $STAGE_MNT/var/cache/pkg"
	mount_nullfs /var/cache/pkg "$STAGE_MNT/var/cache/pkg" || exit
}

unmount_ports()
{
	if [ ! -d "$1/usr/ports/mail" ]; then
		return
	fi

	if ! mount -t nullfs | grep -q "$1"; then
		return
	fi

	echo "unmount $1/usr/ports"
	umount "$1/usr/ports" || exit
}

unmount_pkg_cache()
{
	if ! mount -t nullfs | grep -q "$STAGE_MNT/var/cache/pkg"; then
		return
	fi

	echo "unmount $STAGE_MNT/var/cache/pkg"
	umount "$STAGE_MNT/var/cache/pkg" || exit
}

freebsd_release_url_base()
{
	echo "$FBSD_MIRROR/pub/FreeBSD/releases/$(uname -m)/$FBSD_REL_VER"
}

stage_fbsd_package()
{
	local _dest="$2"
	if [ -z "$_dest" ]; then _dest="$STAGE_MNT"; fi

	tell_status "downloading FreeBSD package $1"
	fetch -m "$(freebsd_release_url_base)/$1.txz" || exit
	echo "done"

	tell_status "extracting FreeBSD package $1.tgz"
	tar -C "$_dest" -xpJf "$1.txz" || exit
	echo "done"
}

has_data_fs()
{
	case $1 in
		clamav )   return 0;;
		avg )      return 0;;
		geoip )    return 0;;
		mysql )    return 0;;
		redis )    return 0;;
		vpopmail ) return 0;;
		webmail )  return 0;;
		nginx )    return 0;;
		lighttpd ) return 0;;
		apache )   return 0;;
		postgres ) return 0;;
		haproxy )  return 0;;
	esac

	return 1
}

mount_data()
{
	local _data_vol; _data_vol="$ZFS_DATA_VOL/$1"

	if ! zfs_filesystem_exists "$_data_vol"; then
		echo "no $_data_vol to mount"
		return
	fi

	local _data_mnt; _data_mnt="$ZFS_DATA_MNT/$1"
	local _data_mp;  _data_mp=$(data_mountpoint "$1" "$2")

	if [ ! -d "$_data_mp" ]; then
		echo "mkdir -p $_data_mp"
		mkdir -p "$_data_mp" || exit
	fi

	if mount -t nullfs | grep "$_data_mp"; then
		echo "$_data_mp already mounted!"
		return
	fi

	echo "mount_nullfs $_data_mnt $_data_mp"
	mount_nullfs "$_data_mnt" "$_data_mp" || exit
}

unmount_data()
{
	local _data_vol; _data_vol="$ZFS_DATA_VOL/$1"

	if ! zfs_filesystem_exists "$_data_vol"; then return; fi

	local _data_mp=; _data_mp=$(data_mountpoint "$1" "$2")

	if mount -t nullfs | grep "$_data_mp"; then
		echo "unmount data fs $_data_mp"
		umount -t nullfs "$_data_mp"
	fi
}

data_mountpoint()
{
	local _base_dir="$2"
	if [ -z "$_base_dir" ]; then
		_base_dir="$STAGE_MNT"  # default to stage
	fi

	case $1 in
		avg )       echo "$_base_dir/data/avg"; return ;;
		clamav )	echo "$_base_dir/var/db/clamav"; return ;;
		geoip )     echo "$_base_dir/usr/local/share/GeoIP"; return ;;
		mysql )     echo "$_base_dir/var/db/mysql"; return ;;
		vpopmail )  echo "$_base_dir/usr/local/vpopmail"; return ;;
	esac

	echo "$_base_dir/data"
}

stage_unmount_dev()
{
	if ! mount -t devfs | grep -q "$STAGE_MNT/dev"; then
		return
	fi
	echo "umount $STAGE_MNT/dev"
	umount "$STAGE_MNT/dev" || exit
}

get_public_facing_nic()
{
	export PUBLIC_NIC

	if [ "$1" = 'ipv6' ]; then
		PUBLIC_NIC=$(netstat -rn | grep default | awk '{ print $4 }' | tail -n1)
	else
		PUBLIC_NIC=$(netstat -rn | grep default | awk '{ print $4 }' | head -n1)
	fi

        if [ -z "$PUBLIC_NIC" ];
        then
            echo "public NIC detection failed"
            exit 1
        fi
}

get_public_ip()
{
	get_public_facing_nic "$1"

	export PUBLIC_IP6
	export PUBLIC_IP4

	if [ "$1" = 'ipv6' ]; then
		PUBLIC_IP6=$(ifconfig "$PUBLIC_NIC" | grep 'inet6' | grep -v fe80 | awk '{print $2}' | head -n1)
	else
		PUBLIC_IP4=$(ifconfig "$PUBLIC_NIC" | grep 'inet ' | awk '{print $2}' | head -n1)
	fi
}

mysql_db_exists()
{
	local _query="SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='$1';"
	result=$(echo "$_query" | jexec mysql mysql -s -N)
	if [ -z "$result" ]; then
		echo "$1 db does not exist"
		return 1
	else
		echo "$1 db exists"
		return 0
	fi
}

fetch_and_exec()
{
	local _toaster_sh="https://raw.githubusercontent.com/msimerson/Mail-Toaster-6/master"

	fetch -m "$_toaster_sh/provision-$1.sh"
	sh "provision-$1.sh"
}

provision()
{
	case "$1" in
		host)   fetch_and_exec "$1"; return;;
	esac

	if ! get_jail_ip "$1"; then
		echo "unknown jail $1"
		return;
	fi

	fetch_and_exec "$1"
}

reverse_list()
{
	# shellcheck disable=2068
	for _j in $@; do
		_rev_list="${_j} ${_rev_list}"
	done
	echo "$_rev_list"
}

unprovision_filesystems()
{
	for _j in $JAIL_ORDERED_LIST; do
		if [ -e "$ZFS_JAIL_VOL/$_j/dev/null" ]; then
			umount -t devfs "$ZFS_JAIL_VOL/$_j/dev"
		fi

		if zfs_filesystem_exists "$ZFS_JAIL_VOL/$_j"; then
			tell_status "destroying $ZFS_JAIL_VOL/$_j"
			zfs destroy "$ZFS_JAIL_VOL/$_j"
		fi

		if zfs_filesystem_exists "$ZFS_JAIL_VOL/$_j.ready"; then
			tell_status "destroying $ZFS_JAIL_VOL/$_j.ready"
			zfs destroy "$ZFS_JAIL_VOL/$_j.ready"
		fi

		if zfs_filesystem_exists "$ZFS_JAIL_VOL/$_j.last"; then
			tell_status "destroying $ZFS_JAIL_VOL/$_j.last"
			zfs destroy "$ZFS_JAIL_VOL/$_j.last"
		fi

		if has_data_fs "$_j"; then
			if zfs_filesystem_exists "$ZFS_DATA_VOL/$_j"; then
				tell_status "destroying $ZFS_DATA_MNT/$_j"
				zfs destroy "$ZFS_DATA_VOL/$_j"
			fi
		fi
	done

	if zfs_filesystem_exists "$ZFS_JAIL_VOL"; then
		tell_status "destroying $ZFS_JAIL_VOL"
		zfs destroy "$ZFS_JAIL_VOL"
	fi

	if zfs_filesystem_exists "$ZFS_DATA_VOL"; then
		tell_status "destroying $ZFS_DATA_VOL"
		zfs destroy "$ZFS_DATA_VOL"
	fi

	if zfs_filesystem_exists "$BASE_VOL"; then
		tell_status "destroying $BASE_VOL"
		zfs destroy -r "$BASE_VOL"
	fi
}

unprovision_files()
{
	for _f in /etc/jail.conf /etc/pf.conf /usr/local/sbin/jailmanage; do
		if [ -f "$_f" ]; then
			tell_status "rm $_f"
			rm "$_f"
		fi
	done

	if grep -q "^$JAIL_NET_PREFIX" /etc/hosts; then
		sed -i .bak -e "/^$JAIL_NET_PREFIX.*/d" /etc/hosts
	fi
}

unprovision()
{
	local _reversed; _reversed=$(reverse_list "$JAIL_ORDERED_LIST")

	if [ -f /etc/jail.conf ]; then
		for _j in $_reversed; do
			echo "$_j"
			service jail stop "$_j"
			sleep 1
		done
	fi

	ipcrm -W
	unprovision_filesystems
	unprovision_files
}

add_pf_portmap()
{
	sed -i .bak -e "/^block / a\
# map port $1 traffic to $2
rdr proto tcp from any to <ext_ips> port { $1 } -> $(get_jail_ip "$2") \
" /etc/pf.conf
}
