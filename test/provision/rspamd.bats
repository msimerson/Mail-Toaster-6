#!/usr/bin/env bats
# Functional tests for provision/rspamd.sh

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export STAGE_MNT; STAGE_MNT=$(mktemp -d)
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  # Pre-create the rspamd config tree that configure_rspamd expects
  mkdir -p "$STAGE_MNT/usr/local/etc/rspamd"
  mkdir -p "$STAGE_MNT/etc"

  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../provision/rspamd.sh"
}

teardown() {
  rm -rf "$STAGE_MNT"
}

# --- JAIL variable exports ---

@test "rspamd - JAIL_START_EXTRA is empty" {
  assert_equal "$JAIL_START_EXTRA" ""
}

@test "rspamd - JAIL_CONF_EXTRA is empty" {
  assert_equal "$JAIL_CONF_EXTRA" ""
}

@test "rspamd - JAIL_FSTAB is empty" {
  assert_equal "$JAIL_FSTAB" ""
}

# --- RSPAMD_ETC points into STAGE_MNT ---

@test "rspamd - RSPAMD_ETC is under STAGE_MNT" {
  assert_equal "$RSPAMD_ETC" "$STAGE_MNT/usr/local/etc/rspamd"
}

# --- Function existence ---

@test "rspamd - defines install_rspamd" {
  run type install_rspamd
  assert_success
}

@test "rspamd - defines configure_rspamd" {
  run type configure_rspamd
  assert_success
}

@test "rspamd - defines start_rspamd" {
  run type start_rspamd
  assert_success
}

@test "rspamd - defines test_rspamd" {
  run type test_rspamd
  assert_success
}

# --- configure_rspamd filesystem outcomes ---

@test "rspamd - configure creates local.d directory" {
  [ -d "$RSPAMD_ETC/local.d" ]
}

@test "rspamd - configure creates override.d directory" {
  [ -d "$RSPAMD_ETC/override.d" ]
}

@test "rspamd - configure_enable writes enabled=true for mxcheck" {
  run cat "$RSPAMD_ETC/local.d/mxcheck.conf"
  assert_output --partial "enabled = true;"
}

@test "rspamd - configure_enable writes enabled=true for url_reputation" {
  run cat "$RSPAMD_ETC/local.d/url_reputation.conf"
  assert_output --partial "enabled = true;"
}

@test "rspamd - configure_enable writes enabled=true for url_tags" {
  run cat "$RSPAMD_ETC/local.d/url_tags.conf"
  assert_output --partial "enabled = true;"
}

# --- configure_logging ---

@test "rspamd - configure_logging writes syslog config when RSPAMD_SYSLOG=1" {
  _captured=""
  store_config() { _captured=$(cat -); }
  RSPAMD_SYSLOG=1 run configure_logging
  assert_success
}

# --- install_rspamd behaviour ---

@test "rspamd - install uses rspamd package" {
  stage_pkg_install() { echo "PKG:$*"; }
  run install_rspamd
  assert_success
  assert_output --partial "PKG:rspamd"
}

# --- start_rspamd behaviour ---

@test "rspamd - start enables rspamd service" {
  stage_sysrc() { echo "SYSRC:$*"; }
  stage_exec()  { :; }
  run start_rspamd
  assert_success
  assert_output --partial "SYSRC:rspamd_enable=YES"
}

@test "rspamd - start calls service rspamd start" {
  stage_sysrc() { :; }
  stage_exec()  { echo "EXEC:$*"; }
  run start_rspamd
  assert_success
  assert_output --partial "EXEC:service rspamd start"
}

# --- test_rspamd behaviour ---

@test "rspamd - test runs configtest" {
  stage_exec()      { echo "EXEC:$*"; }
  stage_listening() { :; }
  run test_rspamd
  assert_output --partial "EXEC:/usr/local/bin/rspamadm configtest"
}

@test "rspamd - test checks port 11334" {
  stage_exec()      { :; }
  stage_listening() { echo "PORT:$*"; }
  run test_rspamd
  assert_success
  assert_output --partial "PORT:11334"
}
