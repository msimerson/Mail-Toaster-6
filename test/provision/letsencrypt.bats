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
