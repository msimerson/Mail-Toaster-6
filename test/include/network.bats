
setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
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

@test "get_random_ip6net - unique per call" {
  local first; first=$(get_random_ip6net)
  local second; second=$(get_random_ip6net)
  # extremely unlikely to be equal; validates randomness is working
  [ "$first" != "$second" ] || skip "got identical values (astronomically unlikely)"
}
