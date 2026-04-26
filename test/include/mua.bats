
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

@test "uriencode / (slash)" {
  run uriencode "/"
  assert_success
  assert_output "%2f"
}

@test "uriencode : (colon)" {
  run uriencode ":"
  assert_success
  assert_output "%3a"
}

@test "uriencode + (plus)" {
  run uriencode "+"
  assert_success
  assert_output "%2b"
}

@test "uriencode = (equals)" {
  run uriencode "="
  assert_success
  assert_output "%3d"
}

@test "uriencode plain alphanumeric unchanged" {
  run uriencode "abc123"
  assert_success
  assert_output "abc123"
}

@test "uriencode hyphen unchanged" {
  run uriencode "a-b"
  assert_success
  assert_output "a-b"
}

@test "uriencode dot unchanged" {
  run uriencode "."
  assert_success
  assert_output "."
}

@test "uriencode underscore unchanged" {
  run uriencode "_"
  assert_success
  assert_output "_"
}

@test "uriencode tilde unchanged" {
  run uriencode "~"
  assert_success
  assert_output "~"
}

@test "uriencode mixed string" {
  run uriencode "user@host.com"
  assert_success
  assert_output "user%40host.com"
}
