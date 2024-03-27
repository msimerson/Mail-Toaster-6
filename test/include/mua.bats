
setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  load ../../include/mua.sh
}

@test "include/mua.sh" {
  skip "works locally, doesn't in GHA"
  run ./include/mua.sh
  assert_success
}

@test "uriencode @" {
  run uriencode @
  assert_success
  assert_output "%40"
}

@test "uriencode [space]" {
  run uriencode " "
  assert_success
  assert_output "%20"
}

@test "uriencode '" {
  run uriencode "'"
  assert_success
  assert_output "%27"
}

@test "uriencode )" {
  run uriencode ")"
  assert_success
  assert_output "%29"
}
