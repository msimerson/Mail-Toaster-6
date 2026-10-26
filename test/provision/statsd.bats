#!/usr/bin/env bats
# Functional tests for provision/statsd.sh
#
# setup_file sources statsd.sh once against $BATS_FILE_TMPDIR, through the stub
# mail-toaster.sh on PATH.

setup_file() {
  load helper
  export STAGE_MNT="$BATS_FILE_TMPDIR/stage"

  # install_statsd edits config.js in place, so it has to exist first
  mkdir -p "$STAGE_MNT/var/lib" "$STAGE_MNT/usr/local/share/statsd/lib"
  printf ' process.EventEmitter = require("events").EventEmitter;\n' \
    > "$STAGE_MNT/usr/local/share/statsd/lib/config.js"

  provision_run statsd
}

setup() {
  load helper
  provision_fns statsd
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
