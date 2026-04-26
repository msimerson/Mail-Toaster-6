#!/usr/bin/env bats

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  load '../../include/util.sh'
}

@test "mt6_version - outputs 8-digit date" {
  run mt6_version
  assert_success
  assert_output --regexp '^[0-9]{8}$'
}

@test "tell_status - outputs message" {
  run tell_status "hello"
  assert_success
  assert_output --partial "hello"
}

@test "dec_to_hex - 255" {
  run dec_to_hex 255
  assert_output "00ff"
}

@test "dec_to_hex - 0" {
  run dec_to_hex 0
  assert_output "0000"
}

@test "dec_to_hex - 65535" {
  run dec_to_hex 65535
  assert_output "ffff"
}

@test "dec_to_hex - 16" {
  run dec_to_hex 16
  assert_output "0010"
}

@test "store_config - new file" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/new_file"

  echo "hello" | store_config "$tmpfile"

  run cat "$tmpfile"
  assert_output "hello"

  rm -rf "$tmpdir"
}

@test "store_config - preserve existing" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/new_file"
  echo "original" > "$tmpfile"

  echo "new" | store_config "$tmpfile"

  run cat "$tmpfile"
  assert_output "original"

  rm -rf "$tmpdir"
}

@test "store_config - overwrite existing" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/new_file"
  echo "original" > "$tmpfile"

  echo "new" | store_config "$tmpfile" "overwrite"

  run cat "$tmpfile"
  assert_output "new"

  rm -rf "$tmpdir"
}

@test "store_config - append to existing" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/new_file"
  echo "first" > "$tmpfile"

  echo "second" | store_config "$tmpfile" "append"

  run cat "$tmpfile"
  assert_output "$(printf 'first\nsecond')"

  rm -rf "$tmpdir"
}

@test "store_config - creates parent directories" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/nested/dir/file"

  echo "content" | store_config "$tmpfile"

  [ -f "$tmpfile" ]

  rm -rf "$tmpdir"
}

@test "store_exec - creates executable file" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/script.sh"

  echo "#!/bin/sh" | store_exec "$tmpfile"

  [ -x "$tmpfile" ]

  rm -rf "$tmpdir"
}

@test "store_exec - file has 755 permissions" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/script.sh"

  echo "#!/bin/sh" | store_exec "$tmpfile"

  run find "$tmpdir" -name "script.sh" -perm 755
  assert_output "$tmpfile"

  rm -rf "$tmpdir"
}

@test "store_exec - file contains expected content" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/script.sh"

  printf '#!/bin/sh\necho hello\n' | store_exec "$tmpfile"

  run cat "$tmpfile"
  assert_output "$(printf '#!/bin/sh\necho hello')"

  rm -rf "$tmpdir"
}

@test "get_random_pass - default length 14" {
  run get_random_pass
  assert_success
  [ "${#output}" -eq 14 ]
}

@test "get_random_pass - custom length" {
  run get_random_pass 20
  assert_success
  [ "${#output}" -eq 20 ]
}

@test "get_random_pass - safe mode is alphanumeric only" {
  run get_random_pass 32 safe
  assert_success
  assert_output --regexp '^[A-Za-z0-9]+$'
}

@test "get_random_pass - safe mode length" {
  run get_random_pass 16 safe
  assert_success
  [ "${#output}" -eq 16 ]
}

@test "reverse_list - three items" {
  run reverse_list one two three
  assert_output "three two one "
}

@test "reverse_list - single item" {
  run reverse_list one
  assert_output "one "
}

@test "reverse_list - two items" {
  run reverse_list a b
  assert_output "b a "
}
