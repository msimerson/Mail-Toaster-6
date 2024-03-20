#!/bin/sh

# bump version when a change in this file effects provision scripts
mt6_version() { echo "20240319"; }

dec_to_hex() { printf '%04x\n' "$1"; }

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
export TOASTER_EDITOR="vim-tiny"
export TOASTER_MSA="haraka"
export TOASTER_MYSQL="1"
export TOASTER_MYSQL_PASS=""
export TOASTER_NRPE=""
export TOASTER_PKG_AUDIT="0"
export TOASTER_PKG_BRANCH="latest"
export TOASTER_USE_TMPFS="0"
export TOASTER_VPOPMAIL_CLEAR="1"
export TOASTER_VPOPMAIL_EXT="0"
export CLAMAV_FANGFRISCH="0"
export MAXMIND_LICENSE_KEY=""
export ROUNDCUBE_SQL="0"
export ROUNDCUBE_DEFAULT_HOST=""
export ROUNDCUBE_PRODUCT_NAME="Roundcube Webmail"
export ROUNDCUBE_ATTACHMENT_SIZE_MB="25"

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
export TOASTER_HOSTNAME=${TOASTER_HOSTNAME:="mail.example.com"} || exit 1
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

export TOASTER_BASE_MTA=${TOASTER_BASE_MTA:=""}
export TOASTER_BASE_PKGS=${TOASTER_BASE_PKGS:="pkg ca_root_nss"}
export TOASTER_EDITOR=${TOASTER_EDITOR:="vi"}
# See https://github.com/msimerson/Mail-Toaster-6/wiki/MySQL
export TOASTER_MYSQL=${TOASTER_MYSQL:="1"}
export TOASTER_MARIADB=${TOASTER_MARIADB:="0"}
export TOASTER_NTP=${TOASTER_NTP:="ntp"}
export TOASTER_MSA=${TOASTER_MSA:="haraka"}
export TOASTER_PKG_AUDIT=${TOASTER_PKG_AUDIT:="0"}
export TOASTER_PKG_BRANCH=${TOASTER_PKG_BRANCH:="latest"}
export TOASTER_USE_TMPFS=${TOASTER_USE_TMPFS:="0"}
export TOASTER_VPOPMAIL_CLEAR=${TOASTER_VPOPMAIL_CLEAR:="1"}
export TOASTER_VPOPMAIL_EXT=${TOASTER_VPOPMAIL_EXT:="0"}
export TOASTER_VQADMIN=${TOASTER_VQADMIN:="0"}
export CLAMAV_FANGFRISCH=${CLAMAV_FANGFRISCH:="0"}
export CLAMAV_UNOFFICIAL=${CLAMAV_UNOFFICIAL:="0"}
export ROUNDCUBE_SQL=${ROUNDCUBE_SQL:="$TOASTER_MYSQL"}
export ROUNDCUBE_PRODUCT_NAME=${ROUNDCUBE_PRODUCT_NAME:="Roundcube Webmail"}
export ROUNDCUBE_ATTACHMENT_SIZE_MB=${ROUNDCUBE_ATTACHMENT_SIZE_MB:="25"}
export SQUIRREL_SQL=${SQUIRREL_SQL:="$TOASTER_MYSQL"}

# shellcheck disable=2009,2317
if ps -o args= -p "$$" | grep csh; then
	echo; echo "ERROR: switch to sh or bash"; return 1; exit 1;
fi
echo "shell: $SHELL"

if [ "$TOASTER_MYSQL" = "1" ]; then
	echo "mysql enabled"
fi

usage()
{
	if [ -n "$1" ]; then echo; echo "ERROR: invalid $1"; echo; fi
	echo; echo "Next step, edit mail-toaster.conf!"; echo
	echo "See: https://github.com/msimerson/Mail-Toaster-6/wiki/FreeBSD"; echo
}
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
echo "IPv6 jail network: $JAIL_NET6"

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

fatal_err() { echo; echo "FATAL: $1"; echo; exit 1; }

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
	if zfs list -t snapshot "$1" 2>/dev/null | grep -q "$1"; then
		echo "$1 snapshot exists"
		return
	fi
	false
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

	tell_status "adding $1 to /etc/jail.conf"
	echo "$1	{$(get_safe_jail_path $1)
		mount.fstab = \"$ZFS_DATA_MNT/$1/etc/fstab\";
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

add_jail_conf_d()
{
	_safe_path="/etc/jail.conf.d/$(safe_jailname $1).conf"
	if [ -f "/etc/jail.conf.d/$1.conf" ]; then
		tell_status "preserving jail config $_safe_path"
		return
	fi

	tell_status "creating $_safe_path"
	tee "$_safe_path" <<EO_JAIL_RC
$(jail_conf_header)

$(safe_jailname $1)	{$(get_safe_jail_path $1)
		mount.fstab = "$ZFS_DATA_MNT/$1/etc/fstab";
		ip4.addr = $JAIL_NET_INTERFACE|${_jail_ip};
		ip6.addr = $JAIL_NET_INTERFACE|$(get_jail_ip6 $1);${JAIL_CONF_EXTRA}
		exec.created = "$ZFS_DATA_MNT/$1/etc/pf.conf.d/pfrule.sh load";
		exec.poststop = "$ZFS_DATA_MNT/$1/etc/pf.conf.d/pfrule.sh unload";
	}
EO_JAIL_RC
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
	if jail_is_running "$_safe"; then
		echo "service jail stop $_safe"
		if ! service jail stop "$_safe"; then
			echo "jail -r $_safe"
			if jail -r "$_safe" 2>/dev/null; then echo "removed"; fi
		fi
	fi

	if jail_is_running "$_safe"; then
		echo "jail -r $_safe"
		if jail -r "$_safe" 2>/dev/null; then echo "removed"; fi
	fi
}

stage_unmount()
{
	for _fs in $(mount | grep stage | sort -u | awk '{ print $3 }'); do
		if [ "$(basename "$_fs")" = "stage" ]; then continue; fi
		umount "$_fs"
	done

	# repeat, as sometimes a nested fs will prevent first try from success
	for _fs in $(mount | grep stage | sort -u | awk '{ print $3 }'); do
		if [ "$(basename "$_fs")" = "stage" ]; then continue; fi
		umount "$_fs"
	done

	if mount -t devfs | grep -q "$STAGE_MNT/dev"; then
		echo "umount $STAGE_MNT/dev"
		umount "$STAGE_MNT/dev" || exit 1
	fi
}

cleanup_staged_fs()
{
	tell_status "stage cleanup"
	stop_jail stage
	stage_unmount "$1"
	zfs_destroy_fs "$ZFS_JAIL_VOL/stage" -f
}

install_pfrule()
{
	tell_status "setting up etc/pf.conf.d"

	store_exec "$_dir/pfrule.sh" <<'EO_PF_RULE'
#!/bin/sh

# pfrule.sh
#
# Matt Simerson, matt@tnpi.net, 2023-06
#
# Use pfctl to load and unload PF rules into named anchors from config
# files. See https://github.com/msimerson/Mail-Toaster-6/wiki/PF

_etcpath="$(dirname -- "$( readlink -f -- "$0"; )";)"

usage() {
    echo "   usage: $0 [ load | unload ]"
    echo " "
    exit 1
}

for _f in "$_etcpath"/*.conf; do
    [ -f "$_f" ] || continue

    _anchor=$(basename $_f .conf)  # nat, rdr, allow
    _jailname=$(basename "$(dirname "$(dirname $_etcpath)")")
    _pfctl="pfctl -a $_anchor/$_jailname"

    case "$1" in
        "load"   ) _cmd="$_pfctl -f $_f" ;;
        "unload" ) _cmd="$_pfctl -F all" ;;
        *        ) usage                 ;;
    esac

    echo "$_cmd"
    $_cmd || exit 1
done

exit
EO_PF_RULE
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

	zfs_create_fs "$ZFS_DATA_VOL/$1" "$ZFS_DATA_MNT/$1"
	install_fstab $1
	install_pfrule $1
	echo
}

enable_bsd_cache()
{
	if ! jail_is_running bsd_cache; then return; fi
	if ! jail_is_running dns; then return; fi

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
	local _name=${1:-"$SAFE_NAME"}
	local _path=${2:-"$STAGE_MNT"}
	local _fstab="$ZFS_DATA_MNT/$_name/etc/fstab.stage"

	if [ "$_name" = "base" ]; then _fstab="$BASE_MNT/data/etc/fstab"; fi

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
		if [ "$_tries" -gt 5 ]; then
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
	echo; echo "   ***   Configured $1 settings:   ***"; echo
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
	if ! jail_is_running dns; then return; fi

	tell_status "configuring DNS for local recursor"
	echo "nameserver $(get_jail_ip  dns)" >  "$STAGE_MNT/etc/resolv.conf"
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
	stage_unmount "$1"
	ipcrm -W
	stage_clear_caches

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

	jexec "$SAFE_NAME" pkg install -y pkgconf portconfig
	# portconfig replaces dialog4ports (as of Oct 2023)

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

port_is_listening()
{
	local _port=${1:-"25"}
	local _jail=${2:-"stage"}

	if [ -n "$(sockstat -l -q -4 -6 -p "$_port" -j "$_jail")" ]; then
		true
	else
		false
	fi
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
	for _j in host base dns mysql redis clamav dcc geoip vpopmail rspamd spamassassin dovecot haraka haproxy webmail roundcube snappymail mailtest; do
		fetch_and_exec "$_j" || break
	done
}

provision()
{
	for _var in JAIL_START_EXTRA JAIL_CONF_EXTRA JAIL_FSTAB; do
		unset "$_var"
	done

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
		local _rev_list="${_j} ${_rev_list}"
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

jail_is_running()
{
	jls -d -j $1 name 2>/dev/null | grep -q $1
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
		/etc/jail.conf
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
	local _jail_name=$1
	local _file_path=$2

	local _active_cfg="$ZFS_JAIL_MNT/$_jail_name/$_file_path"
	local _stage_cfg="${STAGE_MNT}/$_file_path"

	if [ -f "$_active_cfg" ]; then
		tell_status "preserving $_active_cfg"
		cp "$_active_cfg" "$_stage_cfg" || return 1
		return
	fi

	if [ -d "$ZFS_JAIL_MNT/$_jail_name.last" ]; then
		_active_cfg="$ZFS_JAIL_MNT/$_jail_name.last/$_file_path"
		if [ -f "$_active_cfg" ]; then
			tell_status "preserving $_active_cfg"
			cp "$_active_cfg" "$_stage_cfg" || return 1
			return
		fi
	fi
}

get_random_pass()
{
	local _pass_len=${1:-"14"}

	# Password Entropy = log2(charset_len ^pass_len)

	if [ -z "$2" ]; then
		# default, good, limited by base64 charset
		openssl rand -base64 "$(echo "$_pass_len + 4" | bc)" | head -c "$_pass_len"
	else
		# https://unix.stackexchange.com/questions/230673/how-to-generate-a-random-string
		# more entropy with 94 ASCII chars but special chars are often problematic
		LC_ALL=C tr -dc '[:graph:]' </dev/urandom | head -c "$_pass_len"
	fi

	echo
}

store_exec()
{
	# $1 - path to file, STDIN is file contents
	if [ ! -d "$(dirname $1)" ]; then
		tell_status "creating $(dirname $1)"
		mkdir -p "$(dirname $1)" || exit 1
	fi

	cat - > "$1" || exit 1
	chmod 755 "$1"
}

onexit() { while caller $((n++)); do :; done; }

if [ "$TOASTER_BUILD_DEBUG" = "1" ]; then
	trap onexit EXIT
fi
