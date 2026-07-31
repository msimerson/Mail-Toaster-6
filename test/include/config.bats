#!/usr/bin/env bats

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  load '../../include/config.sh'
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
  grep -q "grep ^export ./include/config.sh" "$_tmpdir/mail-toaster.conf"
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

@test "_migrate_config_to_conf_d - moves mail-toaster.conf to conf.d/" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf 'export JAIL_ORDERED_LIST="dns mysql syslog base clamav"\n' > "$_tmpdir/mail-toaster.conf"
  cd "$_tmpdir"
  run _migrate_config_to_conf_d "conf.d/mail-toaster.conf"
  # shellcheck disable=SC2103
  cd -
  assert_success
  run test -e "$_tmpdir/mail-toaster.conf"
  assert_failure
  run grep "^export JAIL_ORDERED_LIST=" "$_tmpdir/conf.d/mail-toaster.conf"
  assert_output 'export JAIL_ORDERED_LIST="dns mysql syslog base clamav"'
}

@test "_migrate_config_to_conf_d - returns 1 when there's nothing to migrate" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  cd "$_tmpdir"
  run _migrate_config_to_conf_d "conf.d/mail-toaster.conf"
  # shellcheck disable=SC2103
  cd -
  assert_failure
}

@test "create_default_config - creates default config where it's told to" {
  uname() { echo "Linux"; }
  get_random_ip6net() { echo "fd7a:e5cd:1fc1:dead:beef:cafe:1"; }
  store_config() { cat > "$1"; }

  local _tmpdir; _tmpdir=$(mktemp -d)
  run create_default_config "$_tmpdir/mail-toaster.conf"
  assert_success
  run grep '^export TOASTER_ORG_NAME=\"Sparky' "$_tmpdir/mail-toaster.conf"
  assert_success
}
