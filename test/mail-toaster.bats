# https://bats-core.readthedocs.io/en/stable/writing-tests.html

setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load ../mail-toaster.sh
}

@test "mt6_version_check" {
  run mt6_version_check
  #[ "$status" -eq 0 ]
  assert_success
}

@test "safe_jailname replaces . with _" {
  run safe_jailname bad.chars
  assert_success
  assert_output "bad_chars"
}

@test "reverse_list" {
  run reverse_list tic tac toe
  #echo "# $output" >&3
  assert_success
  assert_output --partial "toe tac tic"
}

@test "tell_status" {
  run tell_status "BATS testing"
  assert_success
}
