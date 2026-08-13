#!/usr/bin/env bats
# Functional tests for provision/memcached.sh
#
# setup_file sources memcached.sh once against $BATS_FILE_TMPDIR, through the
# stub mail-toaster.sh on PATH. Only the tests that call a function with their
# own stubs pay to source the definitions.

setup_file() {
  export MT6_TEST_ENV=1
  export STAGE_MNT="$BATS_FILE_TMPDIR/stage"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export MEMCACHED_FNS="$BATS_FILE_TMPDIR/memcached_fns_only.sh"

  awk '/^base_snapshot_exists/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/memcached.sh" > "$MEMCACHED_FNS"

  mkdir -p "$STAGE_MNT"

  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../provision/memcached.sh"
}

setup() {
  load '../test_helper/load'
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  # shellcheck source=/dev/null
  . "$MEMCACHED_FNS"
}

@test "memcached - declares no jail extras" {
  assert_equal "$JAIL_START_EXTRA" ""
  assert_equal "$JAIL_CONF_EXTRA" ""
  assert_equal "$JAIL_FSTAB" ""
}

@test "memcached - defines the jail lifecycle functions" {
  local _fn
  for _fn in install_memcached start_memcached test_memcached; do
    run type "$_fn"
    assert_success
  done
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
