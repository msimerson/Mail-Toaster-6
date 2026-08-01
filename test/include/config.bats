#!/usr/bin/env bats

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  load '../../include/config.sh'
}

# `run` forks, so the cd is contained to the subshell.
_in_dir() {
  local _dir="$1"; shift
  cd "$_dir" || return 1
  "$@"
}

_config_in() {
  cd "$1" || return 1
  config > /dev/null
  echo "$MT6_CONF|$TOASTER_HOSTNAME"
}

@test "mt6_defaults - sets BOURNE_SHELL to bash" {
  unset BOURNE_SHELL
  mt6_defaults
  assert_equal "$BOURNE_SHELL" "all"
}

@test "mt6_defaults - preserves existing BOURNE_SHELL" {
  export BOURNE_SHELL="sh"
  mt6_defaults
  assert_equal "$BOURNE_SHELL" "sh"
}

@test "mt6_defaults - sets JAIL_NET_PREFIX" {
  unset JAIL_NET_PREFIX
  mt6_defaults
  assert_equal "$JAIL_NET_PREFIX" "172.16.15"
}

@test "mt6_defaults - preserves existing JAIL_NET_PREFIX" {
  export JAIL_NET_PREFIX="10.0.0"
  mt6_defaults
  assert_equal "$JAIL_NET_PREFIX" "10.0.0"
}

@test "mt6_defaults - sets JAIL_NET_MASK" {
  unset JAIL_NET_MASK
  mt6_defaults
  assert_equal "$JAIL_NET_MASK" "/19"
}

@test "mt6_defaults - sets JAIL_NET_INTERFACE" {
  unset JAIL_NET_INTERFACE
  mt6_defaults
  assert_equal "$JAIL_NET_INTERFACE" "lo1"
}

@test "mt6_defaults - sets ZFS_VOL" {
  unset ZFS_VOL
  mt6_defaults
  assert_equal "$ZFS_VOL" "zroot"
}

@test "mt6_defaults - sets ZFS_JAIL_MNT" {
  unset ZFS_JAIL_MNT
  mt6_defaults
  assert_equal "$ZFS_JAIL_MNT" "/jails"
}

@test "mt6_defaults - sets ZFS_DATA_MNT" {
  unset ZFS_DATA_MNT
  mt6_defaults
  assert_equal "$ZFS_DATA_MNT" "/data"
}

@test "mt6_defaults - sets TOASTER_MYSQL to 1" {
  unset TOASTER_MYSQL
  mt6_defaults
  assert_equal "$TOASTER_MYSQL" "1"
}

@test "mt6_defaults - sets TOASTER_PKG_BRANCH to latest" {
  unset TOASTER_PKG_BRANCH
  mt6_defaults
  assert_equal "$TOASTER_PKG_BRANCH" "latest"
}

@test "mt6_defaults - sets TOASTER_NTP to chrony" {
  unset TOASTER_NTP
  mt6_defaults
  assert_equal "$TOASTER_NTP" "chrony"
}

@test "mt6_defaults - sets TOASTER_MSA to haraka" {
  unset TOASTER_MSA
  mt6_defaults
  assert_equal "$TOASTER_MSA" "haraka"
}

@test "mt6_defaults - preserves explicit TOASTER_BASE_METHOD" {
  export TOASTER_BASE_METHOD="bsdinstall"
  mt6_defaults
  assert_equal "$TOASTER_BASE_METHOD" "bsdinstall"
}

@test "default_base_method - returns fetch on non-pkgbase host" {
  uname() { echo "Linux"; }
  run default_base_method
  assert_output "fetch"
}

@test "default_base_method - returns pkgbase when FreeBSD-bootloader installed" {
  uname() { echo "FreeBSD"; }
  pkg() { [ "$1 $2" = "info -e" ] && [ "$3" = "FreeBSD-bootloader" ]; }
  run default_base_method
  assert_output "pkgbase"
}

@test "mt6_defaults - computes ZFS_JAIL_VOL" {
  unset ZFS_VOL ZFS_JAIL_MNT ZFS_JAIL_VOL
  mt6_defaults
  assert_equal "$ZFS_JAIL_VOL" "zroot/jails"
}

@test "mt6_defaults - computes ZFS_DATA_VOL" {
  unset ZFS_VOL ZFS_DATA_MNT ZFS_DATA_VOL
  mt6_defaults
  assert_equal "$ZFS_DATA_VOL" "zroot/data"
}

@test "mt6_defaults - ZFS_JAIL_VOL uses custom ZFS_VOL" {
  export ZFS_VOL="tank"
  unset ZFS_JAIL_MNT ZFS_JAIL_VOL
  mt6_defaults
  assert_equal "$ZFS_JAIL_VOL" "tank/jails"
}

@test "mt6_defaults - sets STAGE_MNT" {
  unset ZFS_JAIL_MNT
  mt6_defaults
  assert_equal "$STAGE_MNT" "/jails/stage"
}

@test "_add_config_hint - appends hint when missing" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf 'export TOASTER_HOSTNAME="test"\n' > "$_tmpdir/mail-toaster.conf"
  _add_config_hint "$_tmpdir/mail-toaster.conf"
  grep -q "include/config.sh" "$_tmpdir/mail-toaster.conf"
  grep -q "provision/" "$_tmpdir/mail-toaster.conf"
}

# The hint has to find per-jail defaults too, now that they live in the
# provision scripts rather than mt6_defaults.
@test "_add_config_hint - the suggested grep finds both global and per-jail defaults" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf 'export TOASTER_HOSTNAME="test"\n' > "$_tmpdir/mail-toaster.conf"
  _add_config_hint "$_tmpdir/mail-toaster.conf"

  local _cmd
  _cmd=$(grep -o 'grep -rn .*' "$_tmpdir/mail-toaster.conf")
  cd "$BATS_TEST_DIRNAME/../.." || return 1

  run eval "$_cmd"
  assert_success
  assert_output --partial "include/config.sh:"
  assert_output --partial "provision/clamav.sh:"
}

@test "_add_config_hint - does not duplicate existing hint" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf '# grep ^export ./include/config.sh\n' > "$_tmpdir/mail-toaster.conf"
  _add_config_hint "$_tmpdir/mail-toaster.conf"
  local _count; _count=$(grep -c "grep.*config.sh" "$_tmpdir/mail-toaster.conf")
  assert_equal "$_count" "1"
}

@test "_fix_jail_ordered_list - no-op when JAIL_ORDERED_LIST absent" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf 'export TOASTER_HOSTNAME="test"\n' > "$_tmpdir/mail-toaster.conf"
  _fix_jail_ordered_list "$_tmpdir/mail-toaster.conf"
  run grep "JAIL_ORDERED_LIST" "$_tmpdir/mail-toaster.conf"
  assert_failure
}

@test "_fix_jail_ordered_list - no-op when already starts with syslog base" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf 'export JAIL_ORDERED_LIST="syslog base dns mysql"\n' > "$_tmpdir/mail-toaster.conf"
  _fix_jail_ordered_list "$_tmpdir/mail-toaster.conf"
  run grep "^export JAIL_ORDERED_LIST=" "$_tmpdir/mail-toaster.conf"
  assert_output 'export JAIL_ORDERED_LIST="syslog base dns mysql"'
}

@test "_fix_jail_ordered_list - moves syslog and base to front" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf 'export JAIL_ORDERED_LIST="dns mysql syslog base clamav"\n' > "$_tmpdir/mail-toaster.conf"
  _fix_jail_ordered_list "$_tmpdir/mail-toaster.conf"
  run grep "^export JAIL_ORDERED_LIST=" "$_tmpdir/mail-toaster.conf"
  assert_output 'export JAIL_ORDERED_LIST="syslog base dns mysql clamav"'
}

@test "_fix_jail_ordered_list - leaves no .bak file behind" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf 'export JAIL_ORDERED_LIST="dns syslog base"\n' > "$_tmpdir/mail-toaster.conf"
  _fix_jail_ordered_list "$_tmpdir/mail-toaster.conf"
  run test -e "$_tmpdir/mail-toaster.conf.bak"
  assert_failure
}

@test "_migrate_config_to_conf_d - moves legacy config into conf.d" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf 'export TOASTER_HOSTNAME="legacy"\n' > "$_tmpdir/mail-toaster.conf"
  (cd "$_tmpdir" && _migrate_config_to_conf_d "conf.d/mail-toaster.conf")
  run test -e "$_tmpdir/mail-toaster.conf"
  assert_failure
  run grep "^export TOASTER_HOSTNAME=" "$_tmpdir/conf.d/mail-toaster.conf"
  assert_output 'export TOASTER_HOSTNAME="legacy"'
}

@test "_migrate_config_to_conf_d - succeeds when conf.d already exists" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf 'export TOASTER_HOSTNAME="legacy"\n' > "$_tmpdir/mail-toaster.conf"
  mkdir -p "$_tmpdir/conf.d"
  run _in_dir "$_tmpdir" _migrate_config_to_conf_d "conf.d/mail-toaster.conf"
  assert_success
}

@test "_tighten_config_perms - chmods a world-readable config to 600" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf 'export TOASTER_HOSTNAME="test"\n' > "$_tmpdir/mail-toaster.conf"
  chmod 644 "$_tmpdir/mail-toaster.conf"
  _tighten_config_perms "$_tmpdir/mail-toaster.conf"
  run _file_mode "$_tmpdir/mail-toaster.conf"
  assert_output "600"
}

@test "service_config - fails without a service name" {
  run service_config
  assert_failure
  assert_output --partial "service name is required"
}

@test "service_config - no-op when the override file is absent" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  export MT6_CONF_DIR="$_tmpdir/conf.d"
  unset CLAMAV_UNOFFICIAL
  run service_config clamav
  assert_success
  assert_output ""
}

@test "service_config - override file wins over mt6_defaults" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  export MT6_CONF_DIR="$_tmpdir/conf.d"
  mkdir -p "$MT6_CONF_DIR"
  printf 'export ROUNDCUBE_SQL="0"\n' > "$MT6_CONF_DIR/roundcube.conf"

  unset ROUNDCUBE_SQL
  export TOASTER_MYSQL="1"
  mt6_defaults
  assert_equal "$ROUNDCUBE_SQL" "1"

  service_config roundcube
  assert_equal "$ROUNDCUBE_SQL" "0"
}

# A provision script applies its defaults after service_config, so a setting the
# override file supplies must survive the ${VAR:-default} that follows it.
@test "service_config - a provision script default does not clobber the override" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  export MT6_CONF_DIR="$_tmpdir/conf.d"
  mkdir -p "$MT6_CONF_DIR"
  printf 'export CLAMAV_UNOFFICIAL="1"\n' > "$MT6_CONF_DIR/clamav.conf"

  unset CLAMAV_UNOFFICIAL CLAMAV_FANGFRISCH
  service_config clamav
  export CLAMAV_FANGFRISCH=${CLAMAV_FANGFRISCH:-"0"}
  export CLAMAV_UNOFFICIAL=${CLAMAV_UNOFFICIAL:-"0"}

  assert_equal "$CLAMAV_UNOFFICIAL" "1"
  assert_equal "$CLAMAV_FANGFRISCH" "0"
}

# Guards the upgrade path: a setting added upstream after the user's conf.d file
# was written still gets its default from the provision script.
@test "service_config - settings absent from the override file get the script default" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  export MT6_CONF_DIR="$_tmpdir/conf.d"
  mkdir -p "$MT6_CONF_DIR"
  printf 'export CLAMAV_UNOFFICIAL="1"\n' > "$MT6_CONF_DIR/clamav.conf"

  unset CLAMAV_NEW_KNOB
  service_config clamav
  export CLAMAV_NEW_KNOB=${CLAMAV_NEW_KNOB:-"yes"}
  assert_equal "$CLAMAV_NEW_KNOB" "yes"
}

@test "config - migrates a legacy mail-toaster.conf and loads it from conf.d" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf 'export TOASTER_HOSTNAME="migrated.example.com"\n' > "$_tmpdir/mail-toaster.conf"
  run _config_in "$_tmpdir"
  assert_output "conf.d/mail-toaster.conf|migrated.example.com"
  run test -e "$_tmpdir/mail-toaster.conf"
  assert_failure
}

@test "config - loads an existing conf.d config without touching the legacy path" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  mkdir -p "$_tmpdir/conf.d"
  printf 'export TOASTER_HOSTNAME="already.example.com"\n' > "$_tmpdir/conf.d/mail-toaster.conf"
  run _config_in "$_tmpdir"
  assert_output "conf.d/mail-toaster.conf|already.example.com"
}

@test "service_config - tightens permissions on the override file" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  export MT6_CONF_DIR="$_tmpdir/conf.d"
  mkdir -p "$MT6_CONF_DIR"
  printf 'export VIRUSTOTAL_API_KEY="secret"\n' > "$MT6_CONF_DIR/rspamd.conf"
  chmod 644 "$MT6_CONF_DIR/rspamd.conf"
  service_config rspamd
  run _file_mode "$MT6_CONF_DIR/rspamd.conf"
  assert_output "600"
}
