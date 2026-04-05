#!/bin/sh

mt6_defaults()
{
	# export these in your environment to customize
	export BOURNE_SHELL=${BOURNE_SHELL:="bash"}
	export JAIL_NET_PREFIX=${JAIL_NET_PREFIX:="172.16.15"}
	export JAIL_NET_MASK=${JAIL_NET_MASK:="/19"}
	export JAIL_NET_INTERFACE=${JAIL_NET_INTERFACE:="lo1"}
	export JAIL_ORDERED_LIST="syslog base dns mysql clamav spamassassin foundationdb vpopmail haraka webmail munin haproxy rspamd stalwart dovecot redis geoip nginx mailtest apache postgres minecraft joomla php7 memcached sphinxsearch elasticsearch nictool sqwebmail dhcp letsencrypt tinydns roundcube squirrelmail rainloop rsnapshot mediawiki smf wordpress whmcs squirrelcart horde grafana unifi mongodb gitlab gitlab_runner dcc prometheus influxdb telegraf statsd mail_dmarc ghost jekyll borg nagios postfix puppeteer snappymail knot nsd bsd_cache wildduck zonemta centos ubuntu bhyve-ubuntu mailman"

	export ZFS_VOL=${ZFS_VOL:="zroot"}
	export ZFS_BHYVE_VOL="${ZFS_BHYVE_VOL:=$ZFS_VOL}"
	export ZFS_JAIL_MNT=${ZFS_JAIL_MNT:="/jails"}
	export ZFS_DATA_MNT=${ZFS_DATA_MNT:="/data"}
	export FBSD_MIRROR=${FBSD_MIRROR:="ftp://ftp.freebsd.org"}

	export TLS_LIBRARY=${TLS_LIBRARY:=""}
	export TOASTER_BASE_MTA=${TOASTER_BASE_MTA:=""}
	export TOASTER_BASE_PKGS=${TOASTER_BASE_PKGS:="pkg ca_root_nss"}
	export TOASTER_BUILD_DEBUG=${TOASTER_BUILD_DEBUG:="0"}
	export TOASTER_EDITOR=${TOASTER_EDITOR:="vim"}
	export TOASTER_EDITOR_PORT=${TOASTER_EDITOR_PORT:="vim-tiny"}
	# See https://github.com/msimerson/Mail-Toaster-6/wiki/MySQL
	export TOASTER_MYSQL=${TOASTER_MYSQL:="1"}
	export TOASTER_MARIADB=${TOASTER_MARIADB:="0"}
	export TOASTER_NTP=${TOASTER_NTP:="chrony"}
	export TOASTER_MSA=${TOASTER_MSA:="haraka"}
	export TOASTER_PKG_AUDIT=${TOASTER_PKG_AUDIT:="0"}
	export TOASTER_PKG_BRANCH=${TOASTER_PKG_BRANCH:="latest"}
	export TOASTER_USE_TMPFS=${TOASTER_USE_TMPFS:="0"}
	export TOASTER_VPOPMAIL_CLEAR=${TOASTER_VPOPMAIL_CLEAR:="1"}
	export TOASTER_VPOPMAIL_EXT=${TOASTER_VPOPMAIL_EXT:="0"}
	export TOASTER_VQADMIN=${TOASTER_VQADMIN:="0"}
	export TOASTER_QMHANDLE=${TOASTER_QMHANDLE:="0"}
	export TOASTER_WEBMAIL_PROXY=${TOASTER_WEBMAIL_PROXY:="haproxy"}
	export CLAMAV_FANGFRISCH=${CLAMAV_FANGFRISCH:="0"}
	export CLAMAV_UNOFFICIAL=${CLAMAV_UNOFFICIAL:="0"}
	export ROUNDCUBE_SQL=${ROUNDCUBE_SQL:="$TOASTER_MYSQL"}
	export ROUNDCUBE_PRODUCT_NAME=${ROUNDCUBE_PRODUCT_NAME:="Roundcube Webmail"}
	export ROUNDCUBE_ATTACHMENT_SIZE_MB=${ROUNDCUBE_ATTACHMENT_SIZE_MB:="25"}
	export SQUIRREL_SQL=${SQUIRREL_SQL:="$TOASTER_MYSQL"}
	export WILDDUCK_MAIL_DOMAIN=${WILDDUCK_MAIL_DOMAIN:="$TOASTER_MAIL_DOMAIN"}
	export WILDDUCK_HOSTNAME=${WILDDUCK_HOSTNAME:="$TOASTER_HOSTNAME"}

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
export JAIL_NET_MASK="/19"
export JAIL_NET_INTERFACE="lo1"
export JAIL_NET6="$(get_random_ip6net)"
export ZFS_VOL="zroot"
export ZFS_JAIL_MNT="/jails"
export ZFS_DATA_MNT="/data"
export TOASTER_EDITOR="vim"
export TOASTER_EDITOR_PORT="vim-tiny"
export TOASTER_MSA="haraka"
export TOASTER_MYSQL="1"
export TOASTER_MYSQL_PASS=""
export TOASTER_NRPE=""
export TOASTER_NTP=""
export TOASTER_PKG_AUDIT="0"
export TOASTER_PKG_BRANCH="latest"
export TOASTER_USE_TMPFS="0"
export TOASTER_VPOPMAIL_CLEAR="1"
export TOASTER_VPOPMAIL_EXT="0"
export TOASTER_WEBMAIL_PROXY="haproxy"
export CLAMAV_FANGFRISCH="0"
export GEOIP_UPDATER="geoipupdate"
export MAXMIND_ACCOUNT_ID=""
export MAXMIND_LICENSE_KEY=""
export ROUNDCUBE_SQL="0"
export ROUNDCUBE_DEFAULT_HOST=""
export ROUNDCUBE_PRODUCT_NAME="Roundcube Webmail"
export ROUNDCUBE_ATTACHMENT_SIZE_MB="25"
export TOASTER_HARAKA_VERSION=""
export UNIFI_MONGODB_DSN="mongodb://ubnt:$(get_random_pass)@mongodb:27017/unifi"
export VIRUSTOTAL_API_KEY=""

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
