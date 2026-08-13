#!/usr/bin/env bats
# Functional tests for provision/clamav.sh
#
# setup_file sources clamav.sh once, executing install and configure against
# $BATS_FILE_TMPDIR. Tests read what that run produced; only the tests that
# call a function with its own stubs pay to source the definitions.

setup_file() {
  export MT6_TEST_ENV=1
  export STAGE_MNT="$BATS_FILE_TMPDIR/stage"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  # the optional sub-installers want network and an interactive terminal
  export CLAMAV_UNOFFICIAL=0
  export CLAMAV_FANGFRISCH=0

  export CLAMAV_FNS="$BATS_FILE_TMPDIR/clamav_fns_only.sh"
  awk '/^base_snapshot_exists/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/clamav.sh" > "$CLAMAV_FNS"

  mkdir -p "$STAGE_MNT/data/etc" "$STAGE_MNT/usr/local/etc/rc.d"

  cat > "$STAGE_MNT/usr/local/etc/clamd.conf" <<'EOF'
#TCPSocket 3310
#LogFacility LOG_LOCAL6
#LogSyslog no
LogFile /var/log/clamav/clamd.log
#DetectPUA
DatabaseDirectory /var/db/clamav
#ExtendedDetectionInfo
#DetectBrokenExecutables
#StructuredDataDetection
#ArchiveBlockEncrypted no
#OLE2BlockMacros no
#PhishingSignatures yes
#PhishingScanURLs
#HeuristicScanPrecedence yes
#StructuredDataDetection
#StructuredMinCreditCardCount 5
#StructuredMinSSNCount 5
#StructuredSSNFormatStripped yes
#ScanArchive yes
EOF

  cat > "$STAGE_MNT/usr/local/etc/freshclam.conf" <<'EOF'
DatabaseDirectory /var/db/clamav
UpdateLogFile /var/log/clamav/freshclam.log
#LogSyslog
#LogFacility LOG_LOCAL6
#SafeBrowsing yes
#DatabaseMirror XY
EOF

  # rc.d stubs with the paths configure_* rewrites
  echo "conf=/usr/local/etc/clamd.conf; db=/var/db/clamav" \
    > "$STAGE_MNT/usr/local/etc/rc.d/clamav_clamd"
  echo "conf=/usr/local/etc/freshclam.conf; db=/var/db/clamav" \
    > "$STAGE_MNT/usr/local/etc/rc.d/clamav_freshclam"

  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../provision/clamav.sh"
}

setup() {
  load '../test_helper/load'
  CLAMD_CONF="$STAGE_MNT/data/etc/clamd.conf"
  FRESHCLAM_CONF="$STAGE_MNT/data/etc/freshclam.conf"
}

load_clamav_fns() {
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  # shellcheck source=/dev/null
  . "$CLAMAV_FNS"
}

# a setting is enabled when it appears uncommented, with the wanted value
assert_conf_enabled() {
  local _conf="$1"; shift
  local _setting
  for _setting in "$@"; do
    run grep "^$_setting" "$_conf"
    assert_success
  done
}

@test "clamav - declares no jail extras" {
  assert_equal "$JAIL_START_EXTRA" ""
  assert_equal "$JAIL_CONF_EXTRA" ""
  assert_equal "$JAIL_FSTAB" ""
}

@test "clamav - defines the jail lifecycle functions" {
  load_clamav_fns
  local _fn
  for _fn in install_clamav configure_clamav start_clamav test_clamav; do
    run type "$_fn"
    assert_success
  done
}

# --- install_clamav ---

@test "clamav - install uses clamav package" {
  load_clamav_fns
  stage_pkg_install() { echo "PKG:$*"; }
  run install_clamav
  assert_output --partial "PKG:clamav"
}

@test "clamav - install creates data subdirectories" {
  [ -d "$STAGE_MNT/data/etc" ]
  [ -d "$STAGE_MNT/data/db" ]
  [ -d "$STAGE_MNT/data/log" ]
}

# --- configure_clamd ---

@test "clamav - configure_clamd enables the scanner options" {
  assert_conf_enabled "$CLAMD_CONF" TCPSocket LogFacility "LogSyslog yes" \
    DetectPUA "OLE2BlockMacros yes" "ArchiveBlockEncrypted yes"
}

@test "clamav - configure_clamd points the log and database at /data" {
  run grep "^LogFile" "$CLAMD_CONF"
  assert_output --partial "/data/log"
  run grep "^DatabaseDirectory" "$CLAMD_CONF"
  assert_output --partial "/data/db"
}

# --- configure_freshclam ---

@test "clamav - configure_freshclam enables syslog and a us mirror" {
  assert_conf_enabled "$FRESHCLAM_CONF" LogSyslog
  run grep "^DatabaseMirror" "$FRESHCLAM_CONF"
  assert_output --partial "us"
}

@test "clamav - configure_freshclam points the log and database at /data" {
  run grep "^DatabaseDirectory" "$FRESHCLAM_CONF"
  assert_output --partial "/data/db"
  run grep "^UpdateLogFile" "$FRESHCLAM_CONF"
  assert_output --partial "/data/log"
}

# --- rc.d scripts read the configs and database under /data ---

@test "clamav - configure rewrites the rc.d conf and db paths" {
  local _rc
  for _rc in clamav_clamd clamav_freshclam; do
    run grep "data/etc" "$STAGE_MNT/usr/local/etc/rc.d/$_rc"
    assert_success
    run grep "usr/local/etc" "$STAGE_MNT/usr/local/etc/rc.d/$_rc"
    assert_failure

    run grep "data/db" "$STAGE_MNT/usr/local/etc/rc.d/$_rc"
    assert_success
    run grep "var/db/clamav" "$STAGE_MNT/usr/local/etc/rc.d/$_rc"
    assert_failure
  done
}

# --- start / test behaviour ---

@test "clamav - start enables and starts both services" {
  load_clamav_fns
  stage_sysrc() { echo "SYSRC:$*"; }
  stage_exec()  { echo "EXEC:$*"; }
  run start_clamav
  assert_output --partial "SYSRC:clamav_clamd_enable=YES"
  assert_output --partial "SYSRC:clamav_freshclam_enable=YES"
  assert_output --partial "EXEC:service clamav_clamd start"
  assert_output --partial "EXEC:service clamav_freshclam start"
}

@test "clamav - test checks port 3310" {
  load_clamav_fns
  stage_listening() { echo "PORT:$*"; }
  run test_clamav
  assert_success
  assert_output --partial "PORT:3310"
}
