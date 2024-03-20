# https://bats-core.readthedocs.io/en/stable/writing-tests.html

setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load ../mail-toaster.sh
}

@test "mt6_version" {
  run mt6_version
  assert_success
  assert_output --partial "2024"
}

@test "mt6_version_check" {
  run mt6_version_check
  #[ "$status" -eq 0 ]
  assert_success
}

@test "dec_to_hex" {
  run dec_to_hex 10
  assert_success
  assert_output "000a"
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

@test "tell_settings" {
  skip
  run tell_settings "ROUNDCUBE"
  assert_success
  assert_output --partial "
   ***   Configured ROUNDCUBE settings:"
}

@test "tell_status" {
  skip
  run tell_status "BATS testing"
  assert_success
}

@test "proclaim_success" {
  run proclaim_success "test"
  assert_success
  assert_output --partial "Success! A new 'test' jail is provisioned"
}

@test "get_random_pass" {
  run get_random_pass 15
  assert_success
  echo "# $output" >&3
  #assert_output --partial ""
}
