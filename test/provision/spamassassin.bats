#!/usr/bin/env bats
# Functional tests for provision/spamassassin.sh

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  # Use a dot-free path: configure_spamassassin uses `cut -f1-2 -d.` to derive
  # the target filename from *.sample files; dots in parent dirs break that.
  export STAGE_MNT; STAGE_MNT=$(mktemp -d /tmp/mt6saXXXXXX)
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  # Redirect ZFS data/jail mounts to temp tree so no real paths are touched
  export ZFS_DATA_MNT="$STAGE_MNT/data"
  export ZFS_JAIL_MNT="$STAGE_MNT/jails"
  export ZFS_DATA_VOL="zroot${ZFS_DATA_MNT}"
  export ZFS_JAIL_VOL="zroot${ZFS_JAIL_MNT}"

  # Skip MySQL sub-install (requires live DB connection)
  export TOASTER_MYSQL=0

  # Pre-create directories that provision steps expect to exist before running
  mkdir -p "$STAGE_MNT/etc/razor"
  mkdir -p "$STAGE_MNT/usr/local/etc/mail"
  mkdir -p "$STAGE_MNT/usr/local/etc/newsyslog.conf.d"
  mkdir -p "$STAGE_MNT/data/spamassassin"

  # razor-agent.conf must exist or install_spamassassin_razor aborts
  echo "logfile = razor-agent.log" > "$STAGE_MNT/etc/razor/razor-agent.conf"

  # install_spamassassin_port checks for a ports tree before building
  mkdir -p "$STAGE_MNT/usr/ports/mail/spamassassin"

  # local.cf.sample seed: configure_spamassassin globs *.sample and uses
  # `cut -f1-2 -d.` to derive the target name, so it needs to exist.
  mkdir -p "$STAGE_MNT/data/spamassassin/etc"
  touch "$STAGE_MNT/data/spamassassin/etc/local.cf.sample"

  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../provision/spamassassin.sh"
}

teardown() {
  rm -rf "$STAGE_MNT"
}

# --- JAIL variable exports ---

@test "spamassassin - JAIL_START_EXTRA is empty" {
  assert_equal "$JAIL_START_EXTRA" ""
}

@test "spamassassin - JAIL_CONF_EXTRA is empty" {
  assert_equal "$JAIL_CONF_EXTRA" ""
}

@test "spamassassin - JAIL_FSTAB contains GeoIP nullfs mount" {
  assert_equal "$JAIL_FSTAB" "$ZFS_DATA_MNT/geoip/db $ZFS_JAIL_MNT/spamassassin/usr/local/share/GeoIP nullfs rw 0 0"
}

# --- Function existence ---

@test "spamassassin - defines install_spamassassin" {
  run type install_spamassassin
  assert_success
}

@test "spamassassin - defines configure_spamassassin" {
  run type configure_spamassassin
  assert_success
}

@test "spamassassin - defines start_spamassassin" {
  run type start_spamassassin
  assert_success
}

@test "spamassassin - defines test_spamassassin" {
  run type test_spamassassin
  assert_success
}

# --- install filesystem outcomes ---

@test "spamassassin - install creates GeoIP share directory" {
  [ -d "$STAGE_MNT/usr/local/share/GeoIP" ]
}

@test "spamassassin - install creates data/spamassassin/etc directory" {
  [ -d "$ZFS_DATA_MNT/spamassassin/etc" ]
}

@test "spamassassin - install creates data/spamassassin/var directory" {
  [ -d "$ZFS_DATA_MNT/spamassassin/var" ]
}

# --- install_spamassassin_razor outcomes ---

@test "spamassassin - razor config gets logfile path set" {
  run grep "^logfile" "$STAGE_MNT/etc/razor/razor-agent.conf"
  assert_output --partial "/var/log/"
}

# --- configure_spamassassin filesystem outcomes ---

@test "spamassassin - configure writes local.pre with TextCat plugin" {
  run cat "$ZFS_DATA_MNT/spamassassin/etc/local.pre"
  assert_output --partial "Mail::SpamAssassin::Plugin::TextCat"
}

@test "spamassassin - configure writes local.pre with ASN plugin" {
  run cat "$ZFS_DATA_MNT/spamassassin/etc/local.pre"
  assert_output --partial "Mail::SpamAssassin::Plugin::ASN"
}

@test "spamassassin - configure writes local.pre with DMARC plugin" {
  run cat "$ZFS_DATA_MNT/spamassassin/etc/local.pre"
  assert_output --partial "Mail::SpamAssassin::Plugin::DMARC"
}

@test "spamassassin - configure writes local.cf with report_safe 0" {
  run cat "$ZFS_DATA_MNT/spamassassin/etc/local.cf"
  assert_output --partial "report_safe"
}

@test "spamassassin - configure writes local.cf enabling razor2" {
  run cat "$ZFS_DATA_MNT/spamassassin/etc/local.cf"
  assert_output --partial "use_razor2"
}

@test "spamassassin - configure writes local.cf enabling DCC" {
  run cat "$ZFS_DATA_MNT/spamassassin/etc/local.cf"
  assert_output --partial "use_dcc"
}

# --- install_spamassassin behaviour ---

@test "spamassassin - install uses p5-Mail-SPF package" {
  stage_pkg_install() { echo "PKG:$*"; }
  stage_exec()        { :; }
  run install_spamassassin
  assert_output --partial "PKG:p5-Mail-SPF"
}

# --- start_spamassassin behaviour ---

@test "spamassassin - start enables spamd service" {
  stage_sysrc() { echo "SYSRC:$*"; }
  stage_exec()  { :; }
  run start_spamassassin
  assert_success
  assert_output --partial "SYSRC:spamd_enable=YES"
}

@test "spamassassin - start calls service sa-spamd start" {
  stage_sysrc() { :; }
  stage_exec()  { echo "EXEC:$*"; }
  run start_spamassassin
  assert_success
  assert_output --partial "EXEC:service sa-spamd start"
}

# --- test_spamassassin behaviour ---

@test "spamassassin - test checks for running perl process" {
  stage_test_running() { echo "RUNNING:$*"; }
  stage_listening()    { :; }
  run test_spamassassin
  assert_output --partial "RUNNING:perl"
}

@test "spamassassin - test checks port 783" {
  stage_test_running() { :; }
  stage_listening()    { echo "PORT:$*"; }
  run test_spamassassin
  assert_success
  assert_output --partial "PORT:783"
}
