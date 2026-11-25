#!/usr/bin/env bats
# Functional tests for provision/letsencrypt.sh
#
# Only the function definitions are sourced: the execution block would issue
# a certificate.

setup() {
  load helper
  provision_fns letsencrypt install_letsencrypt

  pkg() { :; }
  export ACME_HOME="$BATS_TEST_TMPDIR/acme"
  export ACME_EXAMPLES="$BATS_TEST_TMPDIR/examples"
  mkdir -p "$ACME_EXAMPLES/dnsapi"
  touch "$ACME_EXAMPLES/dnsapi/dns_cf.sh"
}

@test "letsencrypt - install links the pkg DNS API hooks into the acme.sh home" {
  run install_letsencrypt
  assert_success
  assert [ -L "$ACME_HOME/dnsapi" ]
  assert [ -f "$ACME_HOME/dnsapi/dns_cf.sh" ]
}

@test "letsencrypt - install keeps an existing dnsapi directory" {
  mkdir -p "$ACME_HOME/dnsapi"
  touch "$ACME_HOME/dnsapi/dns_custom.sh"
  run install_letsencrypt
  assert_success
  assert [ ! -L "$ACME_HOME/dnsapi" ]
  assert [ -f "$ACME_HOME/dnsapi/dns_custom.sh" ]
}

@test "letsencrypt - install is idempotent" {
  install_letsencrypt
  run install_letsencrypt
  assert_success
  assert [ -f "$ACME_HOME/dnsapi/dns_cf.sh" ]
}

@test "letsencrypt - install skips the link when the pkg ships no hooks" {
  rm -rf "$ACME_EXAMPLES/dnsapi"
  run install_letsencrypt
  assert_success
  assert [ ! -e "$ACME_HOME/dnsapi" ]
}

# --- deploy hooks ---

# a hook as install_deploy_scripts writes it, aimed at the sandbox. $1 haproxy|haraka
_load_hook() {
  export _deploy="$BATS_TEST_TMPDIR/deploy"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  export TOASTER_HOSTNAME="mail.example.com"
  mkdir -p "$_deploy" "$TMPDIR"

  "install_deploy_$1"
  # /tmp first: the sandbox may be under /tmp
  sed_inplace -e "s|/tmp/|$TMPDIR/|g" -e "s|/data/$1|$BATS_TEST_TMPDIR/data/$1|g" "$_deploy/$1"

  _debug() { :; }
  _err() { echo "ERR: $*" >&2; }
  jexec() { echo "$*" >> "$BATS_TEST_TMPDIR/reloads"; }
  service() { echo "$*" >> "$BATS_TEST_TMPDIR/reloads"; }
  # shellcheck source=/dev/null
  . "$_deploy/$1"

  export _key="$BATS_TEST_TMPDIR/example.key" _chain="$BATS_TEST_TMPDIR/fullchain.cer" \
    _ca="$BATS_TEST_TMPDIR/ca.cer"
  echo "PRIVATE KEY" > "$_key"
  echo "CHAIN" > "$_chain"
  echo "CA" > "$_ca"
  : > "$BATS_TEST_TMPDIR/reloads"
}

_leftovers() { ls -A "$TMPDIR" | wc -l | tr -d ' '; }

@test "letsencrypt - haproxy hook installs key and chain and removes its temp file" {
  _load_hook haproxy
  mkdir -p "$BATS_TEST_TMPDIR/data/haproxy/etc/tls.d"

  run haproxy_deploy example.org "$_key" "$_chain" "$_ca" "$_chain"
  assert_success

  run cat "$BATS_TEST_TMPDIR/data/haproxy/etc/tls.d/example.org.pem"
  assert_output "PRIVATE KEY
CHAIN"
  assert [ "$(_leftovers)" = "0" ]
  run cat "$BATS_TEST_TMPDIR/reloads"
  assert_output --partial "haproxy service haproxy reload"
}

@test "letsencrypt - haproxy hook leaves no key behind when nothing changed" {
  _load_hook haproxy
  mkdir -p "$BATS_TEST_TMPDIR/data/haproxy/etc/tls.d"
  haproxy_deploy example.org "$_key" "$_chain" "$_ca" "$_chain"
  : > "$BATS_TEST_TMPDIR/reloads"

  run haproxy_deploy example.org "$_key" "$_chain" "$_ca" "$_chain"
  assert_success
  assert [ "$(_leftovers)" = "0" ]
  # an unchanged cert does not reload haproxy
  run cat "$BATS_TEST_TMPDIR/reloads"
  assert_output ""
}

@test "letsencrypt - haproxy hook creates the temp file private, not at a predictable path" {
  _load_hook haproxy
  mkdir -p "$BATS_TEST_TMPDIR/data/haproxy/etc/tls.d"
  umask 022
  has_differences() { echo "$1" > "$BATS_TEST_TMPDIR/tmpname"; _file_mode "$1" > "$BATS_TEST_TMPDIR/tmpmode"; return 1; }

  haproxy_deploy example.org "$_key" "$_chain" "$_ca" "$_chain"

  run cat "$BATS_TEST_TMPDIR/tmpmode"
  assert_output "600"
  run cat "$BATS_TEST_TMPDIR/tmpname"
  refute_output "$TMPDIR/example.org.pem"
  assert_output --regexp "/le-deploy\\.[A-Za-z0-9]+$"
  assert [ "$(_leftovers)" = "0" ]
}

@test "letsencrypt - haproxy hook removes the temp file when the install fails" {
  _load_hook haproxy
  mkdir -p "$BATS_TEST_TMPDIR/data/haproxy/etc/tls.d"
  install_file() { return 1; }

  run haproxy_deploy example.org "$_key" "$_chain" "$_ca" "$_chain"
  assert_failure
  assert [ "$(_leftovers)" = "0" ]
}

@test "letsencrypt - haraka hook installs key and chain and removes its temp file" {
  _load_hook haraka
  mkdir -p "$BATS_TEST_TMPDIR/data/haraka/config/tls"

  run haraka_deploy example.org "$_key" "$_chain" "$_ca" "$_chain"
  assert_success

  run cat "$BATS_TEST_TMPDIR/data/haraka/config/tls/example.org.pem"
  assert_output "PRIVATE KEY
CHAIN"
  assert [ "$(_leftovers)" = "0" ]
}

@test "letsencrypt - haraka hook leaves no key behind when nothing changed" {
  _load_hook haraka
  mkdir -p "$BATS_TEST_TMPDIR/data/haraka/config/tls"
  haraka_deploy example.org "$_key" "$_chain" "$_ca" "$_chain"
  : > "$BATS_TEST_TMPDIR/reloads"

  run haraka_deploy example.org "$_key" "$_chain" "$_ca" "$_chain"
  assert_success
  assert [ "$(_leftovers)" = "0" ]
  run cat "$BATS_TEST_TMPDIR/reloads"
  assert_output ""
}

@test "letsencrypt - no deploy hook writes the key to a fixed path in /tmp" {
  run grep -n '/tmp/' "$PROVISION_DIR/letsencrypt.sh"
  # only the mktemp templates
  refute_output --regexp '/tmp/[^"]*\.pem'
  refute_output --regexp '/tmp/\$\{?_cdomain'
}

@test "letsencrypt - haproxy hook installs nothing when the chain cannot be read" {
  _load_hook haproxy
  mkdir -p "$BATS_TEST_TMPDIR/data/haproxy/etc/tls.d"

  run haproxy_deploy example.org "$_key" "$_chain" "$_ca" "$BATS_TEST_TMPDIR/missing.cer"
  assert_failure
  assert [ ! -e "$BATS_TEST_TMPDIR/data/haproxy/etc/tls.d/example.org.pem" ]
  assert [ "$(_leftovers)" = "0" ]
  run cat "$BATS_TEST_TMPDIR/reloads"
  assert_output ""
}

@test "letsencrypt - haproxy hook does not replace an installed pem when the key cannot be read" {
  _load_hook haproxy
  local _tls="$BATS_TEST_TMPDIR/data/haproxy/etc/tls.d"
  mkdir -p "$_tls"
  echo "OLD" > "$_tls/example.org.pem"

  run haproxy_deploy example.org "$BATS_TEST_TMPDIR/missing.key" "$_chain" "$_ca" "$_chain"
  assert_failure
  run cat "$_tls/example.org.pem"
  assert_output "OLD"
  assert [ "$(_leftovers)" = "0" ]
}

@test "letsencrypt - haraka hook installs nothing when the chain cannot be read" {
  _load_hook haraka
  mkdir -p "$BATS_TEST_TMPDIR/data/haraka/config/tls"

  run haraka_deploy example.org "$_key" "$_chain" "$_ca" "$BATS_TEST_TMPDIR/missing.cer"
  assert_failure
  assert [ ! -e "$BATS_TEST_TMPDIR/data/haraka/config/tls/example.org.pem" ]
  assert [ "$(_leftovers)" = "0" ]
}

@test "letsencrypt - haraka hook failed install leaves no key behind" {
  _load_hook haraka
  mkdir -p "$BATS_TEST_TMPDIR/data/haraka/config/tls"
  install_file() { return 1; }

  run haraka_deploy example.org "$_key" "$_chain" "$_ca" "$_chain"
  assert_failure
  assert [ "$(_leftovers)" = "0" ]
}
