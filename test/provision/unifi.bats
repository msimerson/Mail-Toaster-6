#!/usr/bin/env bats
# Functional tests for provision/unifi.sh
#
# store_unifi_mongodb_dsn mints a credential and writes it to conf.d/, so every
# test runs with MT6_CONF_DIR pointed at a tmpdir.

setup_file() {
  export UNIFI_FNS="$BATS_FILE_TMPDIR/unifi_fns_only.sh"
  awk '/^store_unifi_mongodb_dsn$/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/unifi.sh" > "$UNIFI_FNS"
}

setup() {
  load '../test_helper/load'

  export MT6_TEST_ENV=1
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  export ZFS_JAIL_MNT="$BATS_TEST_TMPDIR/jails"
  export MT6_CONF_DIR="$BATS_TEST_TMPDIR/conf.d"

  # shellcheck source=/dev/null
  . "$UNIFI_FNS"
}

@test "unifi - defines store_unifi_mongodb_dsn" {
  run type store_unifi_mongodb_dsn
  assert_success
}

@test "unifi - no DSN is minted without a mongodb jail" {
  export UNIFI_MONGODB_DSN=""
  jail_is_running() { return 1; }
  store_unifi_mongodb_dsn
  assert_equal "$UNIFI_MONGODB_DSN" ""
  run test -e "$MT6_CONF_DIR/unifi.conf"
  assert_failure
}

@test "unifi - a DSN is minted and persisted when mongodb is running" {
  export UNIFI_MONGODB_DSN=""
  jail_is_running() { [ "$1" = "mongodb" ]; }
  store_unifi_mongodb_dsn
  [ -n "$UNIFI_MONGODB_DSN" ]
  run grep "^export UNIFI_MONGODB_DSN=" "$MT6_CONF_DIR/unifi.conf"
  assert_success
  assert_output --partial "mongodb://ubnt:"
  assert_output --partial "@mongodb:27017/unifi"
}

# Regenerating per run would rewrite system.properties with a password that
# mongo was never told about.
@test "unifi - a configured DSN is never regenerated" {
  export UNIFI_MONGODB_DSN="mongodb://ubnt:original@mongodb:27017/unifi"
  jail_is_running() { [ "$1" = "mongodb" ]; }
  store_unifi_mongodb_dsn
  assert_equal "$UNIFI_MONGODB_DSN" "mongodb://ubnt:original@mongodb:27017/unifi"
  run test -e "$MT6_CONF_DIR/unifi.conf"
  assert_failure
}

@test "unifi - a minted DSN is stable across runs" {
  export UNIFI_MONGODB_DSN=""
  jail_is_running() { [ "$1" = "mongodb" ]; }
  # a fresh value per call, so regenerating would visibly change the DSN
  get_random_pass() { echo "pw-$RANDOM$RANDOM"; }
  store_unifi_mongodb_dsn
  local _first="$UNIFI_MONGODB_DSN"

  # second provision run: conf.d/unifi.conf is sourced back in
  unset UNIFI_MONGODB_DSN
  # shellcheck source=/dev/null
  . "$MT6_CONF_DIR/unifi.conf"
  store_unifi_mongodb_dsn

  assert_equal "$UNIFI_MONGODB_DSN" "$_first"
  local _count; _count=$(grep -c UNIFI_MONGODB_DSN "$MT6_CONF_DIR/unifi.conf")
  assert_equal "$_count" "1"
}

@test "unifi - the persisted credential is not world readable" {
  export UNIFI_MONGODB_DSN=""
  jail_is_running() { [ "$1" = "mongodb" ]; }
  store_unifi_mongodb_dsn
  run _file_mode "$MT6_CONF_DIR/unifi.conf"
  assert_output "600"
}
