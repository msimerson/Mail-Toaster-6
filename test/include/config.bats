#!/usr/bin/env bats

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  load '../../include/config.sh'
}

@test "mt6_defaults - sets BOURNE_SHELL to bash" {
  unset BOURNE_SHELL
  mt6_defaults
  assert_equal "$BOURNE_SHELL" "bash"
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
  (cd "$_tmpdir" && _add_config_hint)
  grep -q "grep ^export ./include/config.sh" "$_tmpdir/mail-toaster.conf"
}

@test "_add_config_hint - does not duplicate existing hint" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf '# grep ^export ./include/config.sh\n' > "$_tmpdir/mail-toaster.conf"
  (cd "$_tmpdir" && _add_config_hint)
  local _count; _count=$(grep -c "grep.*config.sh" "$_tmpdir/mail-toaster.conf")
  assert_equal "$_count" "1"
}

@test "_fix_jail_ordered_list - no-op when JAIL_ORDERED_LIST absent" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf 'export TOASTER_HOSTNAME="test"\n' > "$_tmpdir/mail-toaster.conf"
  (cd "$_tmpdir" && _fix_jail_ordered_list)
  run grep "JAIL_ORDERED_LIST" "$_tmpdir/mail-toaster.conf"
  assert_failure
}

@test "_fix_jail_ordered_list - no-op when already starts with syslog base" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf 'export JAIL_ORDERED_LIST="syslog base dns mysql"\n' > "$_tmpdir/mail-toaster.conf"
  (cd "$_tmpdir" && _fix_jail_ordered_list)
  run grep "^export JAIL_ORDERED_LIST=" "$_tmpdir/mail-toaster.conf"
  assert_output 'export JAIL_ORDERED_LIST="syslog base dns mysql"'
}

@test "_fix_jail_ordered_list - moves syslog and base to front" {
  local _tmpdir; _tmpdir=$(mktemp -d)
  printf 'export JAIL_ORDERED_LIST="dns mysql syslog base clamav"\n' > "$_tmpdir/mail-toaster.conf"
  (cd "$_tmpdir" && _fix_jail_ordered_list)
  run grep "^export JAIL_ORDERED_LIST=" "$_tmpdir/mail-toaster.conf"
  assert_output 'export JAIL_ORDERED_LIST="syslog base dns mysql clamav"'
}
