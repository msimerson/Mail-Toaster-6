#!/usr/bin/env bats
# Functional tests for provision/haproxy.sh
#
# Performance design (matches dns.bats pattern):
# - setup_file() runs ONCE: overrides store_config so it writes to disk,
#   then calls configure_haproxy_dot_conf to generate haproxy.conf.
# - setup() runs per-test (fast): sources only the function definitions.

setup_file() {
  local _data="$BATS_FILE_TMPDIR/data"
  local _stage="$BATS_FILE_TMPDIR/stage"
  local _fns="$BATS_FILE_TMPDIR/haproxy_fns_only.sh"

  # Strip execution block so setup() can source function definitions only.
  awk '/^base_snapshot_exists/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/haproxy.sh" > "$_fns"

  export MT6_TEST_ENV=1
  export STAGE_MNT="$_stage"
  export ZFS_DATA_MNT="$_data"
  export TOASTER_HOSTNAME="mail.example.com"
  export JAIL_NET_PREFIX="172.16.15"
  export JAIL_ORDERED_LIST="vpopmail haproxy webmail dns roundcube snappymail haraka rspamd"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  mkdir -p "$_data/haproxy/etc" "$_stage/usr/local/etc" "$_stage/usr/local/bin"

  # shellcheck source=/dev/null
  . "$_fns"

  # Override store_config (stubbed as no-op) so haproxy.conf is written to disk.
  store_config() { cat - > "$1"; }

  configure_haproxy_dot_conf
}

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export ZFS_DATA_MNT="$BATS_FILE_TMPDIR/data"
  export HAPROXY_CONF="$ZFS_DATA_MNT/haproxy/etc/haproxy.conf"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  # shellcheck source=/dev/null
  . "$BATS_FILE_TMPDIR/haproxy_fns_only.sh"
}

# --- JAIL variable exports ---

@test "haproxy - JAIL_START_EXTRA is empty" {
  assert_equal "$JAIL_START_EXTRA" ""
}

@test "haproxy - JAIL_CONF_EXTRA is empty" {
  assert_equal "$JAIL_CONF_EXTRA" ""
}

@test "haproxy - JAIL_FSTAB is empty" {
  assert_equal "$JAIL_FSTAB" ""
}

# --- haproxy.conf security headers ---

@test "haproxy.conf - X-Frame-Options header is present" {
  run grep -q 'X-Frame-Options' "$HAPROXY_CONF"
  assert_success
}

@test "haproxy.conf - X-Frame-Options set to sameorigin" {
  run grep 'X-Frame-Options' "$HAPROXY_CONF"
  assert_output --partial 'sameorigin'
}

@test "haproxy.conf - X-XSS-Protection header is present" {
  run grep -q 'X-XSS-Protection' "$HAPROXY_CONF"
  assert_success
}

@test "haproxy.conf - X-XSS-Protection set to block mode" {
  run grep 'X-XSS-Protection' "$HAPROXY_CONF"
  assert_output --partial '1; mode=block'
}

@test "haproxy.conf - X-Content-Type-Options header is present" {
  run grep -q 'X-Content-Type-Options' "$HAPROXY_CONF"
  assert_success
}

@test "haproxy.conf - X-Content-Type-Options set to nosniff" {
  run grep 'X-Content-Type-Options' "$HAPROXY_CONF"
  assert_output --partial 'nosniff'
}

@test "haproxy.conf - Referrer-Policy header is present" {
  run grep -q 'Referrer-Policy' "$HAPROXY_CONF"
  assert_success
}

@test "haproxy.conf - Referrer-Policy set to strict-origin-when-cross-origin" {
  run grep 'Referrer-Policy' "$HAPROXY_CONF"
  assert_output --partial 'strict-origin-when-cross-origin'
}

@test "haproxy.conf - Content-Security-Policy header is present" {
  run grep -q 'Content-Security-Policy' "$HAPROXY_CONF"
  assert_success
}

@test "haproxy.conf - CSP restricts default-src to self" {
  run grep 'Content-Security-Policy' "$HAPROXY_CONF"
  assert_output --partial "default-src 'self'"
}

@test "haproxy.conf - CSP restricts frame-ancestors to self" {
  run grep 'Content-Security-Policy' "$HAPROXY_CONF"
  assert_output --partial "frame-ancestors 'self'"
}

@test "haproxy.conf - security headers use http-response set-header" {
  run grep -c 'http-response set-header' "$HAPROXY_CONF"
  # X-Frame-Options, X-XSS-Protection, X-Content-Type-Options,
  # Referrer-Policy, Content-Security-Policy = 5 directives
  assert [ "$output" -ge 5 ]
}

# --- /auth-check endpoint ---

@test "haproxy.conf - auth-check returns 204 for authenticated users" {
  run grep -q 'http-request return status 204 if auth_check { http_auth(adminusers) }' "$HAPROXY_CONF"
  assert_success
}

@test "haproxy.conf - auth-check returns 204 for local clients" {
  run grep -q 'http-request return status 204 if auth_check is_local' "$HAPROXY_CONF"
  assert_success
}

@test "haproxy.conf - auth-check returns bare 401 (no WWW-Authenticate) for fetch probe" {
  run grep -q 'http-request return status 401 if auth_check' "$HAPROXY_CONF"
  assert_success
}

@test "haproxy.conf - auth-login returns cookie-setting page for authenticated users" {
  run grep 'http-request return.*200.*auth_login.*http_auth' "$HAPROXY_CONF"
  assert_success
  assert_output --partial 'is_admin=1'
}

@test "haproxy.conf - auth-login returns cookie-setting page for local clients" {
  run grep 'http-request return.*200.*auth_login is_local' "$HAPROXY_CONF"
  assert_success
  assert_output --partial 'is_admin=1'
}

@test "haproxy.conf - auth-login sends WWW-Authenticate challenge for unauthenticated users" {
  run grep -q 'http-request auth realm "Restricted" if auth_login' "$HAPROXY_CONF"
  assert_success
}
