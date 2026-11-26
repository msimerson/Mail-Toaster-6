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
  export _deploy="$BATS_TEST_TMPDIR/deploy"
  export TOASTER_HOSTNAME="mail.example.com"
  mkdir -p "$_deploy"
  install_deploy_haproxy
  install_deploy_haraka

  run grep -n '/tmp/' "$_deploy/haproxy" "$_deploy/haraka"
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

# --- a reprovision reaches hooks that are already installed ---

_use_real_store_config() {
  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../include/util.sh"
  export _deploy="$BATS_TEST_TMPDIR/deploy"
  export TOASTER_HOSTNAME="mail.example.com"
  mkdir -p "$_deploy"
}

# the line the vulnerable hooks have
_old_hook() {
  printf '#!/bin/sh\nhaproxy_deploy() {\n\tlocal _tmp="/tmp/${_cdomain}.pem"\n\tcat "$_ckey" "$_cfullchain" > "$_tmp"\n}\n'
}

@test "letsencrypt - an untouched old hook is replaced on reprovision" {
  _use_real_store_config
  local _h
  for _h in haproxy haraka; do
    _old_hook | tee "$_deploy/$_h" > "$_deploy/$_h.mt6"

    "install_deploy_$_h"

    run grep -F '/tmp/${_cdomain}.pem' "$_deploy/$_h"
    assert_failure
    run grep -c 'install_pem()' "$_deploy/$_h"
    assert_output "1"
  done
}

@test "letsencrypt - an edited old hook is kept, and the admin is told" {
  _use_real_store_config
  local _h
  for _h in haproxy haraka; do
    { _old_hook; echo "# local change"; } > "$_deploy/$_h"
    _old_hook > "$_deploy/$_h.mt6"

    run "install_deploy_$_h"
    assert_success
    assert_output --partial "WARNING: $_deploy/$_h is edited"

    run grep -c "local change" "$_deploy/$_h"
    assert_output "1"
  done
}

@test "letsencrypt - an edited hook that no longer uses /tmp/<domain>.pem gets no warning" {
  _use_real_store_config
  local _h
  for _h in haproxy haraka; do
    "install_deploy_$_h"
    echo "# local change" >> "$_deploy/$_h"

    run "install_deploy_$_h"
    assert_success
    refute_output --partial "WARNING"
    run grep -c "local change" "$_deploy/$_h"
    assert_output "1"
  done
}
