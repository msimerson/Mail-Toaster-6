#!/usr/bin/env bats
# Functional tests for provision/dhcp.sh

setup_file() {
  export DHCP_FNS="$BATS_FILE_TMPDIR/dhcp_fns_only.sh"
  awk '/^base_snapshot_exists/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/dhcp.sh" > "$DHCP_FNS"
}

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export JAIL_DEVFS_RULESET_BPF="5"
  export MT6_ETC="$BATS_TEST_TMPDIR/etc"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"

  RDR_CONF="$MT6_ETC/dhcp/pf.conf.d/rdr.conf"

  # shellcheck source=/dev/null
  . "$DHCP_FNS"
}

# /etc/pf.conf declares <ext_ip>, <ext_ip4> and <ext_ip6>. A rule naming any
# other table fails to load, taking the whole anchor with it.
@test "dhcp - rdr.conf names a table pf.conf declares" {
  configure_dhcpd > /dev/null

  run cat "$RDR_CONF"
  refute_output --partial "<ext_ips>"
  assert_output --partial "<ext_ip4>"
}

@test "dhcp - rdr.conf redirects udp, the protocol DHCP speaks" {
  configure_dhcpd > /dev/null

  run cat "$RDR_CONF"
  assert_output --partial "proto udp"
  refute_output --partial "proto tcp"
}

# ports 67 and 68 are DHCPv4; DHCPv6 is a different service on 546 and 547
@test "dhcp - rdr.conf has no IPv6 rule" {
  configure_dhcpd > /dev/null

  run cat "$RDR_CONF"
  refute_output --partial "inet6"
}

@test "dhcp - rdr.conf sends the DHCP ports to the dhcp jail" {
  configure_dhcpd > /dev/null

  run cat "$RDR_CONF"
  assert_output --partial "port { 67 68 } -> $(get_jail_ip4 dhcp)"
}
