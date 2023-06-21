#!/bin/sh

# bump version when a change in this file effects a provision script(s)
mt6_version() { echo "20230507"; }

dec_to_hex() { printf '%04x\n' "$1"; }

sed_replacement_quote() { printf "%s" "$1" | sed -E 's,([&\\/]),\\\1,g'; }

get_random_ip6net()
{
	# shellcheck disable=2039
	local RAND16
	RAND16=$(od -t uI -N 2 /dev/urandom | awk '{print $2}')
	echo "fd7a:e5cd:1fc1:$(dec_to_hex "$RAND16"):dead:beef:cafe"
}

tell_status()
{
	echo; echo "   ***   $1   ***"; echo
	sleep 1
}

store_config()
{
	# $1 - path to config file, $2 - overwrite, STDIN is file contents
	if [ ! -d "$(dirname $1)" ]; then
		tell_status "creating $(dirname $1)"
		mkdir -p "$(dirname $1)" || exit 1
	fi

	cat - > "$1.mt6" || exit 1

	if [ ! -f "$1" ] || [ -n "$2" ]; then
		tell_status "installing $1"
		cp "$1.mt6" "$1" || exit 1
	else
		tell_status "preserving $1"
	fi
}

create_default_config()
{
	local _HOSTNAME
	local _EMAIL_DOMAIN
	local _ORGNAME

	if [ -t 0 ] && [ "$(uname)" = 'FreeBSD' ]; then
		echo "editing prefs"
		_HOSTNAME=$(dialog --stdout --nocancel --backtitle "mail-toaster.sh" --title TOASTER_HOSTNAME --inputbox "the hostname of this [virtual] machine" 8 70 "mail.example.com")
		_EMAIL_DOMAIN=$(dialog --stdout --nocancel --backtitle "mail-toaster.sh" --title TOASTER_MAIL_DOMAIN --inputbox "the primary email domain" 8 70 "example.com")
		_ORGNAME=$(dialog --stdout --nocancel --backtitle "mail-toaster.sh" --title TOASTER_ORG_NAME --inputbox "the name of your organization" 8 70 "Email Inc")
	fi

	# for dev/test environs where dialog doesn't exist
	if [ -z "$_HOSTNAME"     ]; then _HOSTNAME=$(hostname); fi
	if [ -z "$_EMAIL_DOMAIN" ]; then _EMAIL_DOMAIN=$(hostname); fi
	if [ -z "$_ORGNAME"      ]; then _ORGNAME="Sparky the Toaster"; fi

	echo "creating mail-toaster.conf with defaults"
	store_config mail-toaster.conf <<EO_MT_CONF
export TOASTER_ORG_NAME="$_ORGNAME"
export TOASTER_HOSTNAME="$_HOSTNAME"
export TOASTER_MAIL_DOMAIN="$_EMAIL_DOMAIN"
export TOASTER_ADMIN_EMAIL="postmaster@${_EMAIL_DOMAIN}"
export TOASTER_SRC_URL="https://raw.githubusercontent.com/msimerson/Mail-Toaster-6/master"

# If your hosts public facing IP(s) are not bound to a local interface, configure it here.
# Haraka determines it at runtime (with STUN) but the DNS configuration cannot
export PUBLIC_IP4=""
export PUBLIC_IP6=""

export JAIL_NET_PREFIX="172.16.15"
export JAIL_NET_MASK="/12"
export JAIL_NET_INTERFACE="lo1"
export JAIL_NET6="$(get_random_ip6net)"
export ZFS_VOL="zroot"
export ZFS_JAIL_MNT="/jails"
export ZFS_DATA_MNT="/data"
export TOASTER_MARIADB="0"
export TOASTER_MSA="haraka"
export TOASTER_MYSQL="1"
export TOASTER_MYSQL_PASS=""
export TOASTER_NRPE=""
export TOASTER_PKG_AUDIT="0"
export TOASTER_PKG_BRANCH="latest"
export TOASTER_QMHANDLE="0"
export TOASTER_SENTRY=""
export TOASTER_USE_TMPFS="0"
export TOASTER_VPOPMAIL_EXT="0"
export CLAMAV_FANGFRISCH="0"
export CLAMAV_UNOFFICIAL="0"
export MAXMIND_LICENSE_KEY=""
export ROUNDCUBE_SQL="0"
export ROUNDCUBE_DEFAULT_HOST=""
export ROUNDCUBE_PRODUCT_NAME="Roundcube Webmail"
export ROUNDCUBE_ATTACHMENT_SIZE_MB="25"
export SQUIRREL_SQL="0"

EO_MT_CONF

	chmod 600 mail-toaster.conf
}

config()
{
	if [ ! -f "mail-toaster.conf" ]; then
		create_default_config
	fi

	local _mode; _mode=$(stat -f "%OLp" mail-toaster.conf)
	if [ "$_mode" -ne 600 ]; then
		echo "tightening permissions on mail-toaster.conf"
		chmod 600 mail-toaster.conf
	fi

	echo "loading mail-toaster.conf"
	# shellcheck disable=SC1091,SC2039
	. mail-toaster.conf
}

mt6-update()
{
	fetch "$TOASTER_SRC_URL/mail-toaster.sh"
	# shellcheck disable=SC1091
	. mail-toaster.sh
}

mt6_version_check()
{
	if [ "$(uname)" != 'FreeBSD' ]; then return; fi

	if [ -d ".git" ]; then echo "v: $(mt6_version)"; return; fi

	local _github
	_github=$(fetch -o - -q "$TOASTER_SRC_URL/mail-toaster.sh" | grep '^mt6_version(' | cut -f2 -d'"')
	if [ -z "$_github" ]; then
		echo "v: <failed lookup>"
		return
	else
		echo "v: $_github"
	fi

	local _this
	_this="$(mt6_version)";
	if [ -n "$_this" ] && [ "$_this" -lt "$_github" ]; then
		echo "NOTICE: updating mail-toaster.sh"
		mt6-update
	fi
}

export TOASTER_SRC_URL=${TOASTER_SRC_URL:="https://raw.githubusercontent.com/msimerson/Mail-Toaster-6/master"}

mt6_version_check
# load the local config file
config

# Required settings
export TOASTER_HOSTNAME=${TOASTER_HOSTNAME:="mail.example.com"} || exit
export TOASTER_MAIL_DOMAIN=${TOASTER_MAIL_DOMAIN:="example.com"}
export TOASTER_ADMIN_EMAIL=${TOASTER_ADMIN_EMAIL:="postmaster@$TOASTER_MAIL_DOMAIN"}

# export these in your environment to customize
export BOURNE_SHELL=${BOURNE_SHELL:="bash"}
export JAIL_NET_PREFIX=${JAIL_NET_PREFIX:="172.16.15"}
export JAIL_NET_MASK=${JAIL_NET_MASK:="/12"}
export JAIL_NET_INTERFACE=${JAIL_NET_INTERFACE:="lo1"}
export JAIL_ORDERED_LIST="syslog base dns mysql clamav spamassassin dspam vpopmail haraka webmail munin haproxy rspamd avg dovecot redis geoip nginx mailtest apache postgres minecraft joomla php7 memcached sphinxsearch elasticsearch nictool sqwebmail dhcp letsencrypt tinydns roundcube squirrelmail rainloop rsnapshot mediawiki smf wordpress whmcs squirrelcart horde grafana unifi mongodb gitlab gitlab_runner dcc prometheus influxdb telegraf statsd mail_dmarc ghost jekyll borg nagios postfix puppeteer snappymail knot nsd bsd_cache"

export ZFS_VOL=${ZFS_VOL:="zroot"}
export ZFS_JAIL_MNT=${ZFS_JAIL_MNT:="/jails"}
export ZFS_DATA_MNT=${ZFS_DATA_MNT:="/data"}
export FBSD_MIRROR=${FBSD_MIRROR:="ftp://ftp.freebsd.org"}

# See https://github.com/msimerson/Mail-Toaster-6/wiki/MySQL
export TOASTER_MYSQL=${TOASTER_MYSQL:="1"}
export TOASTER_MARIADB=${TOASTER_MARIADB:="0"}
export TOASTER_NTP=${TOASTER_NTP:="ntp"}
export TOASTER_MSA=${TOASTER_MSA:="haraka"}
export TOASTER_PKG_AUDIT=${TOASTER_PKG_AUDIT:="0"}
export TOASTER_PKG_BRANCH=${TOASTER_PKG_BRANCH:="latest"}
export TOASTER_VPOPMAIL_EXT=${TOASTER_VPOPMAIL_EXT:="0"}
export CLAMAV_FANGFRISCH=${CLAMAV_FANGFRISCH:="0"}
export CLAMAV_UNOFFICIAL=${CLAMAV_UNOFFICIAL:="0"}
export ROUNDCUBE_SQL=${ROUNDCUBE_SQL:="$TOASTER_MYSQL"}
export ROUNDCUBE_PRODUCT_NAME=${ROUNDCUBE_PRODUCT_NAME:="Roundcube Webmail"}
export ROUNDCUBE_ATTACHMENT_SIZE_MB=${ROUNDCUBE_ATTACHMENT_SIZE_MB:="25"}
export SQUIRREL_SQL=${SQUIRREL_SQL:="$TOASTER_MYSQL"}

if [ "$TOASTER_MYSQL" = "1" ]; then
	echo "mysql enabled"
fi

usage()
{
	if [ -n "$1" ]; then echo; echo "ERROR: missing required $1"; echo; fi
	echo; echo "Next step, edit mail-toaster.conf!"; echo
	echo "See: https://github.com/msimerson/Mail-Toaster-6/wiki/FreeBSD"; echo
	exit
}
if [ "$TOASTER_HOSTNAME" = "mail.example.com" ]; then usage TOASTER_HOSTNAME; fi
echo "toaster host: $TOASTER_HOSTNAME"

if [ "$TOASTER_MAIL_DOMAIN" = "example.com" ]; then usage TOASTER_MAIL_DOMAIN; fi
echo "email domain: $TOASTER_MAIL_DOMAIN"

if [ -z "$JAIL_NET6" ]; then
	JAIL_NET6=$(get_random_ip6net)
	echo "export JAIL_NET6=\"$JAIL_NET6\"" >> mail-toaster.conf
	export JAIL_NET6
fi
echo "IPv6 jail network: $JAIL_NET6"

# shellcheck disable=2009
if ps -o args= -p "$$" | grep csh; then usage; fi
echo "shell: $SHELL"

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
# host OS version, ex: base-13.0-RELEASE and the snapshot name will be the OS
# patch level, ex: base-13.0-RELEASE@p3
export BASE_NAME="base-$FBSD_REL_VER"
export BASE_VOL="$ZFS_JAIL_VOL/$BASE_NAME"
export BASE_SNAP="${BASE_VOL}@${FBSD_PATCH_VER}"
export BASE_MNT="$ZFS_JAIL_MNT/$BASE_NAME"

export STAGE_MNT="$ZFS_JAIL_MNT/stage"

fatal_err() { echo; echo "FATAL: $1"; echo; exit; }

safe_jailname()
{
	# constrain jail name chars to alpha-numeric and _
	# shellcheck disable=SC2001
	echo "$1" | sed -e 's/[^a-zA-Z0-9]/_/g'
}

export SAFE_NAME; SAFE_NAME=$(safe_jailname stage)
if [ -z "$SAFE_NAME" ]; then echo "unset SAFE_NAME"; exit; fi
echo "safe name: $SAFE_NAME"

zfs_filesystem_exists()
{
	zfs list -t filesystem "$1" 2>/dev/null | grep -q "^$1" || return 1
	tell_status "$1 filesystem exists"
	return 0
}

zfs_snapshot_exists()
{
	zfs list -t snapshot "$1" 2>/dev/null | grep -q "$1" || return 1
	echo "$1 snapshot exists"
	return 0
}

zfs_mountpoint_exists()
{
	zfs list -t filesystem "$1" 2>/dev/null | grep -q "$1\$" || return 1
	echo "$1 mountpoint exists"
	return 0
}

zfs_create_fs()
{
	if zfs_filesystem_exists "$1"; then return; fi
	if zfs_mountpoint_exists "$2"; then return; fi

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
	cat <<EO_JAIL_CONF_HEAD
exec.start = "/bin/sh /etc/rc";
exec.stop = "/bin/sh /etc/rc.shutdown";
exec.clean;
mount.devfs;
devfs_ruleset=5;
path = "$ZFS_JAIL_MNT/\$name";
interface = $JAIL_NET_INTERFACE;
host.hostname = \$name;

EO_JAIL_CONF_HEAD
}

get_jail_ip()
{
	local _start=${JAIL_NET_START:=1}

	case "$1" in
		syslog) echo "$JAIL_NET_PREFIX.$_start";   return;;
		base)   echo "$JAIL_NET_PREFIX.$((_start + 1))";   return;;
		stage)  echo "$JAIL_NET_PREFIX.254"; return;;
	esac

	if echo "$1" | grep -q ^base; then
		echo "$JAIL_NET_PREFIX.$((_start + 1))"
		return
	fi

	local _octet="$_start"

	for _j in $JAIL_ORDERED_LIST; do
		if [ "$1" = "$_j" ]; then
			echo "$JAIL_NET_PREFIX.$_octet"
			return
		fi
		_octet=$((_octet + 1))
	done

	_dns=$(host "$1" | grep 'has address' | cut -f4 -d' ')
	if [ -n "$_dns" ]; then
		echo "$_dns"
		return
	fi

	# return error code
	return 2
}

get_jail_ip6()
{
	local _start=${JAIL_NET_START:=1}

	case "$1" in
		syslog) echo "$JAIL_NET6:$(dec_to_hex "$_start")";       return;;
		base)   echo "$JAIL_NET6:$(dec_to_hex $((_start + 1)))"; return;;
		stage)  echo "$JAIL_NET6:$(dec_to_hex 254)";             return;;
	esac

	if echo "$1" | grep -q ^base; then
		echo "$JAIL_NET6:$(dec_to_hex $((_start + 1)))"
		return
	fi

	local _octet="$_start"

	for _j in $JAIL_ORDERED_LIST; do
		if [ "$1" = "$_j" ]; then
			echo "$JAIL_NET6:$(dec_to_hex "$_octet")"
			return
		fi
		_octet=$((_octet + 1))
	done

	_dns=$(host "$1" | grep 'has IPv6 address' | cut -f5 -d' ')
	if [ -n "$_dns" ]; then
		echo "$_dns"
		return
	fi

	# return error code
	return 2
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

get_reverse_ip6()
{
	_rev_ip=$(get_jail_ip6 "$1" | sed -e 's/://g' | rev | sed -e 's/./&./g')
	echo "${_rev_ip}ip6.arpa"
}

add_jail_conf()
{
	local _jail_ip; _jail_ip=$(get_jail_ip "$1");
	if [ -z "$_jail_ip" ]; then
		fatal_err "can't determine IP for $1"
	fi

	if [ -d /etc/jail.conf.d ]; then
		add_jail_conf_d $1
		return
	fi

	if [ ! -e /etc/jail.conf ]; then
		tell_status "adding /etc/jail.conf header"
		jail_conf_header | tee -a /etc/jail.conf
	fi

	if grep -q "^$1\\>" /etc/jail.conf; then
		tell_status "preserving $1 config in /etc/jail.conf"
		return
	fi

	jail_conf_extra $1

	tell_status "adding $1 to /etc/jail.conf"
	echo "$1	{$(get_safe_jail_path $1)
		ip4.addr = $JAIL_NET_INTERFACE|${_jail_ip};
		ip6.addr = $JAIL_NET_INTERFACE|$(get_jail_ip6 $1);${JAIL_CONF_EXTRA}
	}" | tee -a /etc/jail.conf
}

get_safe_jail_path()
{
	local _safe; _safe=$(safe_jailname "$1")
	if [ "$1" != "$_safe" ]; then
		echo "
		path = $ZFS_JAIL_MNT/${1};"
	else
		echo ""
	fi
}

jail_conf_extra()
{
	# if not present, add data mount
	if ! echo "$JAIL_CONF_EXTRA" | grep -q "mount += \"$ZFS_DATA_MNT/$1"; then
		JAIL_CONF_EXTRA="$JAIL_CONF_EXTRA
		mount += \"$ZFS_DATA_MNT/$1 \$path/data nullfs rw 0 0\";"
	fi

	if [ "$TOASTER_USE_TMPFS" = 1 ]; then
		JAIL_CONF_EXTRA="$JAIL_CONF_EXTRA
		mount += \"tmpfs \$path/tmp tmpfs rw,mode=01777,noexec,nosuid 0 0\";
		mount += \"tmpfs \$path/var/run tmpfs rw,mode=01755,noexec,nosuid 0 0\";"
	fi
}

add_jail_conf_d()
{
	if [ -f "/etc/jail.conf.d/$1.conf" ]; then
		tell_status "preserving jail config /etc/jail.conf.d/$1.conf"
		return
	fi

	jail_conf_extra $1

	tell_status "creating /etc/jail.conf.d/$1.conf"
	echo "$(jail_conf_header)

$1	{$(get_safe_jail_path $1)
		ip4.addr = $JAIL_NET_INTERFACE|${_jail_ip};
		ip6.addr = $JAIL_NET_INTERFACE|$(get_jail_ip6 $1);${JAIL_CONF_EXTRA}
		exec.created = \"$ZFS_DATA_MNT/$1/etc/pf.conf.d/pfrule.sh load\";
		exec.poststop = \"$ZFS_DATA_MNT/$1/etc/pf.conf.d/pfrule.sh unload\";
	}" | tee -a /etc/jail.conf.d/$1.conf
}

add_automount()
{
	if grep -qs auto_ports /etc/auto_master; then
		if grep -qs "^$ZFS_JAIL_MNT/$1/" /etc/auto_ports; then
			tell_status "automount ports already configured"
		else
			tell_status "enabling /usr/ports automount"
			echo "$ZFS_JAIL_MNT/$1/usr/ports		-fstype=nullfs :/usr/ports" | tee -a /etc/auto_ports
			/usr/sbin/automount
		fi
	else
		echo "automount not enabled, see https://github.com/msimerson/Mail-Toaster-6/wiki/automount"
	fi

	if grep -qs auto_pkgcache /etc/auto_master; then
		if grep -qs "^$ZFS_JAIL_MNT/$1/" /etc/auto_pkgcache; then
			tell_status "automount pkg cache already configured"
		else
			tell_status "enabling /var/cache/pkg automount"
			echo "$ZFS_JAIL_MNT/$1/var/cache/pkg		-fstype=nullfs :/var/cache/pkg" | tee -a /etc/auto_pkgcache
			/usr/sbin/automount
		fi
	fi
}

stop_jail()
{
	tell_status "stopping jail $1"
	local _safe; _safe=$(safe_jailname "$1")
	if jls -j $_safe -d 2>/dev/null | grep -q $_safe; then
		echo "service jail stop $_safe"
		service jail stop "$_safe"
	fi

	echo "jail -r $_safe"
	jail -r "$_safe" 2>/dev/null
}

stage_unmount()
{
	stage_unmount_dev
	unmount_ports "$STAGE_MNT"
	unmount_pkg_cache
	unmount_data "$1"
	stage_unmount_aux_data "$1"
}

cleanup_staged_fs()
{
	tell_status "stage cleanup"
	stop_jail stage
	stage_unmount "$1"
	zfs_destroy_fs "$ZFS_JAIL_VOL/stage" -f
}

assure_data_volume_mount_is_declared()
{
	_cnf="/etc/jail.conf.d/$1.conf"

	# config for this jail might not be created yet
	# (created when the data FS is provisioned)
	if [ -f "$_cnf" ]; then
		if ! grep -qs "^$1" "$_cnf"; then return; fi
	elif [ -f /etc/jail.conf ]; then
		_cnf="/etc/jail.conf"
		if ! grep -qs "^$1" "$_cnf"; then return; fi
	else
		return
	fi

	if grep -qs "data/$1" "$_cnf"; then
		# data fs mountpoint already declared
		return
	fi

	local _mp; _mp=$(data_mountpoint "$1" "\$path")
	tell_status "roadblock: UPGRADE action required"
	echo
	echo "You MUST add this line to the $1 section in /etc/jail.conf to continue:"
	echo
	echo "	mount += \"/data/$1 $_mp nullfs rw 0 0\";"
	echo
	exit
}

install_pfrule()
{
	tell_status "setting up etc/pf.conf.d"

	if [ ! -d "$STAGE_MNT/data/etc/pf.conf.d" ]; then
		mkdir -p "$STAGE_MNT/data/etc/pf.conf.d" || exit 1
	fi
	fetch -m -o "$STAGE_MNT/data/etc/pf.conf.d/pfrule.sh" \
		"$TOASTER_SRC_URL/contrib/pfrule.sh" || exit 1
	chmod 755 "$STAGE_MNT/data/etc/pf.conf.d/pfrule.sh" || exit 1
}

create_staged_fs()
{
	cleanup_staged_fs "$1"

	tell_status "stage jail filesystem setup"
	echo "zfs clone $BASE_SNAP $ZFS_JAIL_VOL/stage"
	zfs clone "$BASE_SNAP" "$ZFS_JAIL_VOL/stage" || exit

	stage_sysrc hostname="$1"
	sed -i '' -e "/^hostname=/ s/_HOSTNAME_/$1/" \
		"$STAGE_MNT/usr/local/etc/ssmtp/ssmtp.conf" || exit

	assure_data_volume_mount_is_declared "$1"
	assure_ip6_addr_is_declared "$1"

	zfs_create_fs "$ZFS_DATA_VOL/$1" "$ZFS_DATA_MNT/$1"
	mount_data "$1" "$STAGE_MNT" || exit 1

	install_pfrule

	stage_mount_ports
	stage_mount_pkg_cache
	echo
}

stage_unmount_aux_data()
{
	case "$1" in
		spamassassin)  unmount_data geoip ;;
		haraka)        unmount_data geoip ;;
		whmcs )        unmount_data geoip ;;
	esac
}

stage_mount_aux_data()
{
	case "$1" in
		spamassassin )  mount_data geoip ;;
		haraka )        mount_data geoip ;;
		whmcs )         mount_data geoip ;;
	esac
}

enable_bsd_cache()
{
	# see if jails are running
	jls | grep -q bsd_cache || return;
	jls | grep -q dns || return;

	# assure services are available
	sockstat -4 -6 -p 80 -q -j bsd_cache | grep -q . || return
	sockstat -4 -6 -p 53 -q -j dns | grep -q . || return

	tell_status "enabling bsd_cache"

	store_config "$STAGE_MNT/etc/resolv.conf" "overwrite" <<EO_RESOLV
nameserver $(get_jail_ip dns)
nameserver $(get_jail_ip6 dns)
EO_RESOLV

	local _repo_dir="$ZFS_JAIL_MNT/stage/usr/local/etc/pkg/repos"
	if [ ! -d "$_repo_dir" ]; then mkdir -p "$_repo_dir"; fi

	store_config "$_repo_dir/FreeBSD.conf" <<EO_PKG_CONF
FreeBSD: {
	enabled: no
}
EO_PKG_CONF

	store_config "$_repo_dir/MT6.conf" <<EO_PKG_MT6
MT6: {
	url: "http://pkg/\${ABI}/$TOASTER_PKG_BRANCH",
	enabled: yes
}
EO_PKG_MT6

	# cache pkg audit vulnerability db
	sed -i '' \
		-e '/^#VULNXML_SITE/ s/^#//' \
		-e '/^VULNXML_SITE/ s/vuxml.freebsd.org/vulnxml/' \
		"$ZFS_JAIL_MNT/stage/usr/local/etc/pkg.conf"

	sed -i '' -e '/^ServerName/ s/update.FreeBSD.org/freebsd-update/' \
		"$ZFS_JAIL_MNT/stage/etc/freebsd-update.conf"
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
		ip6.addr="$(get_jail_ip6 stage)" \
		exec.start="/bin/sh /etc/rc" \
		exec.stop="/bin/sh /etc/rc.shutdown" \
		mount.devfs \
		devfs_ruleset=5 \
		$JAIL_START_EXTRA \
		|| exit

	stage_mount_aux_data "$_name"
	enable_bsd_cache

	tell_status "updating pkg database"
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
		if [ "$_tries" -gt 10 ]; then
			echo "trying to force rename"
			_zfs_rename="zfs rename -f $ZFS_JAIL_VOL/stage $_new_vol"
		fi
		echo "waiting for ZFS filesystem to quiet ($_tries)"
		_tries=$((_tries + 1))
		sleep 3
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
		sleep 4
	done
}

rename_ready_to_active()
{
	echo "zfs rename $ZFS_JAIL_VOL/${1}.ready $ZFS_JAIL_VOL/$1"
	zfs rename "$ZFS_JAIL_VOL/${1}.ready" "$ZFS_JAIL_VOL/$1" || exit
}

tell_settings()
{
	echo; echo "   ***   Configured $1 settings:"
	set | grep "^$1_"
	echo
	sleep 2
}

proclaim_success()
{
	echo; echo "Success! A new '$1' jail is provisioned"; echo
}

stage_clear_caches()
{
	echo "clearing pkg cache"
	rm -rf "$STAGE_MNT/var/cache/pkg/*"

	echo "clearing freebsd-update cache"
	rm -rf "$STAGE_MNT/var/db/freebsd-update/*"
}

stage_resolv_conf()
{
	tell_status "configuring DNS for local recursor"
	echo "nameserver $(get_jail_ip dns)" > "$STAGE_MNT/etc/resolv.conf"
	echo "nameserver $(get_jail_ip6 dns)" >> "$STAGE_MNT/etc/resolv.conf"
}

seed_pkg_audit()
{
	if [ "$TOASTER_PKG_AUDIT" = "1" ]; then
		tell_status "installing FreeBSD package audit database"
		stage_exec /usr/sbin/pkg audit -F
	fi
}

enable_jail()
{
	case " $(sysrc -n jail_list) " in *" $1 "*)
		#echo "jail $1 already enabled at startup"
		return ;;
	esac

	tell_status "enabling jail $1 at startup"
	sysrc jail_list+=" $1"
	sysrc -f /etc/periodic.conf security_status_pkgaudit_jails+=" $1"
}

promote_staged_jail()
{
	seed_pkg_audit
	tell_status "promoting jail $1"
	stop_jail stage
	stage_resolv_conf
	stage_unmount "$1"
	ipcrm -W
	stage_clear_caches

	rename_staged_to_ready "$1"

	stop_jail "$1"
	unmount_data "$1" "$ZFS_JAIL_MNT/$1"
	unmount_ports "$ZFS_JAIL_MNT/$1"

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
	# $1 is the port directory (ex: mail/dovecot)
	echo "jexec $SAFE_NAME make -C /usr/ports/$1 build deinstall install clean"
	jexec "$SAFE_NAME" make -C "/usr/ports/$1" build deinstall install clean || return 1

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
	echo "checking for port $1 listener in staged jail"
	if [ -z "$2" ]; then
		sockstat -l -4 -6 -p "$1" -j "$(jls -j stage jid)" | grep -v PROTO || exit
		return
	fi

	local _tries=0
	local _listening=""
	local _sleep="$3"
	if [ -z "$_sleep" ]; then _sleep=1; fi

	until [ -n "$_listening" ]; do
		_tries=$((_tries + 1))

		if [ "$_tries" -gt "$2" ]; then
			echo "port $1 is NOT listening"
			exit
		fi
		echo "	checking port $1"
		_listening=$(sockstat -l -4 -6 -p "$1" -j "$(jls -j stage jid)" | grep -v PROTO)
		sleep "$_sleep"
	done

	echo
	echo "Success! Port $1 is listening in staging jail"
}

stage_test_running()
{
	echo "checking for process $1 in staged jail"
	pgrep -j stage "$1" || exit
	echo "ok"
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

	tell_status "downloading $(freebsd_release_url_base)/$1.txz"
	fetch -m "$(freebsd_release_url_base)/$1.txz" || exit
	echo "done"

	tell_status "extracting FreeBSD package $1.tgz to $_dest"
	tar -C "$_dest" -xpJf "$1.txz" || exit
	echo "done"
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
		mkdir -p "$_data_mp" || exit 1
	fi

	if mount -t nullfs | grep -q "$_data_mp"; then
		echo "$_data_mp already mounted!"
		exit 1
	fi

	echo "mount_nullfs $_data_mnt $_data_mp"
	mount_nullfs "$_data_mnt" "$_data_mp" || exit 1
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

	case "$1" in
		avg )       echo "$_base_dir/data/avg"; return ;;
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

	if [ "$1" = "ipv6" ]; then
		if [ -n "$PUBLIC_IP6" ]; then return; fi
		export PUBLIC_IP6
		PUBLIC_IP6=$(ifconfig "$PUBLIC_NIC" inet6 | grep inet | grep -v fe80 | awk '{print $2}' | head -n1)
	else
		if [ -n "$PUBLIC_IP4" ]; then return; fi
		export PUBLIC_IP4
		PUBLIC_IP4=$(ifconfig "$PUBLIC_NIC" inet | grep inet | awk '{print $2}' | head -n1)
	fi
}

fetch_and_exec()
{
	if [ ! -d provision ]; then mkdir provision; fi

	if [ -d ".git" ]; then
		tell_status "running from git, skipping fetch"
	else
		fetch -o provision -m "$TOASTER_SRC_URL/provision/$1.sh"
	fi

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
	for _j in host base dns bsd_cache mysql redis clamav dcc geoip vpopmail rspamd spamassassin dovecot haraka haproxy webmail roundcube snappymail mailtest; do
		fetch_and_exec "$_j" || break
	done
}

provision()
{
	case "$1" in
		host)   fetch_and_exec "$1"; return;;
		mt6)    provision_mt6; return;;
	esac

	if ! get_jail_ip "$1"; then
		echo "unknown jail $1"
		return
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

mt6-include()
{
	if [ ! -d include ]; then
		mkdir include || exit
	fi

	if [ -d ".git" ]; then
		tell_status "skipping include d/l, running from git"
	else
		fetch -m -o "include/$1.sh" "$TOASTER_SRC_URL/include/$1.sh"

		if [ ! -f "include/$1.sh" ]; then
			echo "unable to download include/$1.sh"
			exit
		fi
	fi

	# shellcheck source=include/$.sh disable=SC1091
	. "include/$1.sh"
}

jail_rename()
{
	if [ -z "$1" ] || [ -z "$2" ]; then
		echo "$0 <existing jail name> <new jail name>"
		exit
	fi

	echo "renaming $1 to $2"
	service jail stop "$1"  || exit

	for _f in data jails
	do
		zfs unmount "$ZFS_VOL/$_f/$1"
		zfs rename "$ZFS_VOL/$_f/$1" "$ZFS_VOL/$_f/$2"  || exit
		zfs set mountpoint="/$_f/$2" "$ZFS_VOL/$_f/$2"  || exit
		zfs mount "$ZFS_VOL/$_f/$2"
	done

	sed -i.bak \
		-e "/^$1\s/ s/$1/$2/" \
		/etc/jail.conf || exit

	service jail start "$2"

	echo "Don't forget to update your PF and/or Haproxy rules"
}

configure_pkg_latest()
{
	local _pkg_host="pkg.FreeBSD.org"

	if [ -d "$ZFS_DATA_MNT/bsd_cache/pkg" ]; then
		tell_status "switching pkg to bsd_cache"
		_pkg_host="pkg"
	fi

	local REPODIR="$1/usr/local/etc/pkg/repos"
	if [ -f "$REPODIR/FreeBSD.conf" ]; then return; fi

	tell_status "switching pkg from quarterly to latest"
	mkdir -p "$REPODIR"
	store_config "$REPODIR/FreeBSD.conf" "overwrite" <<EO_PKG
FreeBSD: {
  url: "pkg+http://$_pkg_host/\${ABI}/$TOASTER_PKG_BRANCH"
}
EO_PKG
}

assure_ip6_addr_is_declared()
{
	if ! grep -qs "^$1" /etc/jail.conf; then
		# config for this jail hasn't been created yet
		return
	fi

	if awk "/^$1/,/}/" /etc/jail.conf | grep -q ip6; then
		echo "ip6.addr is already declared"
		return
	fi

	tell_status "adding ip6.addr to $1 section in /etc/jail.conf"
	sed -i.bak \
		-e "/^$1/,/ip4/ s/ip4.*;/&\\
		ip6.addr = $JAIL_NET_INTERFACE|$(get_jail_ip6 "$1");/" \
		/etc/jail.conf || exit
}

assure_jail()
{
	local _jid; _jid=$(jls -j "$1" jid)
	if [ -z "$_jid" ]; then
		echo "jail $1 is required but not available"
		exit
	fi
}

preserve_file() {
	# $1 is the jail name
	# $2 is a path to a file within a jail
	local _active_cfg="$ZFS_JAIL_MNT/$1/$2"
	local _stage_cfg="${STAGE_MNT}/$2"
	if [ -f "$_active_cfg" ]; then
		tell_status "preserving $_active_cfg"
		cp "$_active_cfg" "$_stage_cfg" || return 1
		return
	fi

	if [ -d "$ZFS_JAIL_MNT/$1.last" ]; then
		_active_cfg="$ZFS_JAIL_MNT/$1.last/$2"
		if [ -f "$_active_cfg" ]; then
			tell_status "preserving $_active_cfg"
			cp "$_active_cfg" "$_stage_cfg" || return 1
			return
		fi
	fi
}
