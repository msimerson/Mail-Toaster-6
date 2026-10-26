#!/usr/bin/env bats
# Functional tests for provision/memcached.sh
#
# setup_file sources memcached.sh once against $BATS_FILE_TMPDIR, through the
# stub mail-toaster.sh on PATH. Only the tests that call a function with their
# own stubs pay to source the definitions.

setup_file() {
  load helper
  export STAGE_MNT="$BATS_FILE_TMPDIR/stage"
  mkdir -p "$STAGE_MNT"
  provision_run memcached
}

setup() {
  load helper
  provision_fns memcached
}

@test "memcached - install installs memcached package" {
  stage_pkg_install() { echo "PKG:$*"; }
  run install_memcached
  assert_success
  assert_output --partial "PKG:memcached"
}

@test "memcached - start enables the service and starts it" {
  stage_sysrc() { echo "SYSRC:$*"; }
  stage_exec()  { echo "EXEC:$*"; }
  run start_memcached
  assert_success
  assert_output --partial "SYSRC:memcached_enable=YES"
  assert_output --partial "EXEC:service memcached start"
}

@test "memcached - test checks port 11211" {
  stage_listening() { echo "PORT:$*"; }
  run test_memcached
  assert_success
  assert_output --partial "PORT:11211"
}
