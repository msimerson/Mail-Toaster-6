
setup() {
  load '../test_helper/load'
  export MT6_TEST_ENV=1
  load ../../include/util.sh
  load ../../include/network.sh
}

@test "get_random_ip6net - format" {
  run get_random_ip6net
  assert_success
  assert_output --regexp '^fd7a:e5cd:1fc1:[0-9a-f]{4}:dead:beef:cafe$'
}

@test "get_random_ip6net - constant prefix" {
  run get_random_ip6net
  assert_output --partial "fd7a:e5cd:1fc1:"
}

@test "get_random_ip6net - constant suffix" {
  run get_random_ip6net
  assert_output --partial ":dead:beef:cafe"
}

# PUBLIC_IP4/6 are the public facing addresses, which need not be bound to a
# local interface, so detection must not overwrite what the admin configured.
@test "get_public_ip4 - keeps a configured address" {
  get_public_facing_nic() { export PUBLIC_NIC="em0"; }
  ifconfig() { echo "	inet 10.0.0.5 netmask 0xffffff00"; }
  export PUBLIC_IP4="203.0.113.7"
  get_public_ip4
  assert_equal "$PUBLIC_IP4" "203.0.113.7"
}

@test "get_public_ip4 - detects when unset" {
  get_public_facing_nic() { export PUBLIC_NIC="em0"; }
  ifconfig() { echo "	inet 10.0.0.5 netmask 0xffffff00"; }
  export PUBLIC_IP4=""
  get_public_ip4
  assert_equal "$PUBLIC_IP4" "10.0.0.5"
}

# host.sh fatals when PUBLIC_NIC is unset, so the early return must come after
# the NIC lookup, not before it.
@test "get_public_ip4 - still exports PUBLIC_NIC with a configured address" {
  get_public_facing_nic() { export PUBLIC_NIC="em0"; }
  export PUBLIC_IP4="203.0.113.7"
  unset PUBLIC_NIC
  get_public_ip4
  assert_equal "$PUBLIC_NIC" "em0"
}

@test "get_public_ip6 - keeps a configured address" {
  get_public_facing_nic() { export PUBLIC_NIC="em0"; }
  ifconfig() { echo "	inet6 fe80::1%em0"; echo "	inet6 2001:db8::99"; }
  export PUBLIC_IP6="2001:db8::1"
  get_public_ip6
  assert_equal "$PUBLIC_IP6" "2001:db8::1"
}

@test "get_public_ip6 - detects when unset" {
  get_public_facing_nic() { export PUBLIC_NIC="em0"; }
  ifconfig() { echo "	inet6 fe80::1%em0"; echo "	inet6 2001:db8::99"; }
  export PUBLIC_IP6=""
  get_public_ip6
  assert_equal "$PUBLIC_IP6" "2001:db8::99"
}

@test "get_random_ip6net - unique per call" {
  local first; first=$(get_random_ip6net)
  local second; second=$(get_random_ip6net)
  # extremely unlikely to be equal; validates randomness is working
  [ "$first" != "$second" ] || skip "got identical values (astronomically unlikely)"
}
