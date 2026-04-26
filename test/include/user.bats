#!/usr/bin/env bats

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  export ZFS_JAIL_MNT; ZFS_JAIL_MNT=$(mktemp -d)
  export STAGE_MNT; STAGE_MNT=$(mktemp -d)
  load '../../include/user.sh'
}

teardown() {
  rm -rf "$ZFS_JAIL_MNT" "$STAGE_MNT"
}

tell_status() { :; }

@test "preserve_passdb - fails without jail name" {
  run preserve_passdb
  assert_failure
  assert_output --partial "jail name is required"
}

@test "preserve_passdb - succeeds with jail name (no files to copy)" {
  run preserve_passdb nonexistent_jail
  assert_success
}

@test "preserve_passdb - copies master.passwd when present" {
  local jail="testjail"
  mkdir -p "$ZFS_JAIL_MNT/$jail/etc"
  echo "root::0:0::0:0:Charlie &:/root:/bin/sh" > "$ZFS_JAIL_MNT/$jail/etc/master.passwd"
  mkdir -p "$STAGE_MNT/etc"

  stage_exec() { :; }  # mock pwd_mkdb

  preserve_passdb "$jail"

  [ -f "$STAGE_MNT/etc/master.passwd" ]
}

@test "preserve_passdb - copies group when present" {
  local jail="testjail"
  mkdir -p "$ZFS_JAIL_MNT/$jail/etc"
  echo "wheel:*:0:root" > "$ZFS_JAIL_MNT/$jail/etc/group"
  mkdir -p "$STAGE_MNT/etc"

  stage_exec() { :; }

  preserve_passdb "$jail"

  [ -f "$STAGE_MNT/etc/group" ]
}

@test "preserve_ssh_host_keys - fails without jail name" {
  run preserve_ssh_host_keys
  assert_failure
  assert_output --partial "jail name is required"
}

@test "preserve_ssh_host_keys - succeeds with jail name (no keys to copy)" {
  run preserve_ssh_host_keys nonexistent_jail
  assert_success
}
