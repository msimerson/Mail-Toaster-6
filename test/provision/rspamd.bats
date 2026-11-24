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

# --- the admin's tuning survives a reprovision ---

@test "rspamd - preserve_rspamd_config carries local.d, override.d and maps.d and the local files" {
  provision_fns rspamd tell_settings
  preserve_config_dir() { echo "DIR:$1:$2"; }
  preserve_file() { echo "FILE:$1:$2"; }

  run preserve_rspamd_config
  assert_success
  assert_output --partial "DIR:rspamd:/usr/local/etc/rspamd/local.d"
  assert_output --partial "DIR:rspamd:/usr/local/etc/rspamd/override.d"
  assert_output --partial "DIR:rspamd:/usr/local/etc/rspamd/maps.d"
  assert_output --partial "FILE:rspamd:/usr/local/etc/rspamd/rspamd.conf.local"
  assert_output --partial "FILE:rspamd:/usr/local/etc/rspamd/rspamd.local.lua"
}

@test "rspamd - configure_rspamd preserves before it writes any default" {
  provision_fns rspamd tell_settings
  local _order="$BATS_TEST_TMPDIR/order"; : > "$_order"
  preserve_rspamd_config() { echo preserve >> "$_order"; }
  configure_logging() { echo write >> "$_order"; }
  configure_redis() { :; }; configure_dmarc() { :; }; configure_stats() { :; }
  configure_dcc() { :; }; configure_enable() { :; }; configure_phishing() { :; }
  configure_rbl() { :; }; configure_virus_total() { :; }; configure_metadefender() { :; }
  configure_worker() { :; }; configure_controller() { :; }
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage-order"
  RSPAMD_ETC="$STAGE_MNT/usr/local/etc/rspamd"
  mkdir -p "$RSPAMD_ETC"

  run configure_rspamd
  assert_success
  run cat "$_order"
  assert_line --index 0 "preserve"
  assert_line --index 1 "write"
}

# a running jail as an admin left it, a stage as the package made it, and the
# real util.sh, not the stubs, so preserve and store_config do their work
_rspamd_live() {
  provision_fns rspamd tell_settings
  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../include/util.sh"
  export ZFS_JAIL_MNT="$BATS_TEST_TMPDIR/jails"
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage-live"
  RSPAMD_ETC="$STAGE_MNT/usr/local/etc/rspamd"
  _live="$ZFS_JAIL_MNT/rspamd/usr/local/etc/rspamd"
  mkdir -p "$_live/local.d" "$_live/override.d" "$_live/maps.d" "$RSPAMD_ETC"
  _mt6_wrote() { printf '%s\n' "$2" > "$1"; printf '%s\n' "$2" > "$1.mt6"; }
}

@test "rspamd - a reprovision keeps the admin's files and edits, and regenerates the defaults" {
  _rspamd_live
  echo "actions { reject = 20; }" > "$_live/local.d/actions.conf"
  echo "map = 1;" > "$_live/maps.d/allow.map"
  echo "-- mine" > "$_live/rspamd.local.lua"
  _mt6_wrote "$_live/local.d/worker-controller.inc" "password = \"old\";"
  echo "password = \"tuned\";" > "$_live/local.d/worker-controller.inc"
  _mt6_wrote "$_live/local.d/mxcheck.conf" "enabled = true;"

  preserve_rspamd_config
  configure_enable mxcheck
  configure_enable url_tags

  run cat "$RSPAMD_ETC/local.d/actions.conf"
  assert_output "actions { reject = 20; }"
  run cat "$RSPAMD_ETC/maps.d/allow.map"
  assert_output "map = 1;"
  run cat "$RSPAMD_ETC/rspamd.local.lua"
  assert_output "-- mine"
  run cat "$RSPAMD_ETC/local.d/worker-controller.inc"
  assert_output 'password = "tuned";'
  run cat "$RSPAMD_ETC/local.d/mxcheck.conf"
  assert_output "enabled = true;"
}

@test "rspamd - configure_enable keeps an edited file, and records what it would have written" {
  _rspamd_live
  mkdir -p "$RSPAMD_ETC/local.d"
  echo "enabled = true; # tuned" > "$RSPAMD_ETC/local.d/url_tags.conf"

  configure_enable url_tags

  run cat "$RSPAMD_ETC/local.d/url_tags.conf"
  assert_output "enabled = true; # tuned"
  run cat "$RSPAMD_ETC/local.d/url_tags.conf.mt6"
  assert_output "enabled = true;"
}

@test "rspamd - configure_dmarc does not append to dmarc.conf on every run" {
  _rspamd_live
  export TOASTER_MTA="haraka" TOASTER_ORG_NAME="Org" TOASTER_MAIL_DOMAIN="example.com" \
    TOASTER_ADMIN_EMAIL="postmaster@example.com"
  get_jail_ip4() { echo "172.16.15.9"; }
  zfs_filesystem_exists() { return 0; }
  mkdir -p "$RSPAMD_ETC/local.d"

  configure_dmarc
  configure_dmarc

  run grep -c "send_reports" "$RSPAMD_ETC/local.d/dmarc.conf"
  assert_output "1"
}

@test "rspamd - configure_dmarc keeps an edited dmarc.conf" {
  _rspamd_live
  export TOASTER_MTA="haraka" TOASTER_ORG_NAME="Org" TOASTER_MAIL_DOMAIN="example.com" \
    TOASTER_ADMIN_EMAIL="postmaster@example.com"
  get_jail_ip4() { echo "172.16.15.9"; }
  zfs_filesystem_exists() { return 0; }
  mkdir -p "$RSPAMD_ETC/local.d"
  echo "send_reports = false;" > "$RSPAMD_ETC/local.d/dmarc.conf"

  configure_dmarc

  run cat "$RSPAMD_ETC/local.d/dmarc.conf"
  assert_output "send_reports = false;"
}
