#!/bin/sh

# pkgbase hosts ship the base as packages; FreeBSD-bootloader is one of them
default_base_method()
{
	if [ "$(uname)" = 'FreeBSD' ] && pkg info -e FreeBSD-bootloader 2>/dev/null; then
		echo "pkgbase"
	else
		echo "fetch"
	fi
}

mt6_defaults()
{
	# export these in your environment to customize
	export BOURNE_SHELL=${BOURNE_SHELL:-"all"}
	export JAIL_NET_PREFIX=${JAIL_NET_PREFIX:-"172.16.15"}
	export JAIL_NET_MASK=${JAIL_NET_MASK:-"/19"}
	export JAIL_NET_INTERFACE=${JAIL_NET_INTERFACE:-"lo1"}
	export JAIL_ORDERED_LIST="syslog base dns mysql clamav spamassassin foundationdb vpopmail haraka webmail munin haproxy rspamd stalwart dovecot redis geoip nginx mailtest apache postgres minecraft joomla php7 memcached sphinxsearch elasticsearch nictool sqwebmail dhcp letsencrypt tinydns roundcube squirrelmail rainloop rsnapshot mediawiki smf wordpress whmcs squirrelcart horde grafana unifi mongodb gitlab gitlab_runner dcc prometheus influxdb telegraf statsd mail_dmarc ghost jekyll borg nagios postfix puppeteer snappymail knot nsd bsd_cache wildduck zonemta centos ubuntu bhyve-ubuntu mailman git"

	export ZFS_VOL=${ZFS_VOL:-"zroot"}
	export ZFS_BHYVE_VOL="${ZFS_BHYVE_VOL:-$ZFS_VOL}"
	export ZFS_JAIL_MNT=${ZFS_JAIL_MNT:-"/jails"}
	export ZFS_DATA_MNT=${ZFS_DATA_MNT:-"/data"}
	export FBSD_MIRROR=${FBSD_MIRROR:-"ftp://ftp.freebsd.org"}

	export TLS_LIBRARY=${TLS_LIBRARY:-""}
	export TOASTER_BASE_MTA=${TOASTER_BASE_MTA:-""}
	export TOASTER_BASE_PKGS=${TOASTER_BASE_PKGS:-"pkg ca_root_nss"}
	export TOASTER_BUILD_DEBUG=${TOASTER_BUILD_DEBUG:-"0"}
	export TOASTER_EDITOR=${TOASTER_EDITOR:-"vim"}
	export TOASTER_EDITOR_PORT=${TOASTER_EDITOR_PORT:-"vim-tiny"}
	# See https://github.com/msimerson/Mail-Toaster-6/wiki/MySQL
	export TOASTER_MYSQL=${TOASTER_MYSQL:-"1"}
	export TOASTER_MARIADB=${TOASTER_MARIADB:-"0"}
	export TOASTER_NGINX_ACME=${TOASTER_NGINX_ACME:-"0"}
	export TOASTER_NTP=${TOASTER_NTP:-"chrony"}
	export TOASTER_MSA=${TOASTER_MSA:-"haraka"}
	export TOASTER_MTA=${TOASTER_MTA:-"haraka"}
	export TOASTER_PKG_AUDIT=${TOASTER_PKG_AUDIT:-"0"}
	export TOASTER_PKG_BRANCH=${TOASTER_PKG_BRANCH:-"latest"}
	export TOASTER_USE_TMPFS=${TOASTER_USE_TMPFS:-"0"}
	export TOASTER_VPOPMAIL_CLEAR=${TOASTER_VPOPMAIL_CLEAR:-"1"}
	export TOASTER_VPOPMAIL_EXT=${TOASTER_VPOPMAIL_EXT:-"0"}
	export TOASTER_VQADMIN=${TOASTER_VQADMIN:-"0"}
	export TOASTER_QMHANDLE=${TOASTER_QMHANDLE:-"0"}
	export TOASTER_WEBMAIL_PROXY=${TOASTER_WEBMAIL_PROXY:-"haproxy"}
	# Jail-private settings live in their provision script; these are read by
	# more than one jail, so they stay here.
	export ROUNDCUBE_SQL=${ROUNDCUBE_SQL:-"$TOASTER_MYSQL"}
	export SQUIRREL_SQL=${SQUIRREL_SQL:-"$TOASTER_MYSQL"}

	# If your hosts public facing IP(s) are not bound to a local interface, configure it here.
	export PUBLIC_IP4=${PUBLIC_IP4:-""}
	export PUBLIC_IP6=${PUBLIC_IP6:-""}

	# little below here should need customizing. If so, consider opening
	# an issue or PR at https://github.com/msimerson/Mail-Toaster-6
	export ZFS_JAIL_VOL="${ZFS_VOL}${ZFS_JAIL_MNT}"
	export ZFS_DATA_VOL="${ZFS_VOL}${ZFS_DATA_MNT}"

	# how the base jail is built: fetch (base.txz) | bsdinstall | pkgbase
	export TOASTER_BASE_METHOD=${TOASTER_BASE_METHOD:-"$(default_base_method)"}
	export TOASTER_BASE_PKG_BRANCH=${TOASTER_BASE_PKG_BRANCH:-""}

	export FBSD_REL_VER FBSD_PATCH_VER
	if [ "$(uname)" = 'FreeBSD' ]; then
		FBSD_REL_VER=$(/bin/freebsd-version | /usr/bin/cut -f1-2 -d'-')
		FBSD_PATCH_VER=$(/bin/freebsd-version | /usr/bin/cut -f3 -d'-')
		FBSD_PATCH_VER=${FBSD_PATCH_VER:-"p0"}
	fi

	# the 'base' jail that other jails are cloned from. This will be named as the
	# host OS version, eg: base-13.2-RELEASE and the snapshot name will be the OS
	# patch level, eg: base-13.2-RELEASE@p3
	export BASE_NAME="base-$FBSD_REL_VER"
	export BASE_VOL="$ZFS_JAIL_VOL/$BASE_NAME"
	export BASE_SNAP="${BASE_VOL}@${FBSD_PATCH_VER}"
	export BASE_MNT="$ZFS_JAIL_MNT/$BASE_NAME"

	export STAGE_MNT="$ZFS_JAIL_MNT/stage"
}

create_default_config()
{
	local _HOSTNAME
	local _EMAIL_DOMAIN
	local _ORGNAME

	if [ -t 0 ] && [ "$(uname)" = 'FreeBSD' ]; then
		echo "editing prefs"
		_HOSTNAME=$(bsddialog --nocancel --backtitle "mail-toaster.sh" --title TOASTER_HOSTNAME --inputbox "the hostname of this [virtual] machine" 8 70 "mail.example.com" 3>&1 1>&2 2>&3)
		_EMAIL_DOMAIN=$(bsddialog --nocancel --backtitle "mail-toaster.sh" --title TOASTER_MAIL_DOMAIN --inputbox "the primary email domain" 8 70 "example.com" 3>&1 1>&2 2>&3)
		_ORGNAME=$(bsddialog --nocancel --backtitle "mail-toaster.sh" --title TOASTER_ORG_NAME --inputbox "the name of your organization" 8 70 "Email Inc" 3>&1 1>&2 2>&3)
	fi

	# for dev/test environs where bsddialog doesn't exist
	if [ -z "$_HOSTNAME"     ]; then _HOSTNAME=$(hostname); fi
	if [ -z "$_EMAIL_DOMAIN" ]; then _EMAIL_DOMAIN=$(hostname); fi
	if [ -z "$_ORGNAME"      ]; then _ORGNAME="Sparky the Toaster"; fi

	echo "creating $1 with defaults"
	store_config "$1" <<EO_MT_CONF
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
export JAIL_NET_MASK="/19"
export JAIL_NET_INTERFACE="lo1"
export JAIL_NET6="$(get_random_ip6net)"
export ZFS_VOL="zroot"
export ZFS_JAIL_MNT="/jails"
export ZFS_DATA_MNT="/data"
export TOASTER_EDITOR="vim"
export TOASTER_EDITOR_PORT="vim-tiny"
export TOASTER_MSA="haraka"
export TOASTER_MTA="haraka"
export TOASTER_MYSQL="1"
export TOASTER_MYSQL_PASS=""
export TOASTER_NGINX_ACME="0"
export TOASTER_NRPE=""
export TOASTER_NTP=""
export TOASTER_BASE_METHOD="$(default_base_method)"  # fetch | bsdinstall | pkgbase
export TOASTER_BASE_MTA=""
export TOASTER_BASE_PKG_BRANCH=""   # pkgbase: base_release_N (default), base_latest, base_weekly
export TOASTER_PKG_AUDIT="0"
export TOASTER_PKG_BRANCH="latest"
export TOASTER_USE_TMPFS="0"
export TOASTER_VPOPMAIL_CLEAR="1"
export TOASTER_VPOPMAIL_EXT="0"
export TOASTER_WEBMAIL_PROXY="haproxy"
export ROUNDCUBE_SQL="0"
export TOASTER_HARAKA_VERSION=""
export UNIFI_MONGODB_DSN="mongodb://ubnt:$(get_random_pass)@mongodb:27017/unifi"

EO_MT_CONF

	chmod 600 "$1"
}

_add_config_hint()
{
	if grep -q "grep.*config.sh" "$1"; then
		return
	fi
	printf '\n# To see all available settings and their defaults:\n# grep -rn "export [A-Z_]*=..[A-Z_]*:-" ./include/config.sh ./provision/\n' \
		>> "$1"
}

_fix_jail_ordered_list()
{
	if ! grep -q "^export JAIL_ORDERED_LIST=" "$1"; then
		return
	fi
	local _current
	_current=$(grep "^export JAIL_ORDERED_LIST=" "$1" \
		| sed 's/^export JAIL_ORDERED_LIST="\(.*\)"$/\1/')
	case "$_current" in
		"syslog base "*) return ;;
	esac
	echo "fixing JAIL_ORDERED_LIST prefix in $1"
	local _rest
	_rest=$(printf '%s' "$_current" | tr ' ' '\n' \
		| grep -v -E '^(syslog|base)$' | tr '\n' ' ' | sed 's/ $//')
	sed -i.bak "s|^export JAIL_ORDERED_LIST=.*|export JAIL_ORDERED_LIST=\"syslog base ${_rest}\"|" "$1"
	rm -f "$1.bak"
}

_migrate_config_to_conf_d()
{
	mkdir -p "$(dirname "$1")"
	echo "moving mail-toaster.conf to $1"
	mv mail-toaster.conf "$1"
}

# BSD and GNU stat disagree on both the flag and the format specifier. Toasters
# run on FreeBSD; the test suite runs on Linux.
_file_mode()
{
	case "$(uname)" in
		Linux*) stat -c "%a" "$1" ;;
		*)      stat -f "%OLp" "$1" ;;
	esac
}

_tighten_config_perms()
{
	# An unreadable mode compares unequal, so the chmod still runs. Absorb the
	# failure too, or the assignment would abort a provision script's set -e.
	local _mode; _mode=$(_file_mode "$1" 2>/dev/null) || _mode=""
	if [ "$_mode" != "600" ]; then
		echo "tightening permissions on $1"
		chmod 600 "$1"
	fi
}

# Per-jail overrides, sourced by provision scripts after mt6_defaults has run.
# A setting present in the file wins; anything absent keeps the ${VAR:-default}
# value from mt6_defaults, so new upstream settings still reach existing installs.
service_config()
{
	if [ -z "${1:-}" ]; then
		echo "service_config: a service name is required" >&2
		return 1
	fi

	local _conf="$MT6_CONF_DIR/$1.conf"
	if [ ! -f "$_conf" ]; then
		return 0
	fi

	_tighten_config_perms "$_conf"
	echo "loading $_conf"
	# shellcheck disable=SC1090
	. "$_conf"
}

config()
{
	export MT6_CONF_DIR="conf.d"
	export MT6_CONF="$MT6_CONF_DIR/mail-toaster.conf"

	if [ ! -f "$MT6_CONF" ]; then
		if [ -f "mail-toaster.conf" ]; then
			_migrate_config_to_conf_d "$MT6_CONF"
		else
			create_default_config "$MT6_CONF"
		fi
	fi

	_tighten_config_perms "$MT6_CONF"
	_add_config_hint "$MT6_CONF"
	_fix_jail_ordered_list "$MT6_CONF"

	echo "loading $MT6_CONF"
	# shellcheck disable=SC1090,SC1091,SC2039
	. "$MT6_CONF"
}
