# https://bats-core.readthedocs.io/en/stable/writing-tests.html

setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  export MT6_TEST_ENV=1
  load ../mail-toaster.sh
  # Manually load includes that mt6_init would have loaded
  load ../include/util.sh
  load ../include/config.sh
  load ../include/zfs.sh
  load ../include/jail.sh
  load ../include/network.sh
  # Initialize defaults that mt6_init would have set
  mt6_defaults
}

@test "safe_jailname replaces . with _" {
  run safe_jailname bad.chars
  assert_success
  assert_output "bad_chars"
}

@test "reverse_list" {
  run reverse_list tic tac toe
  #echo "# $output" >&3
  assert_success
  assert_output --partial "toe tac tic"
}

@test "tell_settings" {
  skip
  run tell_settings "ROUNDCUBE"
  assert_success
  assert_output --partial "
   ***   Configured ROUNDCUBE settings:"
}

@test "tell_status" {
  skip
  run tell_status "BATS testing"
  assert_success
}

@test "proclaim_success" {
  run proclaim_success "test"
  assert_success
  assert_output --partial "Success! A new 'test' jail is provisioned"
}

@test "get_random_pass 20" {
  run get_random_pass 20
  #echo "# $output" >&3
  assert_success
  assert_equal ${#output} 20
}

@test "get_random_pass (defaults)" {
  run get_random_pass
  #echo "# $output" >&3
  assert_success
  assert_equal ${#output} 14
}

@test "get_random_pass 14 strong" {
  run get_random_pass 14 strong
  #echo "# $output" >&3
  assert_success
  #assert_equal ${#output} 14
}

@test "get_random_pass 14 safe" {
  run get_random_pass 14 safe
  #echo "# $output" >&3
  assert_success
  #assert_equal ${#output} 14
}

@test "get_jail_ip mysql" {
  run get_jail_ip mysql
  assert_success
  assert_output "172.16.15.4"
}

@test "get_jail_ip haraka" {
  run get_jail_ip haraka
  assert_success
  assert_output "172.16.15.9"
}

@test "fstab_add_mount" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  mkdir -p "$tmpdir/myjail/etc"
  local fstab="$tmpdir/myjail/etc/fstab"
  touch "$fstab" "${fstab}.stage"

  # Mock tell_status
  tell_status() { :; }

  run fstab_add_mount myjail /src /dest
  assert_success

  run grep "/src" "$fstab"
  assert_success
  assert_output --partial "/dest"

  run grep "/src" "${fstab}.stage"
  assert_success

  rm -rf "$tmpdir"
}

@test "stage_sysrc" {
  export STAGE_MNT=$(mktemp -d)
  # Mock sysrc
  sysrc() {
    echo "sysrc called with $*"
  }

  run stage_sysrc myvar=value
  assert_success
  assert_output --partial "sysrc -R $STAGE_MNT myvar=value"

  rm -rf "$STAGE_MNT"
}

@test "stage_make_conf - new setting" {
  export STAGE_MNT=$(mktemp -d)
  mkdir -p "$STAGE_MNT/etc"
  local make_conf="$STAGE_MNT/etc/make.conf"
  touch "$make_conf"

  tell_status() { :; }

  run stage_make_conf MY_VAR "MY_VAR=val"
  assert_success

  run cat "$make_conf"
  assert_output "MY_VAR=val"

  rm -rf "$STAGE_MNT"
}

@test "stage_make_conf - existing setting" {
  export STAGE_MNT=$(mktemp -d)
  mkdir -p "$STAGE_MNT/etc"
  local make_conf="$STAGE_MNT/etc/make.conf"
  echo "MY_VAR=old" > "$make_conf"

  run stage_make_conf MY_VAR "MY_VAR=new"
  assert_success
  assert_output --partial "preserving make.conf settings"

  run cat "$make_conf"
  assert_output "MY_VAR=old"

  rm -rf "$STAGE_MNT"
}

@test "stage_resolv_conf" {
  export STAGE_MNT=$(mktemp -d)
  mkdir -p "$STAGE_MNT/etc"

  # Mock jail_is_running and get_jail_ip
  jail_is_running() { return 0; }
  get_jail_ip() { echo "1.2.3.4"; }
  get_jail_ip6() { echo "fe80::1"; }
  tell_status() { :; }

  run stage_resolv_conf
  assert_success

  run cat "$STAGE_MNT/etc/resolv.conf"
  assert_output --partial "nameserver 1.2.3.4"
  assert_output --partial "nameserver fe80::1"

  rm -rf "$STAGE_MNT"
}
