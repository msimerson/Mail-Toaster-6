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
  configure_rbl() { :; }; configure_antivirus() { :; }
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

# the real util.sh: the stubs do not preserve
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

@test "rspamd - configure_dmarc writes dmarc.conf once across reprovisions" {
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

# the stage becomes the live jail, and a new stage is built from it
_reprovision() {
  rm -rf "${ZFS_JAIL_MNT:?}/rspamd"
  mkdir -p "$ZFS_JAIL_MNT/rspamd"
  cp -Rp "$STAGE_MNT/usr" "$ZFS_JAIL_MNT/rspamd/"
  rm -rf "$STAGE_MNT/usr"
  mkdir -p "$RSPAMD_ETC/local.d"
  preserve_rspamd_config
}

@test "rspamd - configure_antivirus writes each scanner once across reprovisions" {
  _rspamd_live
  export VIRUSTOTAL_API_KEY="vt-key" METADEFENDER_API_KEY="md-key"
  mkdir -p "$RSPAMD_ETC/local.d"

  local _i
  for _i in 1 2 3; do
    configure_antivirus
    _reprovision
  done
  configure_antivirus

  run grep -c "^virustotal {" "$RSPAMD_ETC/local.d/antivirus.conf"
  assert_output "1"
  run grep -c "^metadefender {" "$RSPAMD_ETC/local.d/antivirus.conf"
  assert_output "1"
}

@test "rspamd - configure_antivirus keeps an edited antivirus.conf, once" {
  _rspamd_live
  export VIRUSTOTAL_API_KEY="vt-key" METADEFENDER_API_KEY=""
  mkdir -p "$RSPAMD_ETC/local.d"

  configure_antivirus
  echo "# tuned" >> "$RSPAMD_ETC/local.d/antivirus.conf"
  _reprovision
  configure_antivirus
  _reprovision
  configure_antivirus

  run grep -c "^virustotal {" "$RSPAMD_ETC/local.d/antivirus.conf"
  assert_output "1"
  run grep -c "# tuned" "$RSPAMD_ETC/local.d/antivirus.conf"
  assert_output "1"
}

@test "rspamd - configure_antivirus writes nothing without a key" {
  _rspamd_live
  export VIRUSTOTAL_API_KEY="" METADEFENDER_API_KEY=""
  mkdir -p "$RSPAMD_ETC/local.d"

  configure_antivirus

  [ ! -e "$RSPAMD_ETC/local.d/antivirus.conf" ]
}
