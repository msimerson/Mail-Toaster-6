#!/usr/bin/env bats
# Functional tests for provision/statsd.sh

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export STAGE_MNT; STAGE_MNT=$(mktemp -d)
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  # Pre-create dirs and stub config.js so install_statsd can run
  mkdir -p "$STAGE_MNT/var/lib"
  mkdir -p "$STAGE_MNT/usr/local/share/statsd/lib"
  printf ' process.EventEmitter = require("events").EventEmitter;\n' \
    > "$STAGE_MNT/usr/local/share/statsd/lib/config.js"

  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../provision/statsd.sh"
}

teardown() {
  rm -rf "$STAGE_MNT"
}

# --- JAIL variable exports ---

@test "statsd - JAIL_START_EXTRA is empty" {
  assert_equal "$JAIL_START_EXTRA" ""
}

@test "statsd - JAIL_CONF_EXTRA is empty" {
  assert_equal "$JAIL_CONF_EXTRA" ""
}

@test "statsd - JAIL_FSTAB is empty" {
  assert_equal "$JAIL_FSTAB" ""
}

# --- Function existence ---

@test "statsd - defines install_statsd" {
  run type install_statsd
  assert_success
}

@test "statsd - defines start_statsd" {
  run type start_statsd
  assert_success
}

@test "statsd - defines test_statsd" {
  run type test_statsd
  assert_success
}

# --- install_statsd behaviour ---

@test "statsd - install uses statsd package" {
  stage_pkg_install() { echo "PKG:$*"; }
  stage_sysrc()       { :; }
  run install_statsd
  assert_output --partial "PKG:statsd"
}

@test "statsd - install enables statsd via sysrc" {
  stage_pkg_install() { return 0; }
  stage_sysrc()       { echo "SYSRC:$*"; }
  run install_statsd
  assert_output --partial "SYSRC:statsd_enable=YES"
}

# --- start_statsd behaviour ---

@test "statsd - start calls service statsd start" {
  stage_exec() { echo "EXEC:$*"; }
  run start_statsd
  assert_success
  assert_output --partial "EXEC:service statsd start"
}

# --- test_statsd behaviour ---

@test "statsd - test checks statsd is running" {
  stage_test_running() { echo "RUNNING:$*"; }
  run test_statsd
  assert_success
  assert_output --partial "RUNNING:statsd"
}
