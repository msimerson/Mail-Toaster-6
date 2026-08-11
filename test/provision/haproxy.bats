#!/usr/bin/env bats
# Functional tests for provision/haproxy.sh
#
# Performance design (matches dns.bats pattern):
# - setup_file() runs ONCE: overrides store_config so it writes to disk,
#   then calls configure_haproxy_dot_conf to generate haproxy.conf.
# - setup() runs per-test (fast): sources only the function definitions.

setup_file() {
  local _fns="$BATS_FILE_TMPDIR/haproxy_fns_only.sh"

  # Strip execution block so setup() can source function definitions only.
  awk '/^base_snapshot_exists/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/haproxy.sh" > "$_fns"

  export MT6_TEST_ENV=1
  export TOASTER_HOSTNAME="mail.example.com"
  export JAIL_NET_PREFIX="172.16.15"
  export JAIL_ORDERED_LIST="vpopmail haproxy webmail dns roundcube snappymail haraka rspamd"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  # shellcheck source=/dev/null
  . "$_fns"

  # Override store_config (stubbed as no-op) so haproxy.conf is written to disk.
  store_config() { cat - > "$1"; }

  # One config set per address family the host might have. The stub
  # mail-toaster.sh clears PUBLIC_IP4/PUBLIC_IP6, so set them after sourcing.
  gen_conf both    "203.0.113.10" "2001:db8::10"
  gen_conf ip4only "203.0.113.10" ""
  gen_conf ip6only ""             "2001:db8::10"
  gen_conf neither ""             ""
}

gen_conf() {
  export ZFS_DATA_MNT="$BATS_FILE_TMPDIR/$1/data"
  export STAGE_MNT="$BATS_FILE_TMPDIR/$1/stage"
  export PUBLIC_IP4="$2"
  export PUBLIC_IP6="$3"

  mkdir -p "$ZFS_DATA_MNT/haproxy/etc" "$STAGE_MNT/usr/local/etc" \
    "$STAGE_MNT/usr/local/bin"

  configure_haproxy_dot_conf
}

conf()       { echo "$BATS_FILE_TMPDIR/$1/data/haproxy/etc/haproxy.conf"; }
stage_conf() { echo "$BATS_FILE_TMPDIR/$1/stage/usr/local/etc/haproxy.conf"; }

setup() {
  load '../test_helper/load'

  HAPROXY_CONF="$(conf both)"
}

# haproxy -c on a copy with the cert path and DH params pointed at fixtures
assert_haproxy_accepts() {
  command -v haproxy > /dev/null || skip "haproxy not installed"
  command -v openssl > /dev/null || skip "openssl not installed"

  local _tls="$BATS_FILE_TMPDIR/tls.d"
  if [ ! -f "$_tls/$TOASTER_HOSTNAME.pem" ]; then
    mkdir -p "$_tls"
    openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
      -subj "/CN=$TOASTER_HOSTNAME" \
      -keyout "$_tls/key" -out "$_tls/crt" 2> /dev/null
    cat "$_tls/key" "$_tls/crt" > "$_tls/$TOASTER_HOSTNAME.pem"
    rm -f "$_tls/key" "$_tls/crt"
  fi

  local _local="$1.local"
  sed -e "s|/data/etc/tls.d|$_tls|" -e '/ssl-dh-param-file/d' "$1" > "$_local"

  run haproxy -c -f "$_local"
  assert_success
}

# --- JAIL variable exports ---

@test "haproxy - declares no jail extras" {
  assert_equal "$JAIL_START_EXTRA" ""
  assert_equal "$JAIL_CONF_EXTRA" ""
  assert_equal "$JAIL_FSTAB" ""
}

# --- frontend binds ---
#
# 'bind :::80 v4v6' refuses to start on a host without IPv6, so each address
# family gets its own bind and only the families the host has are emitted.

@test "haproxy.conf - dual stack binds both families" {
  run grep '^	bind ' "$(conf both)"
  assert_line '	bind 0.0.0.0:80 alpn http/1.1'
  assert_line '	bind 0.0.0.0:443 alpn http/1.1 ssl crt /data/etc/tls.d'
  assert_line '	bind [::]:80 alpn http/1.1'
  assert_line '	bind [::]:443 alpn http/1.1 ssl crt /data/etc/tls.d'
}

@test "haproxy.conf - IPv4 only host binds no IPv6" {
  run grep '^	bind ' "$(conf ip4only)"
  assert_line '	bind 0.0.0.0:80 alpn http/1.1'
  assert_line '	bind 0.0.0.0:443 alpn http/1.1 ssl crt /data/etc/tls.d'
  refute_line --partial '[::]'
}

@test "haproxy.conf - IPv6 only host binds no IPv4" {
  run grep '^	bind ' "$(conf ip6only)"
  assert_line '	bind [::]:80 alpn http/1.1'
  assert_line '	bind [::]:443 alpn http/1.1 ssl crt /data/etc/tls.d'
  refute_line --partial '0.0.0.0'
}

@test "haproxy.conf - with no public address detected, falls back to IPv4" {
  run grep '^	bind ' "$(conf neither)"
  assert_line '	bind 0.0.0.0:80 alpn http/1.1'
  refute_line --partial '[::]'
}

@test "haproxy.conf - no v4v6 bind option in any case" {
  run grep -l 'v4v6' "$(conf both)" "$(conf ip4only)" "$(conf ip6only)" \
    "$(conf neither)"
  assert_failure
}

# --- stage jail binds ---

@test "haproxy stage conf - dual stack binds both families" {
  run grep '^    bind ' "$(stage_conf both)"
  assert_line '    bind 172.16.15.1:80 alpn http/1.1'
  assert_line '    bind [fd7a:e5cd:1fc1:c597:dead:beef:cafe:00fe]:80 alpn http/1.1'
}

@test "haproxy stage conf - IPv4 only host binds no IPv6" {
  run grep '^    bind ' "$(stage_conf ip4only)"
  assert_line '    bind 172.16.15.1:80 alpn http/1.1'
  refute_line --partial '['
}

@test "haproxy stage conf - IPv6 only host binds no IPv4" {
  run grep '^    bind ' "$(stage_conf ip6only)"
  assert_line '    bind [fd7a:e5cd:1fc1:c597:dead:beef:cafe:00fe]:80 alpn http/1.1'
  refute_line --partial '172.16.15'
}

# --- haproxy accepts the generated configs ---

@test "haproxy - validates every generated config" {
  local _case
  for _case in both ip4only ip6only; do
    assert_haproxy_accepts "$(conf "$_case")"
    assert_haproxy_accepts "$(stage_conf "$_case")"
  done
}

# --- haproxy.conf security headers ---

# <header> <value it must carry>
@test "haproxy.conf - sets the security headers" {
  while read -r _header _value; do
    [ -n "$_header" ] || continue
    run grep "$_header" "$HAPROXY_CONF"
    assert_success
    assert_output --partial "$_value"
  done <<'EO_HEADERS'
X-Frame-Options         sameorigin
X-XSS-Protection        1; mode=block
X-Content-Type-Options  nosniff
Referrer-Policy         strict-origin-when-cross-origin
Content-Security-Policy default-src 'self'
Content-Security-Policy frame-ancestors 'self'
EO_HEADERS
}

@test "haproxy.conf - security headers use http-response set-header" {
  run grep -c 'http-response set-header' "$HAPROXY_CONF"
  # X-Frame-Options, X-XSS-Protection, X-Content-Type-Options,
  # Referrer-Policy, Content-Security-Policy = 5 directives
  assert [ "$output" -ge 5 ]
}

# --- /auth-check endpoint ---

@test "haproxy.conf - auth-check answers the fetch probe without a challenge" {
  run grep -q 'http-request return status 204 if auth_check { http_auth(adminusers) }' "$HAPROXY_CONF"
  assert_success
  run grep -q 'http-request return status 204 if auth_check is_local' "$HAPROXY_CONF"
  assert_success
  # a bare 401, no WWW-Authenticate, or the browser pops its own dialog
  run grep -q 'http-request return status 401 if auth_check' "$HAPROXY_CONF"
  assert_success
}

@test "haproxy.conf - auth-login sets the admin cookie, else challenges" {
  run grep 'http-request return.*200.*auth_login.*http_auth' "$HAPROXY_CONF"
  assert_success
  assert_output --partial 'is_admin=1'

  run grep 'http-request return.*200.*auth_login is_local' "$HAPROXY_CONF"
  assert_success
  assert_output --partial 'is_admin=1'

  run grep -q 'http-request auth realm "Restricted" if auth_login' "$HAPROXY_CONF"
  assert_success
}
