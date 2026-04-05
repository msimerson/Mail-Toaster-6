#!/bin/sh
# Stub mail-toaster.sh for BATS provision testing.
# Placed first in PATH so provision scripts source this instead of the real one.

export MT6_TEST_ENV=1

export JAIL_NET_PREFIX=${JAIL_NET_PREFIX:-"172.16.15"}
export JAIL_ORDERED_LIST=${JAIL_ORDERED_LIST:-"syslog base dns mysql clamav spamassassin foundationdb vpopmail haraka webmail munin haproxy rspamd stalwart dovecot redis geoip nginx mailtest apache postgres minecraft joomla php7 memcached sphinxsearch elasticsearch nictool sqwebmail dhcp letsencrypt tinydns roundcube squirrelmail rainloop rsnapshot mediawiki smf wordpress whmcs squirrelcart horde grafana unifi mongodb gitlab gitlab_runner dcc prometheus influxdb telegraf statsd mail_dmarc ghost jekyll borg nagios postfix puppeteer snappymail knot nsd bsd_cache wildduck zonemta centos ubuntu bhyve-ubuntu mailman"}
export ZFS_VOL=${ZFS_VOL:-"zroot"}
export ZFS_JAIL_MNT=${ZFS_JAIL_MNT:-"/jails"}
export ZFS_DATA_MNT=${ZFS_DATA_MNT:-"/data"}
export ZFS_JAIL_VOL="${ZFS_VOL}${ZFS_JAIL_MNT}"
export ZFS_DATA_VOL="${ZFS_VOL}${ZFS_DATA_MNT}"
export STAGE_MNT=${STAGE_MNT:-"$ZFS_JAIL_MNT/stage"}
export SAFE_NAME=${SAFE_NAME:-"stage"}
export BASE_MNT=${BASE_MNT:-"/jails/base"}
export BASE_SNAP=${BASE_SNAP:-"zroot/jails/base@p0"}
export TOASTER_HOSTNAME=${TOASTER_HOSTNAME:-"mail.example.com"}
export TOASTER_MAIL_DOMAIN=${TOASTER_MAIL_DOMAIN:-"example.com"}
export TOASTER_ADMIN_EMAIL=${TOASTER_ADMIN_EMAIL:-"postmaster@example.com"}
export TOASTER_MYSQL=${TOASTER_MYSQL:-"1"}
export TOASTER_MARIADB=${TOASTER_MARIADB:-"0"}
export TOASTER_MSA=${TOASTER_MSA:-"haraka"}
export TOASTER_EDITOR=${TOASTER_EDITOR:-"vim"}
export TOASTER_EDITOR_PORT=${TOASTER_EDITOR_PORT:-"vim-tiny"}
export TOASTER_PKG_BRANCH=${TOASTER_PKG_BRANCH:-"latest"}
export TOASTER_VPOPMAIL_CLEAR=${TOASTER_VPOPMAIL_CLEAR:-"1"}
export TOASTER_VPOPMAIL_EXT=${TOASTER_VPOPMAIL_EXT:-"0"}
export TOASTER_USE_TMPFS=${TOASTER_USE_TMPFS:-"0"}
export TLS_LIBRARY=${TLS_LIBRARY:-""}
export JAIL_NET6=${JAIL_NET6:-"fd7a:e5cd:1fc1:c597:dead:beef:cafe"}
export PUBLIC_IP4=""
export PUBLIC_IP6=""
export ROUNDCUBE_SQL=${ROUNDCUBE_SQL:-"0"}

# Logging / status
tell_status()    { :; }
fatal_err()      { echo "FATAL: $*" >&2; }
err_exit()       { echo "ERR: $*" >&2; }
proclaim_success() { :; }
tell_settings()  { :; }

# Versioning
mt6_version()    { echo "20260403"; }
mt6_version_check() { :; }
mt6-fetch()      { :; }
mt6-include()    { :; }
mt6_defaults()   { :; }
mt6_init()       { :; }

# ZFS / filesystem
base_snapshot_exists()     { return 0; }
zfs_filesystem_exists()    { return 0; }
zfs_snapshot_exists()      { return 0; }
zfs_create_fs()            { :; }
zfs_destroy_fs()           { :; }
zfs_dataset_property()     { echo "none"; }
cleanup_staged_fs()        { :; }
rename_staged_to_ready()   { :; }
rename_active_to_last()    { :; }
rename_ready_to_active()   { :; }
stage_unmount()            { :; }
stage_clear_caches()       { :; }

# Jail lifecycle
create_staged_fs()         { :; }
start_staged_jail()        { :; }
promote_staged_jail()      { :; }
stop_jail()                { :; }
seed_pkg_audit()           { :; }

# Jail helpers
jail_is_running()          { return 1; }
get_jail_ip() {
  local _name="$1" _idx=1
  for _j in $JAIL_ORDERED_LIST; do
    if [ "$_j" = "$_name" ]; then echo "$JAIL_NET_PREFIX.$_idx"; return 0; fi
    _idx=$((_idx + 1))
  done
  echo "172.16.15.1"
}
get_jail_ip6()             { echo "fd7a:e5cd:1fc1:c597:1"; }
get_jail_data()            { echo "${ZFS_DATA_MNT}/$1"; }
safe_jailname()            { echo "$1" | tr '.-' '__'; }
add_jail_conf()            { :; }
add_jail_conf_d()          { :; }
assure_ip6_addr_is_declared() { :; }
install_fstab()            { :; }
fstab_add_mount()          { :; }

# Stage operations
stage_pkg_install()        { :; }
stage_port_install()       { :; }
stage_exec()               { :; }
stage_sysrc()              { :; }
stage_make_conf()          { :; }
stage_listening()          { :; }
stage_test_running()       { :; }
stage_enable_newsyslog()   { :; }
stage_resolv_conf()        { :; }

# Network
port_is_listening()        { return 0; }
get_random_ip6net()        { echo "fd7a:e5cd:1fc1:dead:beef:cafe:1"; }
get_public_ip()            { :; }
get_public_facing_nic()    { :; }
install_pfrule()           { :; }
install_acme_sh()          { :; }

# Config / util
store_config()             { cat - > /dev/null; }
store_exec()               { cat - > /dev/null; }
preserve_file()            { :; }
configure_pkg_latest()     { :; }
enable_bsd_cache()         { :; }
get_random_pass()          { echo "testpassword14x"; }
dec_to_hex()               { printf '%04x\n' "$1"; }
reverse_list() {
  local _r=""
  for _j in "$@"; do _r="${_j} ${_r}"; done
  echo "$_r"
}

# MySQL include stubs
mysql_db_exists()          { return 1; }
mysql_user_exists()        { return 1; }
mysql_create_db()          { :; }
mysql_query()              { :; }
mysql_perm()               { :; }
mysql_bin()                { echo "mysql"; }
mysql_error_warning()      { :; }

# PHP include stubs
install_php()              { :; }
configure_php()            { :; }
configure_php_ini()        { :; }
configure_php_fpm()        { :; }
start_php_fpm()            { :; }
test_php_fpm()             { :; }
php_quote()                { echo "$1"; }

# Nginx include stubs
install_nginx()            { :; }
configure_nginx()          { :; }
configure_nginx_server_d() { :; }
start_nginx()              { :; }
test_nginx()               { :; }
contains()                 { [ "${1#*"$2"}" != "$1" ]; }

# MTA include stubs
configure_mta()            { :; }
disable_sendmail()         { :; }
enable_dma()               { :; }
enable_sendmail()          { :; }
set_root_alias()           { :; }

# Vpopmail include stubs
install_vpopmail_deps()    { :; }
install_qmail()            { :; }

# Editor include stubs
configure_editor()         { :; }

# Shell include stubs
install_bash()             { :; }
configure_bash()           { :; }
configure_bourne_shell()   { :; }
configure_csh_shell()      { :; }

# User include stubs
preserve_passdb()          { :; }
preserve_ssh_host_keys()   { :; }

# Linux include stubs
configure_linuxulator()    { :; }
configure_apt_sources()    { :; }
install_apt_updates()      { :; }
install_linux()            { :; }

# DJB include stubs
install_daemontools()      { :; }
configure_svscan()         { :; }

# Misc provision helpers
add_devfs_rule()           { :; }
stage_enable_quotas()      { :; }
