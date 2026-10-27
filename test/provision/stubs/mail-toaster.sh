#!/bin/sh
# Stub mail-toaster.sh for BATS provision testing.
# Placed first in PATH so provision scripts source this instead of the real one.

export MT6_TEST_ENV=1

export JAIL_NET_PREFIX=${JAIL_NET_PREFIX:-"172.16.15"}
export JAIL_ORDERED_LIST=${JAIL_ORDERED_LIST:-"syslog base dns mysql clamav spamassassin foundationdb vpopmail haraka webmail munin haproxy rspamd stalwart dovecot redis geoip nginx mailtest apache postgres minecraft joomla php7 memcached sphinxsearch elasticsearch nictool sqwebmail dhcp letsencrypt tinydns roundcube squirrelmail rainloop rsnapshot mediawiki smf wordpress whmcs squirrelcart horde grafana unifi mongodb gitlab gitlab_runner dcc prometheus influxdb telegraf statsd mail_dmarc ghost jekyll borg nagios postfix puppeteer snappymail knot nsd bsd_cache wildduck zonemta centos ubuntu bhyve-ubuntu mailman git tachyon"}
export ZFS_VOL=${ZFS_VOL:-"zroot"}
_stub_root="${BATS_FILE_TMPDIR:-/nonexistent}"
export ZFS_JAIL_MNT=${ZFS_JAIL_MNT:-"$_stub_root/jails"}
export ZFS_DATA_MNT=${ZFS_DATA_MNT:-"$_stub_root/data"}
export ZFS_JAIL_VOL="${ZFS_VOL}${ZFS_JAIL_MNT}"
export ZFS_DATA_VOL="${ZFS_VOL}${ZFS_DATA_MNT}"
export STAGE_MNT=${STAGE_MNT:-"$ZFS_JAIL_MNT/stage"}
export SAFE_NAME=${SAFE_NAME:-"stage"}
export BASE_MNT=${BASE_MNT:-"$ZFS_JAIL_MNT/base"}
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
export TOASTER_BASE_METHOD=${TOASTER_BASE_METHOD:-"fetch"}
export TOASTER_BASE_PKG_BRANCH=${TOASTER_BASE_PKG_BRANCH:-""}
export TOASTER_VPOPMAIL_CLEAR=${TOASTER_VPOPMAIL_CLEAR:-"1"}
export TOASTER_VPOPMAIL_EXT=${TOASTER_VPOPMAIL_EXT:-"0"}
export TOASTER_USE_TMPFS=${TOASTER_USE_TMPFS:-"0"}
export TLS_LIBRARY=${TLS_LIBRARY:-""}
export JAIL_NET6=${JAIL_NET6:-"fd7a:e5cd:1fc1:c597:dead:beef:cafe"}
export PUBLIC_IP4=""
export PUBLIC_IP6=""
export ROUNDCUBE_SQL=${ROUNDCUBE_SQL:-"0"}
export MT6_CONF_DIR=${MT6_CONF_DIR:-"conf.d"}
export MT6_CONF=${MT6_CONF:-"$MT6_CONF_DIR/mail-toaster.conf"}

# Logging / status
tell_status()    { :; }
fatal_err()      { echo "FATAL: $*" >&2; }
err_exit()       { echo "ERR: $*" >&2; }
proclaim_success() { :; }
tell_settings()  { :; }
service_config() { :; }

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
unmount_data()             { :; }
stage_clear_caches()       { :; }

# Jail lifecycle
create_staged_fs()         { :; }
start_staged_jail()        { :; }
promote_staged_jail()      { :; }
stop_jail()                { :; }
seed_pkg_audit()           { :; }

# Jail helpers
jail_is_running()          { return 1; }
# Numbers the jails as include/jail.sh does, less the host(1) fallback for an
# unlisted jail. Bats traps DEBUG on every command, so the per-jail loop
# include/jail.sh runs would cost ~20ms a lookup; counting the names ahead of
# the jail costs the same few commands wherever it sits in the list.
_jail_octet() {
  local _jail="$1" _start=${JAIL_NET_START:-1}

  case "$_jail" in
    syslog) _octet="$_start";           return ;;
    base*)  _octet="$((_start + 1))";   return ;;
    stage)  _octet=254;                 return ;;
  esac

  # shellcheck disable=SC2086
  set -- $JAIL_ORDERED_LIST
  local _list=" $* "
  case "$_list" in *" $_jail "*) ;; *) return 2 ;; esac

  # shellcheck disable=SC2086
  set -- ${_list%% "$_jail" *}
  _octet="$((_start + $#))"
}

get_jail_ip4() {
  local _octet
  _jail_octet "$1" || return
  echo "$JAIL_NET_PREFIX.$_octet"
}

get_jail_ip() {
  get_jail_ip4 "$@"
}

get_jail_ip6() {
  local _octet
  _jail_octet "$1" || return
  echo "$JAIL_NET6:$(dec_to_hex "$_octet")"
}
get_jail_data()            { echo "${ZFS_DATA_MNT}/$1"; }
export MT6_ETC=${MT6_ETC:-"$_stub_root/etc/mail-toaster"}
get_jail_host_etc()        { echo "${MT6_ETC}/$1"; }
get_pfrule_path()          { echo "${MT6_ETC}/pfrule.sh"; }
safe_jailname()            { echo "$1" | tr '.-' '__'; }
add_jail_conf()            { :; }
add_jail_conf_d()          { :; }
assure_ip6_addr_is_declared() { :; }
configure_pf_jail_table()  { :; }
configure_mta_pf_rdr()     { :; }
install_fstab()            { :; }
fstab_add_mount()          { :; }

# Stage operations
stage_fbsd_package()       { :; }
stage_fbsd_pkgbase()       { :; }
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
has_public_ip4()           { get_public_ip4; [ -n "${PUBLIC_IP4:-}" ]; }
has_public_ip6()           { get_public_ip6; [ -n "${PUBLIC_IP6:-}" ]; }
jail_has_ip6()             { has_public_ip6; }
get_public_ip4()           { :; }
get_public_ip6()           { :; }
get_public_facing_nic()    { :; }
install_pfrule()           { :; }
install_acme_sh()          { :; }
install_minimal_hosts()    { :; }

# Config / util
sed_inplace()              { sed -i.bak "$@"; }
store_config() {
  local _operation=${2:-""}
  [ -d "$(dirname "$1")" ] || mkdir -p "$(dirname "$1")"
  cat - > "$1.mt6"
  if [ ! -f "$1" ] || [ "$_operation" = "overwrite" ]; then
    cp "$1.mt6" "$1"
  elif [ "$_operation" = "append" ]; then
    cat "$1.mt6" >> "$1"
  fi
}
store_exec()               { cat - > /dev/null; }
preserve_file()            { :; }
configure_pkg_latest()     { :; }
enable_bsd_cache()         { :; }
get_random_pass()          { echo "testpassword14x"; }
dec_to_hex()               { printf '%04x\n' "$1"; }
_file_mode() {
  case "$(uname)" in
    Linux*) stat -c "%a" "$1" ;;
    *)      stat -f "%OLp" "$1" ;;
  esac
}
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
install_php_newsyslog()    { :; }
configure_php()            { :; }
configure_php_ini()        { :; }
configure_php_fpm()        { :; }
start_php_fpm()            { :; }
test_php_fpm()             { :; }
php_quote()                { echo "$1"; }

# Nginx include stubs
install_nginx()            { :; }
install_nginx_newsyslog()  { :; }
configure_nginx()          { :; }
configure_nginx_server_d() { :; }
start_nginx()              { :; }
test_nginx()               { :; }
contains()                 { [ "${1#*"$2"}" != "$1" ]; }
nginx_listen()             { printf '\t\tlisten       %s%s;\n\t\tlisten  [::]:%s%s;\n' "${1:-80}" "${2:+ $2}" "${1:-80}" "${2:+ $2}"; }

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

# FreeBSD system commands
jexec()    { echo "stubpass"; }
sysctl()   { echo "1073741824"; }  # ~1 GB; keeps phishing checks disabled
# sysrc()    { :; }
rspamadm() { echo "stub-rspamadm-hash"; }
chown()    { :; }  # non-root CI environments can't chown
assure_devfs_bpf_ruleset() { :; }
stage_enable_quotas()      { :; }
