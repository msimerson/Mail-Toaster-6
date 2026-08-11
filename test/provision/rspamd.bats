#!/usr/bin/env bats
# Functional tests for provision/rspamd.sh
#
# setup_file sources rspamd.sh once, executing install/configure/start/test
# against $BATS_FILE_TMPDIR. Tests read what that run produced; only the tests
# that call a function with its own stubs pay to source the definitions.

setup_file() {
  export MT6_TEST_ENV=1
  export STAGE_MNT="$BATS_FILE_TMPDIR/stage"
  export RSPAMD_ETC="$STAGE_MNT/usr/local/etc/rspamd"
  export RSPAMD_FNS="$BATS_FILE_TMPDIR/rspamd_fns_only.sh"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  local _script="$BATS_TEST_DIRNAME/../../provision/rspamd.sh"

  # everything from tell_settings on is the execution block
  awk '/^tell_settings/{exit} {print}' "$_script" > "$RSPAMD_FNS"

  mkdir -p "$RSPAMD_ETC" "$STAGE_MNT/etc"

  # shellcheck source=/dev/null
  . "$_script"
}

setup() {
  load '../test_helper/load'
}

load_rspamd_fns() {
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  # shellcheck source=/dev/null
  . "$RSPAMD_FNS"
}

@test "rspamd - declares no jail extras, RSPAMD_ETC lives under STAGE_MNT" {
  assert_equal "$JAIL_START_EXTRA" ""
  assert_equal "$JAIL_CONF_EXTRA" ""
  assert_equal "$JAIL_FSTAB" ""
  assert_equal "$RSPAMD_ETC" "$STAGE_MNT/usr/local/etc/rspamd"
}

@test "rspamd - defines the jail lifecycle functions" {
  load_rspamd_fns
  local _fn
  for _fn in install_rspamd configure_rspamd start_rspamd test_rspamd; do
    run type "$_fn"
    assert_success
  done
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
  load_rspamd_fns
  store_config() { cat - > /dev/null; }
  RSPAMD_SYSLOG=1 run configure_logging
  assert_success
}

@test "rspamd - install uses the rspamd package" {
  load_rspamd_fns
  stage_pkg_install() { echo "PKG:$*"; }
  run install_rspamd
  assert_success
  assert_output --partial "PKG:rspamd"
}

@test "rspamd - start enables the service and starts it" {
  load_rspamd_fns
  stage_sysrc() { echo "SYSRC:$*"; }
  stage_exec()  { echo "EXEC:$*"; }
  run start_rspamd
  assert_success
  assert_output --partial "SYSRC:rspamd_enable=YES"
  assert_output --partial "EXEC:service rspamd start"
}

@test "rspamd - test runs configtest and checks port 11334" {
  load_rspamd_fns
  stage_exec()      { echo "EXEC:$*"; }
  stage_listening() { echo "PORT:$*"; }
  run test_rspamd
  assert_success
  assert_output --partial "EXEC:/usr/local/bin/rspamadm configtest"
  assert_output --partial "PORT:11334"
}
