#!/usr/bin/env bats
# Functional tests for provision/statsd.sh
#
# setup_file sources statsd.sh once against $BATS_FILE_TMPDIR, through the stub
# mail-toaster.sh on PATH.

setup_file() {
  export MT6_TEST_ENV=1
  export STAGE_MNT="$BATS_FILE_TMPDIR/stage"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export STATSD_FNS="$BATS_FILE_TMPDIR/statsd_fns_only.sh"

  awk '/^base_snapshot_exists/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/statsd.sh" > "$STATSD_FNS"

  # install_statsd edits config.js in place, so it has to exist first
  mkdir -p "$STAGE_MNT/var/lib" "$STAGE_MNT/usr/local/share/statsd/lib"
  printf ' process.EventEmitter = require("events").EventEmitter;\n' \
    > "$STAGE_MNT/usr/local/share/statsd/lib/config.js"

  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../provision/statsd.sh"
}

setup() {
  load '../test_helper/load'
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  # shellcheck source=/dev/null
  . "$STATSD_FNS"
}

@test "statsd - declares no jail extras" {
  assert_equal "$JAIL_START_EXTRA" ""
  assert_equal "$JAIL_CONF_EXTRA" ""
  assert_equal "$JAIL_FSTAB" ""
}

@test "statsd - defines the jail lifecycle functions" {
  local _fn
  for _fn in install_statsd start_statsd test_statsd; do
    run type "$_fn"
    assert_success
  done
}

@test "statsd - install uses the statsd package and enables it" {
  stage_pkg_install() { echo "PKG:$*"; }
  stage_sysrc()       { echo "SYSRC:$*"; }
  run install_statsd
  assert_output --partial "PKG:statsd"
  assert_output --partial "SYSRC:statsd_enable=YES"
}

@test "statsd - start calls service statsd start" {
  stage_exec() { echo "EXEC:$*"; }
  run start_statsd
  assert_success
  assert_output --partial "EXEC:service statsd start"
}

@test "statsd - test checks statsd is running" {
  stage_test_running() { echo "RUNNING:$*"; }
  run test_statsd
  assert_success
  assert_output --partial "RUNNING:statsd"
}
