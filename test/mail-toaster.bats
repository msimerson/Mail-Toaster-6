# https://bats-core.readthedocs.io/en/stable/writing-tests.html

setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load ../mail-toaster.sh
}

@test "mt6_version_check" {
  run mt6_version_check
  [ "$status" -eq 0 ]
}

@test "safe_jailname replaces . with _" {
  run safe_jailname bad.chars
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "bad_chars" ]
}

@test "reverse_list" {
  run reverse_list tic tac toe
  assert_output --partial "toe tac tic"
}

@test "tell_status" {
  run tell_status "BATS testing"
  [ "$status" -eq 0 ]
}
