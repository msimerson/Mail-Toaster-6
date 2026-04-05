#!/usr/bin/env bats
# Functional tests for provision/clamav.sh

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export STAGE_MNT; STAGE_MNT=$(mktemp -d)
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  # Disable optional sub-installers that require network/interactive access
  export CLAMAV_UNOFFICIAL=0
  export CLAMAV_FANGFRISCH=0

  # Pre-create filesystem layout expected by install_clamav and configure_*
  mkdir -p "$STAGE_MNT/data/etc"
  mkdir -p "$STAGE_MNT/usr/local/etc/rc.d"

  # clamd.conf template (representative commented options)
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

  # freshclam.conf template
  cat > "$STAGE_MNT/usr/local/etc/freshclam.conf" <<'EOF'
DatabaseDirectory /var/db/clamav
UpdateLogFile /var/log/clamav/freshclam.log
#LogSyslog
#LogFacility LOG_LOCAL6
#SafeBrowsing yes
#DatabaseMirror XY
EOF

  # rc.d stubs with paths that configure_* will rewrite
  echo "conf=/usr/local/etc/clamd.conf; db=/var/db/clamav" \
    > "$STAGE_MNT/usr/local/etc/rc.d/clamav_clamd"
  echo "conf=/usr/local/etc/freshclam.conf; db=/var/db/clamav" \
    > "$STAGE_MNT/usr/local/etc/rc.d/clamav_freshclam"

  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../provision/clamav.sh"
}

teardown() {
  rm -rf "$STAGE_MNT"
}

# --- JAIL variable exports ---

@test "clamav - JAIL_START_EXTRA is empty" {
  assert_equal "$JAIL_START_EXTRA" ""
}

@test "clamav - JAIL_CONF_EXTRA is empty" {
  assert_equal "$JAIL_CONF_EXTRA" ""
}

@test "clamav - JAIL_FSTAB is empty" {
  assert_equal "$JAIL_FSTAB" ""
}

# --- Function existence ---

@test "clamav - defines install_clamav" {
  run type install_clamav
  assert_success
}

@test "clamav - defines configure_clamav" {
  run type configure_clamav
  assert_success
}

@test "clamav - defines start_clamav" {
  run type start_clamav
  assert_success
}

@test "clamav - defines test_clamav" {
  run type test_clamav
  assert_success
}

# --- install_clamav behaviour ---

@test "clamav - install uses clamav package" {
  stage_pkg_install() { echo "PKG:$*"; }
  run install_clamav
  assert_output --partial "PKG:clamav"
}

@test "clamav - install creates data subdirectories" {
  [ -d "$STAGE_MNT/data/etc" ]
  [ -d "$STAGE_MNT/data/db" ]
  [ -d "$STAGE_MNT/data/log" ]
}

# --- configure_clamd outcomes ---

@test "clamav - configure_clamd enables TCPSocket" {
  run grep "^TCPSocket" "$STAGE_MNT/data/etc/clamd.conf"
  assert_success
}

@test "clamav - configure_clamd enables LogFacility" {
  run grep "^LogFacility" "$STAGE_MNT/data/etc/clamd.conf"
  assert_success
}

@test "clamav - configure_clamd enables syslog" {
  run grep "^LogSyslog yes" "$STAGE_MNT/data/etc/clamd.conf"
  assert_success
}

@test "clamav - configure_clamd redirects LogFile to /data/log" {
  run grep "^LogFile" "$STAGE_MNT/data/etc/clamd.conf"
  assert_output --partial "/data/log"
}

@test "clamav - configure_clamd sets DatabaseDirectory to /data/db" {
  run grep "^DatabaseDirectory" "$STAGE_MNT/data/etc/clamd.conf"
  assert_output --partial "/data/db"
}

@test "clamav - configure_clamd enables DetectPUA" {
  run grep "^DetectPUA" "$STAGE_MNT/data/etc/clamd.conf"
  assert_success
}

@test "clamav - configure_clamd enables OLE2BlockMacros" {
  run grep "^OLE2BlockMacros yes" "$STAGE_MNT/data/etc/clamd.conf"
  assert_success
}

@test "clamav - configure_clamd enables ArchiveBlockEncrypted" {
  run grep "^ArchiveBlockEncrypted yes" "$STAGE_MNT/data/etc/clamd.conf"
  assert_success
}

@test "clamav - configure_clamd rewrites rc.d conf path" {
  run grep "data/etc" "$STAGE_MNT/usr/local/etc/rc.d/clamav_clamd"
  assert_success
  run grep "usr/local/etc" "$STAGE_MNT/usr/local/etc/rc.d/clamav_clamd"
  assert_failure
}

@test "clamav - configure_clamd rewrites rc.d db path" {
  run grep "data/db" "$STAGE_MNT/usr/local/etc/rc.d/clamav_clamd"
  assert_success
  run grep "var/db/clamav" "$STAGE_MNT/usr/local/etc/rc.d/clamav_clamd"
  assert_failure
}

# --- configure_freshclam outcomes ---

@test "clamav - configure_freshclam sets DatabaseDirectory to /data/db" {
  run grep "^DatabaseDirectory" "$STAGE_MNT/data/etc/freshclam.conf"
  assert_output --partial "/data/db"
}

@test "clamav - configure_freshclam redirects UpdateLogFile to /data/log" {
  run grep "^UpdateLogFile" "$STAGE_MNT/data/etc/freshclam.conf"
  assert_output --partial "/data/log"
}

@test "clamav - configure_freshclam enables LogSyslog" {
  run grep "^LogSyslog" "$STAGE_MNT/data/etc/freshclam.conf"
  assert_success
}

@test "clamav - configure_freshclam enables DatabaseMirror with us region" {
  run grep "^DatabaseMirror" "$STAGE_MNT/data/etc/freshclam.conf"
  assert_output --partial "us"
}

@test "clamav - configure_freshclam rewrites rc.d conf path" {
  run grep "data/etc" "$STAGE_MNT/usr/local/etc/rc.d/clamav_freshclam"
  assert_success
  run grep "usr/local/etc" "$STAGE_MNT/usr/local/etc/rc.d/clamav_freshclam"
  assert_failure
}

@test "clamav - configure_freshclam rewrites rc.d db path" {
  run grep "data/db" "$STAGE_MNT/usr/local/etc/rc.d/clamav_freshclam"
  assert_success
  run grep "var/db/clamav" "$STAGE_MNT/usr/local/etc/rc.d/clamav_freshclam"
  assert_failure
}

# --- start_clamav behaviour ---

@test "clamav - start enables clamav_clamd service" {
  stage_sysrc() { echo "SYSRC:$*"; }
  stage_exec()  { :; }
  run start_clamav
  assert_output --partial "SYSRC:clamav_clamd_enable=YES"
}

@test "clamav - start enables clamav_freshclam service" {
  stage_sysrc() { echo "SYSRC:$*"; }
  stage_exec()  { :; }
  run start_clamav
  assert_output --partial "SYSRC:clamav_freshclam_enable=YES"
}

@test "clamav - start calls service clamav_clamd start" {
  stage_sysrc() { :; }
  stage_exec()  { echo "EXEC:$*"; }
  run start_clamav
  assert_output --partial "EXEC:service clamav_clamd start"
}

@test "clamav - start calls service clamav_freshclam start" {
  stage_sysrc() { :; }
  stage_exec()  { echo "EXEC:$*"; }
  run start_clamav
  assert_output --partial "EXEC:service clamav_freshclam start"
}

# --- test_clamav behaviour ---

@test "clamav - test checks port 3310" {
  stage_listening() { echo "PORT:$*"; }
  run test_clamav
  assert_success
  assert_output --partial "PORT:3310"
}
