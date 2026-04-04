#!/usr/bin/env bats
# Functional tests for provision/memcached.sh
# Uses stub mail-toaster.sh via PATH injection so the provision script can be
# sourced without FreeBSD infrastructure.

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export STAGE_MNT; STAGE_MNT=$(mktemp -d)

  # Inject stub directory first in PATH so '. mail-toaster.sh' finds the stub
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  # Source the provision script; the execution block runs against stub functions
  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../provision/memcached.sh"
}

teardown() {
  rm -rf "$STAGE_MNT"
}

# --- JAIL variable exports ---

@test "memcached - JAIL_START_EXTRA is empty (no special capabilities needed)" {
  assert_equal "$JAIL_START_EXTRA" ""
}

@test "memcached - JAIL_CONF_EXTRA is empty" {
  assert_equal "$JAIL_CONF_EXTRA" ""
}

@test "memcached - JAIL_FSTAB is empty (no extra mounts needed)" {
  assert_equal "$JAIL_FSTAB" ""
}

# --- Function existence ---

@test "memcached - defines install_memcached" {
  run type install_memcached
  assert_success
}

@test "memcached - defines start_memcached" {
  run type start_memcached
  assert_success
}

@test "memcached - defines test_memcached" {
  run type test_memcached
  assert_success
}

# --- install_memcached behaviour ---

@test "memcached - install installs memcached package" {
  stage_pkg_install() { echo "PKG:$*"; }
  run install_memcached
  assert_success
  assert_output --partial "PKG:memcached"
}

# --- start_memcached behaviour ---

@test "memcached - start enables service via sysrc" {
  stage_sysrc() { echo "SYSRC:$*"; }
  stage_exec()  { :; }
  run start_memcached
  assert_success
  assert_output --partial "SYSRC:memcached_enable=YES"
}

@test "memcached - start calls service memcached start" {
  stage_sysrc() { :; }
  stage_exec()  { echo "EXEC:$*"; }
  run start_memcached
  assert_success
  assert_output --partial "EXEC:service memcached start"
}

# --- test_memcached behaviour ---

@test "memcached - test checks port 11211" {
  stage_listening() { echo "PORT:$*"; }
  run test_memcached
  assert_success
  assert_output --partial "PORT:11211"
}
