#!/usr/bin/env bats
# Functional tests for provision/dcc.sh
#
# dcc speaks IPv6 only when the port was built with the IPV6 option and cdcc
# was not told to turn it off, so both decisions have to follow the jail.

setup_file() {
  export DCC_FNS="$BATS_FILE_TMPDIR/dcc_fns_only.sh"
  awk '/^base_snapshot_exists/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/dcc.sh" > "$DCC_FNS"
}

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export STAGE_MNT; STAGE_MNT=$(mktemp -d)

  # shellcheck source=/dev/null
  . "$DCC_FNS"

  # the stubs are no-ops; report the arguments so the tests can assert on them
  stage_make_conf() { echo "make_conf: $*"; }
  stage_exec()      { echo "exec: $*"; }
  stage_sysrc()     { echo "sysrc: $*"; }
}

teardown() {
  rm -rf "$STAGE_MNT"
}

host_has_ip6() {
  if [ "$1" = "yes" ]; then
    export PUBLIC_IP6="2001:db8::1"
  else
    export PUBLIC_IP6=""
  fi
  get_public_ip6() { :; }
}

@test "dcc - the port builds with IPV6 when the jail has an IPv6 address" {
  host_has_ip6 yes

  run install_dcc_port_options
  assert_line --partial "mail_dcc-dccd_SET=DCCIFD IPV6"
  refute_output --partial "_UNSET=DCCGREY DCCD DCCM PORTS_MILTER IPV6"
}

@test "dcc - the port drops IPV6 when the jail has no IPv6 address" {
  host_has_ip6 no

  run install_dcc_port_options
  assert_line --partial "mail_dcc-dccd_UNSET=DCCGREY DCCD DCCM PORTS_MILTER IPV6"
  assert_line --partial "mail_dcc-dccd_SET=DCCIFD"
  refute_output --partial "_SET=DCCIFD IPV6"
}

# start_dcc used to read a PUBLIC_IP6 nothing in this script populates, so an
# IPv6 only host reached cdcc with IPv6 switched off
@test "dcc - cdcc keeps IPv6 on when the jail has an IPv6 address" {
  host_has_ip6 yes

  run start_dcc
  assert_line "exec: cdcc info"
}

@test "dcc - cdcc turns IPv6 off when the jail has none" {
  host_has_ip6 no

  run start_dcc
  assert_line "exec: cdcc IPv6=off info"
}

@test "dcc - start_dcc does not depend on its caller for PUBLIC_IP6" {
  # the real has_public_ip6, which jail_has_ip6 defers to
  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../include/network.sh"

  # stub what it shells out to. These must come after the source above, or
  # network.sh replaces get_public_facing_nic with the real one, which reads the
  # host routing table and fails wherever netstat has no "default" line.
  get_public_facing_nic() { export PUBLIC_NIC="em0"; }
  ifconfig() { echo "	inet6 2001:db8::1 prefixlen 64"; }

  unset PUBLIC_IP6
  run start_dcc
  assert_line "exec: cdcc info"
}
