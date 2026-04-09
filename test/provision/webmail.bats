#!/usr/bin/env bats
# Functional tests for provision/webmail.sh
#
# Performance design (matches dns.bats pattern):
# - setup_file() runs ONCE: calls configure_nginx_server to generate webmail.conf
#   and saves a stripped function-only script for per-test use.
# - setup() runs per-test (fast): sources only the function definitions.

setup_file() {
  local _data="$BATS_FILE_TMPDIR/data"
  local _stage="$BATS_FILE_TMPDIR/stage"
  local _fns="$BATS_FILE_TMPDIR/webmail_fns_only.sh"

  # Strip execution block so setup() can source function definitions only.
  awk '/^base_snapshot_exists/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/webmail.sh" > "$_fns"

  export MT6_TEST_ENV=1
  export STAGE_MNT="$_stage"
  export ZFS_DATA_MNT="$_data"
  export TOASTER_HOSTNAME="mail.example.com"
  export TOASTER_WEBMAIL_PROXY="nginx"
  export TOASTER_NGINX_ACME=""
  export JAIL_NET_PREFIX="172.16.15"
  export JAIL_ORDERED_LIST="vpopmail haproxy webmail dns roundcube snappymail haraka rspamd"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  mkdir -p "$_data/webmail/etc/nginx" "$_stage"

  # shellcheck source=/dev/null
  . "$_fns"
  configure_nginx_server
}

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export ZFS_DATA_MNT="$BATS_FILE_TMPDIR/data"
  export WEBMAIL_CONF="$ZFS_DATA_MNT/webmail/etc/nginx/webmail.conf"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  # shellcheck source=/dev/null
  . "$BATS_FILE_TMPDIR/webmail_fns_only.sh"
}

# --- JAIL variable exports ---

@test "webmail - JAIL_START_EXTRA is empty" {
  assert_equal "$JAIL_START_EXTRA" ""
}

@test "webmail - JAIL_CONF_EXTRA is empty" {
  assert_equal "$JAIL_CONF_EXTRA" ""
}

@test "webmail - JAIL_FSTAB is empty" {
  assert_equal "$JAIL_FSTAB" ""
}

# --- webmail.conf security headers ---

@test "webmail.conf - X-XSS-Protection header is present" {
  run grep -q 'X-XSS-Protection' "$WEBMAIL_CONF"
  assert_success
}

@test "webmail.conf - X-XSS-Protection set to block mode" {
  run grep 'X-XSS-Protection' "$WEBMAIL_CONF"
  assert_output --partial '1; mode=block'
}

@test "webmail.conf - X-Content-Type-Options header is present" {
  run grep -q 'X-Content-Type-Options' "$WEBMAIL_CONF"
  assert_success
}

@test "webmail.conf - X-Content-Type-Options set to nosniff" {
  run grep 'X-Content-Type-Options' "$WEBMAIL_CONF"
  assert_output --partial 'nosniff'
}

@test "webmail.conf - X-Frame-Options header is present" {
  run grep -q 'X-Frame-Options' "$WEBMAIL_CONF"
  assert_success
}

@test "webmail.conf - X-Frame-Options set to SAMEORIGIN" {
  run grep 'X-Frame-Options' "$WEBMAIL_CONF"
  assert_output --partial 'SAMEORIGIN'
}

@test "webmail.conf - Referrer-Policy header is present" {
  run grep -q 'Referrer-Policy' "$WEBMAIL_CONF"
  assert_success
}

@test "webmail.conf - Referrer-Policy set to strict-origin-when-cross-origin" {
  run grep 'Referrer-Policy' "$WEBMAIL_CONF"
  assert_output --partial 'strict-origin-when-cross-origin'
}

@test "webmail.conf - Content-Security-Policy header is present" {
  run grep -q 'Content-Security-Policy' "$WEBMAIL_CONF"
  assert_success
}

@test "webmail.conf - CSP restricts default-src to self" {
  run grep 'Content-Security-Policy' "$WEBMAIL_CONF"
  assert_output --partial "default-src 'self'"
}

@test "webmail.conf - CSP restricts frame-ancestors to self" {
  run grep 'Content-Security-Policy' "$WEBMAIL_CONF"
  assert_output --partial "frame-ancestors 'self'"
}

@test "webmail.conf - security headers use always flag" {
  run grep -c 'always;' "$WEBMAIL_CONF"
  # All 5 add_header directives should have the always flag
  assert [ "$output" -ge 5 ]
}
