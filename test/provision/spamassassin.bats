#!/usr/bin/env bats
# Functional tests for provision/spamassassin.sh
#
# setup_file sources spamassassin.sh once, executing install and configure
# against $BATS_FILE_TMPDIR. Tests read what that run produced; only the tests
# that call a function with its own stubs pay to source the definitions.

setup_file() {
  load helper
  # configure_spamassassin derives target filenames from *.sample with
  # `cut -f1-2 -d.`, so no parent directory may contain a dot
  export STAGE_MNT="$BATS_FILE_TMPDIR/stage"

  export ZFS_DATA_MNT="$STAGE_MNT/data"
  export ZFS_JAIL_MNT="$STAGE_MNT/jails"
  export ZFS_DATA_VOL="zroot${ZFS_DATA_MNT}"
  export ZFS_JAIL_VOL="zroot${ZFS_JAIL_MNT}"

  # the MySQL sub-install wants a live DB
  export TOASTER_MYSQL=0

  mkdir -p "$STAGE_MNT/etc/razor" "$STAGE_MNT/usr/local/etc/mail" \
    "$STAGE_MNT/usr/local/etc/newsyslog.conf.d" "$ZFS_DATA_MNT/spamassassin/etc" \
    "$STAGE_MNT/usr/ports/mail/spamassassin"

  # install_spamassassin_razor aborts without it
  echo "logfile = razor-agent.log" > "$STAGE_MNT/etc/razor/razor-agent.conf"

  touch "$ZFS_DATA_MNT/spamassassin/etc/local.cf.sample"

  provision_run spamassassin
}

setup() {
  load helper
  SA_ETC="$ZFS_DATA_MNT/spamassassin/etc"
}

# --- JAIL variable exports ---

@test "spamassassin - declares no jail extras beyond the GeoIP mount" {
  assert_equal "$JAIL_START_EXTRA" ""
  assert_equal "$JAIL_CONF_EXTRA" ""
  assert_equal "$JAIL_FSTAB" \
    "$ZFS_DATA_MNT/geoip/db $ZFS_JAIL_MNT/spamassassin/usr/local/share/GeoIP nullfs rw 0 0"
}

@test "spamassassin - JAIL_FSTAB empty when geoip dataset absent" {
  zfs_filesystem_exists() { return 1; }
  JAIL_FSTAB="preset"
  eval "$(sed -n '/^export JAIL_FSTAB=""$/,/^fi$/p' "$PROVISION_DIR/spamassassin.sh")"
  assert_equal "$JAIL_FSTAB" ""
}

# --- install filesystem outcomes ---

@test "spamassassin - install creates the GeoIP and data directories" {
  [ -d "$STAGE_MNT/usr/local/share/GeoIP" ]
  [ -d "$ZFS_DATA_MNT/spamassassin/etc" ]
  [ -d "$ZFS_DATA_MNT/spamassassin/var" ]
}

@test "spamassassin - razor config gets logfile path set" {
  run grep "^logfile" "$STAGE_MNT/etc/razor/razor-agent.conf"
  assert_output --partial "/var/log/"
}

# --- configure_spamassassin filesystem outcomes ---

@test "spamassassin - configure writes local.pre with the plugins" {
  run cat "$SA_ETC/local.pre"
  assert_output --partial "Mail::SpamAssassin::Plugin::TextCat"
  assert_output --partial "Mail::SpamAssassin::Plugin::ASN"
  assert_output --partial "Mail::SpamAssassin::Plugin::DMARC"
}

@test "spamassassin - configure writes local.cf with the scanner settings" {
  run cat "$SA_ETC/local.cf"
  assert_output --partial "report_safe"
  assert_output --partial "use_razor2"
  assert_output --partial "use_dcc"
}

# --- configure_geoip / RelayCountry outcomes ---

@test "spamassassin - configure_geoip enables RelayCountry when geoip present" {
  run cat "$SA_ETC/relaycountry.pre"
  assert_success
  assert_output --partial "loadplugin Mail::SpamAssassin::Plugin::RelayCountry"
  assert_output --partial "country_db_type"
  assert_output --partial "/usr/local/share/GeoIP/GeoLite2-Country.mmdb"
}

@test "spamassassin - configure_geoip removes RelayCountry when geoip absent" {
  provision_fns spamassassin
  # configure_spamassassin leaves _sa_etc set for it; work on a private copy so
  # the file the previous test reads survives
  _sa_etc="$BATS_TEST_TMPDIR/etc"
  mkdir -p "$_sa_etc"
  echo "loadplugin Mail::SpamAssassin::Plugin::RelayCountry" > "$_sa_etc/relaycountry.pre"
  zfs_filesystem_exists() { return 1; }
  run configure_geoip
  assert_success
  [ ! -f "$_sa_etc/relaycountry.pre" ]
}

# --- install / start / test behaviour ---

@test "spamassassin - install uses p5-Mail-SPF package" {
  provision_fns spamassassin
  stage_pkg_install() { echo "PKG:$*"; }
  stage_exec()        { :; }
  run install_spamassassin
  assert_output --partial "PKG:p5-Mail-SPF"
}

@test "spamassassin - start enables spamd and starts sa-spamd" {
  provision_fns spamassassin
  stage_sysrc() { echo "SYSRC:$*"; }
  stage_exec()  { echo "EXEC:$*"; }
  run start_spamassassin
  assert_success
  assert_output --partial "SYSRC:spamd_enable=YES"
  assert_output --partial "EXEC:service sa-spamd start"
}

@test "spamassassin - test checks the perl process and port 783" {
  provision_fns spamassassin
  stage_test_running() { echo "RUNNING:$*"; }
  stage_listening()    { echo "PORT:$*"; }
  run test_spamassassin
  assert_success
  assert_output --partial "RUNNING:perl"
  assert_output --partial "PORT:783"
}
