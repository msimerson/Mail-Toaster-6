#!/bin/sh

export MT6_TEST_ENV=${MT6_TEST_ENV:-0}

tell_status()
{
	echo; echo "   ***   $1   ***"; echo
	if [ -t 0 ] && [ "$MT6_TEST_ENV" != "1" ]; then sleep 1; fi
}

mt6-update()
{
	fetch "$TOASTER_SRC_URL/mail-toaster.sh"
	# shellcheck disable=SC1091
	. mail-toaster.sh
}

check_last_hour() {
	timestamp_file="${TMPDIR:-/tmp}/.mt6_fetch"
	current=$(date +%s)
	last=$(cat "$timestamp_file" 2>/dev/null || echo 0)

	if [ $((current - last)) -ge 3600 ]; then
		echo "$current" > "$timestamp_file"
		return 1  # Not within last hour (or first run)
	else
		return 0  # Within last hour
	fi
}

mt6-fetch()
{
	local _dir="$1"
	local _file="$2"

	if [ -z "$_dir" ] || [ -z "$_file" ]; then
		echo "FATAL: invalid args to mt6-fetch"; return 1
	fi

	if [ -d ".git" ]; then
		if ! check_last_hour; then
			tell_status "git repo, check status, skip fetch"
			git remote update && git status
		fi
		return
	fi

	if [ ! -d "$_dir" ]; then mkdir "$_dir"; fi

	fetch -o "$_dir" -m "$TOASTER_SRC_URL/$_dir/$2"
}

mt6-include()
{
	mt6-fetch include "$1.sh"

	if [ ! -f "include/$1.sh" ]; then
		echo "unable to download include/$1.sh"
		exit
	fi

	# shellcheck source=include/$.sh disable=SC1091
	. "include/$1.sh"
}

mt6_init()
{
	for _i in util config zfs jail network; do
		mt6-include "$_i"
	done

	mt6_defaults
	mt6_version_check
	# load the local config file
	config

	# Required settings
	export TOASTER_HOSTNAME=${TOASTER_HOSTNAME:="mail.example.com"} || exit 1
	export TOASTER_MAIL_DOMAIN=${TOASTER_MAIL_DOMAIN:="example.com"}
	export TOASTER_ADMIN_EMAIL=${TOASTER_ADMIN_EMAIL:="postmaster@$TOASTER_MAIL_DOMAIN"}

	# shellcheck disable=2009,2317
	if ps -o args= -p "$$" | grep csh; then
		echo; echo "ERROR: switch to sh or bash"; return 1; exit 1;
	fi
	echo "shell: $SHELL"

	if [ "$TOASTER_MYSQL" = "1" ]; then
		echo "mysql enabled"
	fi

	# shellcheck disable=2317
	if [ "$TOASTER_HOSTNAME" = "mail.example.com" ]; then
		usage TOASTER_HOSTNAME; return 1; exit 1
	fi
	echo "toaster host: $TOASTER_HOSTNAME"

	# shellcheck disable=2317
	if [ "$TOASTER_MAIL_DOMAIN" = "example.com" ]; then
		usage TOASTER_MAIL_DOMAIN; return 1; exit 1
	fi
	echo "email domain: $TOASTER_MAIL_DOMAIN"

	if [ -z "$JAIL_NET6" ]; then
		JAIL_NET6=$(get_random_ip6net)
		echo "export JAIL_NET6=\"$JAIL_NET6\"" >> mail-toaster.conf
		export JAIL_NET6
	fi

	# little below here should need customizing. If so, consider opening
	# an issue or PR at https://github.com/msimerson/Mail-Toaster-6
	export ZFS_JAIL_VOL="${ZFS_VOL}${ZFS_JAIL_MNT}"
	export ZFS_DATA_VOL="${ZFS_VOL}${ZFS_DATA_MNT}"

	export FBSD_REL_VER FBSD_PATCH_VER
	if [ "$(uname)" = 'FreeBSD' ]; then
		FBSD_REL_VER=$(/bin/freebsd-version | /usr/bin/cut -f1-2 -d'-')
		FBSD_PATCH_VER=$(/bin/freebsd-version | /usr/bin/cut -f3 -d'-')
		FBSD_PATCH_VER=${FBSD_PATCH_VER:="p0"}
	fi

	# the 'base' jail that other jails are cloned from. This will be named as the
	# host OS version, eg: base-13.2-RELEASE and the snapshot name will be the OS
	# patch level, eg: base-13.2-RELEASE@p3
	export BASE_NAME="base-$FBSD_REL_VER"
	export BASE_VOL="$ZFS_JAIL_VOL/$BASE_NAME"
	export BASE_SNAP="${BASE_VOL}@${FBSD_PATCH_VER}"
	export BASE_MNT="$ZFS_JAIL_MNT/$BASE_NAME"

	export STAGE_MNT="$ZFS_JAIL_MNT/stage"

	export SAFE_NAME; SAFE_NAME=$(safe_jailname stage)
	if [ -z "$SAFE_NAME" ]; then echo "unset SAFE_NAME"; exit; fi
}

export TOASTER_SRC_URL=${TOASTER_SRC_URL:="https://raw.githubusercontent.com/msimerson/Mail-Toaster-6/master"}

if [ "${MT6_TEST_ENV:-0}" != "1" ]; then
	mt6_init
fi

fatal_err() { echo; echo "FATAL: $1"; echo; exit 1; }

stage_unmount()
{
	for _fs in $(mount | grep stage | sort -u | awk '{ print $3 }'); do
		if [ "$(basename "$_fs")" = "stage" ]; then continue; fi
		echo "umount $_fs"
		umount "$_fs" || echo ""
	done

	# repeat, as sometimes a nested fs will prevent first try from success
	for _fs in $(mount | grep stage | sort -u | awk '{ print $3 }'); do
		if [ "$(basename "$_fs")" = "stage" ]; then continue; fi
		echo "umount $_fs"
		umount "$_fs"
	done

	if mount -t devfs | grep -q "$STAGE_MNT/dev"; then
		echo "umount $STAGE_MNT/dev"
		umount "$STAGE_MNT/dev"
	fi
}

cleanup_staged_fs()
{
	tell_status "stage cleanup"
	stop_jail stage
	stage_unmount "$1"
	zfs_destroy_fs "$ZFS_JAIL_VOL/stage" -f
}

install_fstab()
{
	_data_mount="$ZFS_DATA_MNT/$1"
	_jail_mount="$ZFS_JAIL_MNT/$1"
	_fstab="$ZFS_DATA_MNT/$1/etc/fstab"

	if [ ! -d "$_data_mount/etc" ]; then
		mkdir "$_data_mount/etc" || exit 1
	fi

	tell_status "writing data mount to $_fstab"
	echo "# Device                Mountpoint      FStype  Options         Dump    Pass#" | tee "$_fstab" || exit 1
	echo "$_data_mount       $_jail_mount/data nullfs  rw   0  0" | tee -a "$_fstab"
	echo "devfs               $_jail_mount/dev  devfs   rw   0  0" | tee -a "$_fstab"

	if [ -n "$JAIL_FSTAB" ]; then
		tell_status "appending JAIL_FSTAB to fstab"
		echo "$JAIL_FSTAB" | tee -a "$_fstab" || exit 1
	fi

	if [ "$TOASTER_USE_TMPFS" = 1 ]; then
		if ! grep -q "$_jail_mount/tmp" "$_fstab"; then
			tell_status "adding tmpfs to fstab"
			echo "tmpfs $_jail_mount/tmp     tmpfs rw,mode=01777,noexec,nosuid  0  0" | tee -a "$_fstab"
			echo "tmpfs $_jail_mount/var/run tmpfs rw,mode=01755,noexec,nosuid  0  0" | tee -a "$_fstab"
		fi
	fi

	sed -e "s|[[:space:]]$ZFS_JAIL_MNT/$1| $ZFS_JAIL_MNT/stage|" \
		"$_fstab" > \
		"$_fstab.stage" || exit 1

	tell_status "appending pkg & ports to fstab.stage"
	echo "/usr/ports         $STAGE_MNT/usr/ports       nullfs rw  0  0" | tee -a "$_fstab.stage"
	echo "/var/cache/pkg     $STAGE_MNT/var/cache/pkg   nullfs rw  0  0" | tee -a "$_fstab.stage"

	# copy staged fstab into place for jail shutdown
	if [ ! -d "$ZFS_DATA_MNT/stage/etc" ]; then
		mkdir -p "$ZFS_DATA_MNT/stage/etc" || exit 1
	fi
	cp "$_fstab.stage" "$ZFS_DATA_MNT/stage/etc/fstab" || exit 1
}

fstab_add_mount() {
	if [ -z "$3" ]; then
		echo "Error: invalid args to fstab_add_mount" >&2
		exit 1
	fi

	local jail_name="$1"
	local fs_path="$2"
	local mount_point="$3"
	local fs_type="${4:-nullfs}"
	local opts="${5:-rw}"
	local fstab="$ZFS_DATA_MNT/$jail_name/etc/fstab"

	for _file in "$fstab" "${fstab}.stage"; do
		if ! grep -qs "^$fs_path" "$_file"; then
			tell_status "adding $fs_path volume to $_file"
			printf "%s\t%s\t%s\t%s\t0\t0\n" "$fs_path" "$mount_point" "$fs_type" "$opts" | \
				tee -a "$_file"
		fi
	done
}

create_staged_fs()
{
	cleanup_staged_fs "$1"

	tell_status "stage jail filesystem setup"
	echo "zfs clone $BASE_SNAP $ZFS_JAIL_VOL/stage"
	zfs clone "$BASE_SNAP" "$ZFS_JAIL_VOL/stage" || exit 1
	if [ ! -d "$ZFS_JAIL_MNT/stage/data" ]; then
		mkdir "$ZFS_JAIL_MNT/stage/data" || exit 1
	fi

	if [ ! -d "$ZFS_JAIL_MNT/stage/data" ]; then
		tell_status "creating $ZFS_JAIL_MNT/stage/data"
		mkdir "$ZFS_JAIL_MNT/stage/data" || exit 1
	fi

	stage_sysrc hostname="$1"
	if [ -f "$STAGE_MNT/usr/local/etc/ssmtp/ssmtp.conf" ]; then
		sed -i '' -e "/^hostname=/ s/_HOSTNAME_/$1/" \
			"$STAGE_MNT/usr/local/etc/ssmtp/ssmtp.conf"
	fi

	assure_ip6_addr_is_declared "$1"
	stage_resolv_conf
	echo "MASQUERADE $1@$TOASTER_MAIL_DOMAIN" >> "$STAGE_MNT/etc/dma/dma.conf"

	zfs_create_fs "$ZFS_DATA_VOL/$1" "$ZFS_DATA_MNT/$1"
	install_fstab "$1"
	install_pfrule "$1"
	echo
}

start_staged_jail()
{
	local _name=${1:-"$SAFE_NAME"}
	local _path=${2:-"$STAGE_MNT"}
	local _fstab

	_fstab="$(get_jail_data "$_name")/etc/fstab"
	if [ "$_name" != "base" ]; then _fstab="$_fstab.stage"; fi

	tell_status "stage jail $_name startup"

	# shellcheck disable=2086
	jail -c \
		name=stage \
		host.hostname="$_name" \
		path="$_path" \
		interface="$JAIL_NET_INTERFACE" \
		ip4.addr="$(get_jail_ip stage)" \
		ip6.addr="$(get_jail_ip6 stage)" \
		exec.start="/bin/sh /etc/rc" \
		exec.stop="/bin/sh /etc/rc.shutdown" \
		mount.fstab="$_fstab" \
		devfs_ruleset=5 \
		$JAIL_START_EXTRA

	enable_bsd_cache

	tell_status "updating pkg database"
	pkg -j stage update
}

tell_settings()
{
	echo; echo "   ***   Configured $1 settings:   ***"; echo
	set | grep "^$1_"
	echo
	if [ -t 0 ] && [ "$MT6_TEST_ENV" != "1" ]; then sleep 2; fi
}

proclaim_success()
{
	echo; echo "Success! A new '$1' jail is provisioned"; echo
}

stage_clear_caches()
{
	for _c in "$STAGE_MNT/var/cache/pkg" "$STAGE_MNT/var/db/freebsd-update"
	do
		echo "clearing cache ($_c)"
		rm -rf "${_c:?}"/*
	done
}

stage_resolv_conf()
{
	if ! jail_is_running dns; then return; fi

	tell_status "configuring DNS for local recursor"
	echo "nameserver $(get_jail_ip  dns)" >  "$STAGE_MNT/etc/resolv.conf"
	echo "nameserver $(get_jail_ip6 dns)" >> "$STAGE_MNT/etc/resolv.conf"
}

seed_pkg_audit()
{
	if [ "$TOASTER_PKG_AUDIT" = "1" ]; then
		tell_status "installing FreeBSD package audit database"
		stage_exec /usr/sbin/pkg audit -F || echo ''
	fi
}

promote_staged_jail()
{
	seed_pkg_audit
	tell_status "promoting jail $1"
	stop_jail stage
	stage_clear_caches
	stage_unmount "$1"
	ipcrm -W

	rename_staged_to_ready "$1"

	stop_jail "$1"

	rename_active_to_last "$1"
	rename_ready_to_active "$1"
	add_jail_conf "$1"
	#add_automount "$1"

	tell_status "service jail start $1"
	service jail start "$1" || exit 1
	enable_jail "$1"
	proclaim_success "$1"
}

stage_pkg_install()
{
	echo "pkg -j $SAFE_NAME install -y $*"
	pkg -j "$SAFE_NAME" install -y "$@"
}

stage_port_install()
{
	# $1 is the port directory (eg: mail/dovecot)

	stage_pkg_install pkgconf portconfig

	stage_exec make -C "/usr/ports/$1" build deinstall install clean || return 1

	tell_status "port $1 installed"
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

	tell_status "setting $1 make.conf options"
	echo "$2" | tee -a "$STAGE_MNT/etc/make.conf" || exit
}

stage_exec()
{
	echo "jexec $SAFE_NAME $*"
	jexec "$SAFE_NAME" "$@"
}

stage_listening()
{
	local _port=${1:-"25"}
	local _max_tries=${2:-"3"}
	local _sleep=${3:-"1"}
	local _try=0

	echo; echo -n "checking for port $_port listening in staged jail..."

	until port_is_listening "$_port"; do
		_try=$((_try + 1))

		if [ "$_try" -gt "$_max_tries" ]; then
			echo "FAILED"
			exit 1
		fi
		echo -n "."
		sleep "$_sleep"
	done

	echo "OK"; echo
}

stage_test_running()
{
	echo "checking for process $1 in staged jail"
	pgrep -j stage "$1" || exit
	echo "ok"
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
	_major_ver="$(/bin/freebsd-version | cut -f1 -d.)"
	if [ "$_major_ver" -lt "13" ]; then
		echo "http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases"
	else
		echo "ftp://ftp.freebsd.org/pub/FreeBSD/releases"
	fi
}

stage_fbsd_package()
{
	local _dest="$2"
	if [ -z "$_dest" ]; then _dest="$STAGE_MNT"; fi

	_file_uri="$(freebsd_release_url_base)/$(uname -m)/$FBSD_REL_VER/$1.txz"
	tell_status "downloading $_file_uri"
	fetch -m "$_file_uri" || exit
	echo "done"

	tell_status "extracting FreeBSD package $1.tgz to $_dest"
	tar -C "$_dest" -xpJf "$1.txz" || exit
	echo "done"
}

stage_setup_tls()
{
	# static TLS certificates (installed at deploy)
	if [ ! -f "$STAGE_MNT/etc/ssl/certs/${TOASTER_MAIL_DOMAIN}.pem" ]; then
		tell_status "installing TLS certificate"
		cp /etc/ssl/certs/server.crt "$STAGE_MNT/etc/ssl/certs/${TOASTER_MAIL_DOMAIN}.pem"
		cp /etc/ssl/private/server.key "$STAGE_MNT/etc/ssl/private/${TOASTER_MAIL_DOMAIN}.pem"
	fi

	# dynamic TLS certs, kept up-to-date by acme.sh or certbot
	if [ ! -f "$STAGE_MNT/data/etc/tls/certs" ]; then
		# shellcheck disable=SC2174
		mkdir -m 0644 -p "$STAGE_MNT/data/etc/tls/certs"
		cp /etc/ssl/certs/server.crt "$STAGE_MNT/data/etc/tls/certs/${TOASTER_MAIL_DOMAIN}.pem"
	fi

	if [ ! -f "$STAGE_MNT/data/etc/tls/private" ]; then
		# shellcheck disable=SC2174
		mkdir -m 0640 -p "$STAGE_MNT/data/etc/tls/private"
		cp /etc/ssl/private/server.key "$STAGE_MNT/data/etc/tls/private/${TOASTER_MAIL_DOMAIN}.pem"
	fi
}

stage_enable_newsyslog()
{
	tell_status "enabling newsyslog"
	sysrc -f "$STAGE_MNT/etc/rc.conf" newsyslog_enable=YES
	if [ ! -d "$STAGE_MNT/usr/local/etc/newsyslog.conf.d" ]; then
		mkdir "$STAGE_MNT/usr/local/etc/newsyslog.conf.d"
	fi
	sed -i.bak \
		-e '/^#0.*newsyslog/ s/^#0/0/' \
		"$STAGE_MNT/etc/crontab"
}

unmount_data()
{
	# $1 is ZFS fs (eg: /data/mysql)
	local _data_vol; _data_vol="$ZFS_DATA_VOL/$1"

	if ! zfs_filesystem_exists "$_data_vol"; then return; fi

	local _data_mp="$STAGE_MNT/data"
	if mount -t nullfs | grep -q "$_data_mp"; then
		tell_status "unmounting data fs $_data_mp"
		umount -t nullfs "$_data_mp"
	fi
}

fetch_and_exec()
{
	mt6-fetch provision "$1.sh"
	sh "provision/$1.sh"
}

install_sentry()
{
	if [ -z "$TOASTER_SENTRY" ]; then
		echo "TOASTER_SENTRY unset, skipping sentry"
		return
	fi

	tell_status "installing sentry"
	stage_pkg_install perl5 p5-Net-IP
	stage_exec mkdir /var/db/sentry || exit
	stage_exec fetch -o /var/db/sentry/sentry.pl --no-verify-peer https://raw.githubusercontent.com/msimerson/sentry/master/sentry.pl
	stage_exec perl /var/db/sentry/sentry.pl --update

	if [ -n "$TOASTER_NRPE" ]; then
		tell_status "installing nagios sentry plugin"
		stage_pkg_install nagios-plugins || exit
		stage_exec fetch -o /usr/local/libexec/nagios/check_sentry $TOASTER_SRC_URL/contrib/check_sentry
	fi
}

provision_mt6()
{
	for _j in host base dns mysql redis clamav dcc geoip vpopmail rspamd spamassassin dovecot haraka haproxy webmail roundcube snappymail mailtest; do
		fetch_and_exec "$_j" || break
	done
}

provision_skeleton()
{
	if [ -z "$3" ]; then
		echo "Usage:"; echo; echo "provision skel NAME IPv4 IPv6"; echo
		return
	fi

	mt6-fetch provision "skel.sh"
	sed -e "s/_skel/_$2/g" -e "s/ skel/ $2/g" provision/skel.sh > "provision/$2.sh"

	local _ucl="$ZFS_DATA_MNT/dns/unbound.conf.local"
	if ! grep -qs "$2" "$_ucl"; then
		tell_status "adding DNS for $2"
		tee -a "$_ucl" <<EO_UB_CONF

	local-data: "$2		A $3"
	local-data: "$2		AAAA $4"
	local-data: "$(echo "$3" | awk '{split($1,a,".");printf("%s.%s.%s.%s",a[4],a[3],a[2],a[1])}').in-addr.arpa	PTR $2"
	local-data: "$(echo "$4" | sed -e 's/://g' | rev | sed -e 's/./&./g')ip6.arpa	PTR $2"

EO_UB_CONF
		jexec dns service unbound reload
	fi

	sh "provision/$2.sh"
}

provision()
{
	for _var in JAIL_START_EXTRA JAIL_CONF_EXTRA JAIL_FSTAB; do
		unset "$_var"
	done

	case "$1" in
		host) fetch_and_exec "$1"; return;;
		web)  for _j in haproxy webmail roundcube snappymail; do fetch_and_exec "$_j"; done
			return;;
		mt6)  provision_mt6; return;;
	esac

	if ! get_jail_ip "$1"; then
		if [ "$1" = "skel" ]; then
			provision_skeleton "$@"
		else
			echo "unknown jail $1"
		fi
		return
	fi

	fetch_and_exec "$1"
}

unprovision_last()
{
	for _j in $JAIL_ORDERED_LIST; do
		if zfs_filesystem_exists "$ZFS_JAIL_VOL/$_j.last"; then
			tell_status "destroying $ZFS_JAIL_VOL/$_j.last"
			zfs destroy "$ZFS_JAIL_VOL/$_j.last"
		fi
	done
}

unprovision_filesystem()
{
	if zfs_filesystem_exists "$ZFS_JAIL_VOL/$1.ready"; then
		tell_status "destroying $ZFS_JAIL_VOL/$1.ready"
		zfs destroy "$ZFS_JAIL_VOL/$1.ready" || return 1
	fi

	if zfs_filesystem_exists "$ZFS_JAIL_VOL/$1.last"; then
		tell_status "destroying $ZFS_JAIL_VOL/$1.last"
		zfs destroy "$ZFS_JAIL_VOL/$1.last"  || return 1
	fi

	if [ -e "$ZFS_JAIL_VOL/$1/dev/null" ]; then
		umount -t devfs "$ZFS_JAIL_VOL/$1/dev"  || return 1
	fi

	if zfs_filesystem_exists "$ZFS_DATA_VOL/$1"; then
		tell_status "destroying $ZFS_DATA_MNT/$1"
		unmount_data "$1" || return 1
		zfs destroy "$ZFS_DATA_VOL/$1" || return 1
	fi

	if zfs_filesystem_exists "$ZFS_JAIL_VOL/$1"; then
		tell_status "destroying $ZFS_JAIL_VOL/$1"
		zfs destroy "$ZFS_JAIL_VOL/$1" || return 1
	fi
}

unprovision_filesystems()
{
	for _j in $JAIL_ORDERED_LIST; do
		unprovision_filesystem "$_j" || return 1
	done

	if zfs_filesystem_exists "$ZFS_JAIL_VOL"; then
		tell_status "destroying $ZFS_JAIL_VOL"
		zfs destroy "$ZFS_JAIL_VOL" || return 1
	fi

	if zfs_filesystem_exists "$ZFS_DATA_VOL"; then
		tell_status "destroying $ZFS_DATA_VOL"
		zfs destroy "$ZFS_DATA_VOL" || return 1
	fi

	if zfs_filesystem_exists "$BASE_VOL"; then
		tell_status "destroying $BASE_VOL"
		zfs destroy -r "$BASE_VOL" || return 1
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
		sed -i.bak -e "/^$JAIL_NET_PREFIX.*/d" /etc/hosts
	fi
}

unprovision_rc()
{
	tell_status "disabling jail $1 startup"
	sysrc jail_list-=" $1"
	sysrc -f /etc/periodic.conf security_status_pkgaudit_jails-=" $1"

	if [ -f /etc/jail.conf.d/$1.conf ]; then
		tell_status "deleting /etc/jail.conf.d/$1.conf"
		rm "/etc/jail.conf.d/$1.conf"
	fi
}

unprovision()
{
	if [ -n "$1" ]; then

		if [ "$1" = "last" ]; then
			unprovision_last
			return
		fi

		service jail stop stage "$1"
		unprovision_filesystem "$1" || return 1
		unprovision_rc "$1"
		return
	fi

	service jail stop
	sleep 1

	ipcrm -W
	unprovision_filesystems
	unprovision_files
	for _j in $JAIL_ORDERED_LIST; do unprovision_rc "$_j"; done
	echo "done"
}

# shellcheck disable=3044,3018
onexit() { while caller $((n++)); do :; done; }

if [ "$TOASTER_BUILD_DEBUG" = "1" ]; then
	trap onexit EXIT
fi

