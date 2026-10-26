#!/usr/bin/env bats
# Functional tests for provision/rspamd.sh
#
# setup_file sources rspamd.sh once, executing install/configure/start/test
# against $BATS_FILE_TMPDIR. Tests read what that run produced; only the tests
# that call a function with its own stubs pay to source the definitions.

setup_file() {
  load helper
  export STAGE_MNT="$BATS_FILE_TMPDIR/stage"
  export RSPAMD_ETC="$STAGE_MNT/usr/local/etc/rspamd"
  mkdir -p "$RSPAMD_ETC" "$STAGE_MNT/etc"
  provision_run rspamd
}

setup() {
  load helper
}

@test "rspamd - declares no jail extras, RSPAMD_ETC lives under STAGE_MNT" {
  assert_equal "$JAIL_START_EXTRA" ""
  assert_equal "$JAIL_CONF_EXTRA" ""
  assert_equal "$JAIL_FSTAB" ""
  assert_equal "$RSPAMD_ETC" "$STAGE_MNT/usr/local/etc/rspamd"
}

@test "rspamd - configure creates the config directories" {
  [ -d "$RSPAMD_ETC/local.d" ]
  [ -d "$RSPAMD_ETC/override.d" ]
}

@test "rspamd - configure_enable writes enabled=true for each module" {
  local _mod
  for _mod in mxcheck url_reputation url_tags; do
    run cat "$RSPAMD_ETC/local.d/$_mod.conf"
    assert_output --partial "enabled = true;"
  done
}

@test "rspamd - configure_logging accepts RSPAMD_SYSLOG=1" {
  provision_fns rspamd tell_settings
  store_config() { cat - > /dev/null; }
  RSPAMD_SYSLOG=1 run configure_logging
  assert_success
}

@test "rspamd - install uses the rspamd package" {
  provision_fns rspamd tell_settings
  stage_pkg_install() { echo "PKG:$*"; }
  run install_rspamd
  assert_success
  assert_output --partial "PKG:rspamd"
}

@test "rspamd - start enables the service and starts it" {
  provision_fns rspamd tell_settings
  stage_sysrc() { echo "SYSRC:$*"; }
  stage_exec()  { echo "EXEC:$*"; }
  run start_rspamd
  assert_success
  assert_output --partial "SYSRC:rspamd_enable=YES"
  assert_output --partial "EXEC:service rspamd start"
}

@test "rspamd - test runs configtest and checks port 11334" {
  provision_fns rspamd tell_settings
  stage_exec()      { echo "EXEC:$*"; }
  stage_listening() { echo "PORT:$*"; }
  run test_rspamd
  assert_success
  assert_output --partial "EXEC:/usr/local/bin/rspamadm configtest"
  assert_output --partial "PORT:11334"
}
