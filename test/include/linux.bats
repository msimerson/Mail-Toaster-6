#!/usr/bin/env bats

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  export STAGE_MNT; STAGE_MNT=$(mktemp -d)
  mkdir -p "$STAGE_MNT/compat/linux/etc/apt"
  load '../../include/linux.sh'
  set +e  # linux.sh sets -e; let BATS control error handling
}

teardown() {
  rm -rf "$STAGE_MNT"
}

tell_status() { :; }

@test "configure_apt_sources - bionic writes ubuntu archive url" {
  configure_apt_sources bionic > /dev/null
  run grep "archive.ubuntu.com" "$STAGE_MNT/compat/linux/etc/apt/sources.list"
  assert_success
}

@test "configure_apt_sources - bionic includes release name" {
  configure_apt_sources bionic > /dev/null
  run grep "bionic" "$STAGE_MNT/compat/linux/etc/apt/sources.list"
  assert_success
}

@test "configure_apt_sources - focal includes focal" {
  configure_apt_sources focal > /dev/null
  run grep "focal" "$STAGE_MNT/compat/linux/etc/apt/sources.list"
  assert_success
}

@test "configure_apt_sources - noble writes ubuntu archive url" {
  configure_apt_sources noble > /dev/null
  run grep "archive.ubuntu.com" "$STAGE_MNT/compat/linux/etc/apt/sources.list"
  assert_success
}

@test "configure_apt_sources - bookworm writes debian url" {
  configure_apt_sources bookworm > /dev/null
  run grep "deb.debian.org" "$STAGE_MNT/compat/linux/etc/apt/sources.list"
  assert_success
}

@test "configure_apt_sources - bookworm includes release name" {
  configure_apt_sources bookworm > /dev/null
  run grep "bookworm" "$STAGE_MNT/compat/linux/etc/apt/sources.list"
  assert_success
}

@test "configure_apt_sources - bullseye writes debian url" {
  configure_apt_sources bullseye > /dev/null
  run grep "deb.debian.org" "$STAGE_MNT/compat/linux/etc/apt/sources.list"
  assert_success
}

@test "configure_apt_sources - trixie writes debian url" {
  configure_apt_sources trixie > /dev/null
  run grep "deb.debian.org" "$STAGE_MNT/compat/linux/etc/apt/sources.list"
  assert_success
}

@test "configure_apt_sources - ubuntu includes security repo" {
  configure_apt_sources jammy > /dev/null
  run grep "security.ubuntu.com" "$STAGE_MNT/compat/linux/etc/apt/sources.list"
  assert_success
}

@test "configure_apt_sources - debian includes security repo" {
  configure_apt_sources bullseye > /dev/null
  run grep "debian-security" "$STAGE_MNT/compat/linux/etc/apt/sources.list"
  assert_success
}
