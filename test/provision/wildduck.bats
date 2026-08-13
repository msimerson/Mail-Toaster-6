#!/usr/bin/env bats
# Functional tests for provision/wildduck.sh

setup_file() {
  export WD_FNS="$BATS_FILE_TMPDIR/wildduck_fns_only.sh"
  awk '/^base_snapshot_exists/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/wildduck.sh" > "$WD_FNS"
}

setup() {
  load '../test_helper/load'

  export MT6_TEST_ENV=1
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export MT6_ETC="$BATS_TEST_TMPDIR/etc"
  export PUBLIC_NIC="em0"

  RDR_CONF="$MT6_ETC/wildduck/pf.conf.d/rdr.conf"
  NAT_CONF="$MT6_ETC/wildduck/pf.conf.d/nat.conf"

  # shellcheck source=/dev/null
  . "$WD_FNS"
}

# each get_public_ip* resolves its own family's default route into PUBLIC_NIC
two_nic_host() {
  export PUBLIC_IP4="$1" PUBLIC_IP6="$2"
  get_public_ip4() { export PUBLIC_NIC="em0"; }
  get_public_ip6() { export PUBLIC_NIC="gif0"; }
}

@test "wildduck - each family NATs on its own interface" {
  two_nic_host "203.0.113.7" "2001:db8::1"

  configure_pf > /dev/null

  run cat "$NAT_CONF"
  assert_line 'ext_if  = "em0"'
  assert_line 'ext_if6 = "gif0"'
  assert_line 'nat on $ext_if from $int_ip4 to any -> $ext_ip4'
  assert_line 'nat on $ext_if6 from $int_ip6 to any -> $ext_ip6'
}

@test "wildduck - a one NIC host uses it for both families" {
  export PUBLIC_IP4="203.0.113.7" PUBLIC_IP6="2001:db8::1"
  get_public_ip4() { export PUBLIC_NIC="em0"; }
  get_public_ip6() { export PUBLIC_NIC="em0"; }

  configure_pf > /dev/null

  run cat "$NAT_CONF"
  assert_line 'ext_if  = "em0"'
  assert_line 'ext_if6 = "em0"'
}

@test "wildduck - an IPv4 only host emits no IPv6 rules" {
  two_nic_host "203.0.113.7" ""

  configure_pf > /dev/null

  run cat "$NAT_CONF"
  assert_line 'ext_if  = "em0"'
  assert_line 'ext_if6 = "em0"'
  refute_output --partial 'int_ip6'
  refute_output --partial '$ext_ip6'

  run cat "$RDR_CONF"
  refute_output --partial 'inet6'
}

@test "wildduck - an IPv6 only host emits no IPv4 NAT" {
  two_nic_host "" "2001:db8::1"

  configure_pf > /dev/null

  run cat "$NAT_CONF"
  assert_line 'ext_if  = "gif0"'
  assert_line 'ext_if6 = "gif0"'
  assert_line 'nat on $ext_if6 from $int_ip6 to any -> $ext_ip6'
  refute_output --partial 'to any -> $ext_ip4'

  run cat "$RDR_CONF"
  assert_output --partial 'inet6'
  refute_output --partial 'rdr inet '
}

@test "wildduck - mail and http redirects reach the right jails" {
  two_nic_host "203.0.113.7" "2001:db8::1"

  configure_pf > /dev/null

  run cat "$RDR_CONF"
  assert_output --partial "int_ip4 = \"$(get_jail_ip4 wildduck)\""
  assert_output --partial "int_ip6 = \"$(get_jail_ip6 wildduck)\""
  assert_output --partial 'port { 25 465 587 993 995 } -> $int_ip4'
  assert_output --partial "port { 80 443 } -> $(get_jail_ip4 haproxy)"
}
