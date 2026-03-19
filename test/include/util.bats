#!/usr/bin/env bats

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  load '../../include/util.sh'
}

@test "dec_to_hex" {
  run dec_to_hex 255
  assert_output "00ff"
}

@test "store_config - new file" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/new_file"

  tell_status() { :; }

  echo "hello" | store_config "$tmpfile"

  run cat "$tmpfile"
  assert_output "hello"

  rm -rf "$tmpdir"
}

@test "store_config - preserve existing" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/new_file"
  echo "original" > "$tmpfile"

  tell_status() { :; }

  echo "new" | store_config "$tmpfile"

  run cat "$tmpfile"
  assert_output "original"

  rm -rf "$tmpdir"
}

@test "get_random_pass - length" {
  run get_random_pass 20
  assert_success
  [ "${#output}" -eq 20 ]
}

@test "reverse_list" {
  run reverse_list one two three
  assert_output "three two one "
}
