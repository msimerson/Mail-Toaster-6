#!/usr/bin/env bats
# Functional tests for provision/clamav.sh
#
# setup_file sources clamav.sh once, executing install and configure against
# $BATS_FILE_TMPDIR. Tests read what that run produced; only the tests that
# call a function with its own stubs pay to source the definitions.

setup_file() {
  load helper
  export STAGE_MNT="$BATS_FILE_TMPDIR/stage"

  # the optional sub-installers want network and an interactive terminal
  export CLAMAV_UNOFFICIAL=0
  export CLAMAV_FANGFRISCH=0

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

  provision_run clamav
}

setup() {
  load helper
  CLAMD_CONF="$STAGE_MNT/data/etc/clamd.conf"
  FRESHCLAM_CONF="$STAGE_MNT/data/etc/freshclam.conf"
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

# --- install_clamav ---

@test "clamav - install uses clamav package" {
  provision_fns clamav
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
  provision_fns clamav
  stage_sysrc() { echo "SYSRC:$*"; }
  stage_exec()  { echo "EXEC:$*"; }
  run start_clamav
  assert_output --partial "SYSRC:clamav_clamd_enable=YES"
  assert_output --partial "SYSRC:clamav_freshclam_enable=YES"
  assert_output --partial "EXEC:service clamav_clamd start"
  assert_output --partial "EXEC:service clamav_freshclam start"
}

@test "clamav - test checks port 3310" {
  provision_fns clamav
  stage_listening() { echo "PORT:$*"; }
  run test_clamav
  assert_success
  assert_output --partial "PORT:3310"
}

# --- optional signature installers ---

@test "clamav - unofficial installs gsed and writes signatures to /data/db" {
  provision_fns clamav
  export CLAMAV_UNOFFICIAL=1
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  local _dist="$STAGE_MNT/tmp/clamav-unofficial-sigs-7.2.5"
  mkdir -p "$_dist/config/os" "$STAGE_MNT/usr/local/bin"
  echo 'clam_dbs="/var/db/clamav"' > "$_dist/config/os/os.freebsd.conf"
  echo '#user_configuration_complete="yes"' > "$_dist/config/user.conf"
  echo '#!/bin/bash' > "$_dist/clamav-unofficial-sigs.sh"
  fetch() { :; }
  tar() { :; }
  stage_pkg_install() { echo "PKG:$*"; }

  run install_clamav_unofficial
  assert_success
  assert_output --regexp "PKG:.* gsed"
  run grep '^clam_dbs=' "$STAGE_MNT/etc/clamav-unofficial-sigs/os.conf"
  assert_output 'clam_dbs="/data/db"'
}

@test "clamav - fangfrisch installs sqlite3 for the default python, into /data/db" {
  provision_fns clamav
  export CLAMAV_FANGFRISCH=1
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  mkdir -p "$STAGE_MNT/etc"
  # the real stage_exec echoes its command, which must not reach pkg
  stage_exec() { echo "jexec stage $*"; }
  jexec() { [ "$2" = "python3" ] && echo "py311"; return 0; }
  stage_pkg_install() { echo "PKG:$*"; }
  store_config() { mkdir -p "$(dirname "$1")"; cat - > "$1"; }

  run install_clamav_fangfrisch
  assert_success
  assert_line "PKG:py311-sqlite3"
  refute_output --partial "py39"
  assert_output --partial "fangfrisch.conf initdb"
  run grep '^local_directory' "$STAGE_MNT/data/etc/fangfrisch.conf"
  assert_output "local_directory = /data/db"
  run grep '^\*/10.*clamav.*fangfrisch --conf /data/etc/fangfrisch.conf refresh' "$STAGE_MNT/etc/crontab"
  assert_success
}

# the providers that need an account stay off until one is configured
@test "clamav - fangfrisch enables only the providers that need no account" {
  provision_fns clamav
  export CLAMAV_FANGFRISCH=1
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  mkdir -p "$STAGE_MNT/etc"
  stage_exec() { :; }
  jexec() { echo "py311"; }
  stage_pkg_install() { :; }
  store_config() { mkdir -p "$(dirname "$1")"; cat - > "$1"; }

  install_clamav_fangfrisch
  local _conf="$STAGE_MNT/data/etc/fangfrisch.conf"
  run awk '/^\[/ { s = $0 } /^enabled = yes/ { print s }' "$_conf"
  assert_output "[sanesecurity]"
}

# initdb fails on a db that already has its tables
@test "clamav - fangfrisch skips initdb when the db exists" {
  provision_fns clamav
  export CLAMAV_FANGFRISCH=1
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  mkdir -p "$STAGE_MNT/etc" "$STAGE_MNT/data/db"
  touch "$STAGE_MNT/data/db/fangfrisch.sqlite"
  stage_exec() { echo "EXEC:$*"; }
  jexec() { echo "py311"; }
  stage_pkg_install() { :; }
  store_config() { mkdir -p "$(dirname "$1")"; cat - > "$1"; }

  run install_clamav_fangfrisch
  assert_success
  refute_output --partial "initdb"
  assert_output --partial "fangfrisch.conf refresh"
}
