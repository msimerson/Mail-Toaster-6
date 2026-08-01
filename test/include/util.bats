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

@test "freebsd_major - root dir chroots and extracts major version" {
  chroot() { echo "14.2-RELEASE-p1"; }
  run freebsd_major /stage
  assert_success
  assert_output "14"
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

@test "store_config - shadow copy is not world readable" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/secret.conf"

  echo "password=hunter2" | store_config "$tmpfile"

  run _file_mode "$tmpfile.mt6"
  assert_output "600"

  rm -rf "$tmpdir"
}

@test "store_config - shadow is tightened on every operation" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/secret.conf"

  echo "first" | store_config "$tmpfile"
  echo "second" | store_config "$tmpfile" "append"
  run _file_mode "$tmpfile.mt6"
  assert_output "600"

  echo "third" | store_config "$tmpfile" "overwrite"
  run _file_mode "$tmpfile.mt6"
  assert_output "600"

  rm -rf "$tmpdir"
}

# The shadow is the source of the cp that installs $1, so a shadow left at 600
# by an earlier run must not drag the installed config down with it.
@test "store_config - a tightened shadow does not tighten a reinstalled file" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  umask 022
  echo "one" | store_config "$tmpfile"
  local _first; _first=$(_file_mode "$tmpfile")

  rm -f "$tmpfile"          # shadow survives at 600
  echo "two" | store_config "$tmpfile"

  run _file_mode "$tmpfile"
  assert_output "$_first"

  rm -rf "$tmpdir"
}

@test "store_config - update replaces a file matching the previous shadow" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "v1" | store_config "$tmpfile"          # installs v1, shadow = v1
  echo "v2" | store_config "$tmpfile" "update" # untouched since, so take v2

  run cat "$tmpfile"
  assert_output "v2"

  rm -rf "$tmpdir"
}

@test "store_config - update preserves a file the admin edited" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "v1" | store_config "$tmpfile"
  echo "hand edited" > "$tmpfile"
  echo "v2" | store_config "$tmpfile" "update"

  run cat "$tmpfile"
  assert_output "hand edited"

  rm -rf "$tmpdir"
}

# An edit that is later reverted is not a customization worth keeping.
@test "store_config - update resumes after an edit is reverted" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "v1" | store_config "$tmpfile"
  echo "hand edited" > "$tmpfile"
  echo "v2" | store_config "$tmpfile" "update"   # preserved
  run cat "$tmpfile"
  assert_output "hand edited"

  echo "v2" > "$tmpfile"                          # admin reverts to our version
  echo "v3" | store_config "$tmpfile" "update"
  run cat "$tmpfile"
  assert_output "v3"

  rm -rf "$tmpdir"
}

# A pre-existing file with no shadow predates us; we have no idea if it is ours.
@test "store_config - update preserves a file with no shadow" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "someone elses" > "$tmpfile"
  echo "v1" | store_config "$tmpfile" "update"

  run cat "$tmpfile"
  assert_output "someone elses"

  rm -rf "$tmpdir"
}

@test "store_config - update installs when the file is absent" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "v1" | store_config "$tmpfile" "update"

  run cat "$tmpfile"
  assert_output "v1"

  rm -rf "$tmpdir"
}

@test "store_config - update keeps the mode the admin set" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "v1" | store_config "$tmpfile"
  chmod 640 "$tmpfile"
  echo "v2" | store_config "$tmpfile" "update"

  run _file_mode "$tmpfile"
  assert_output "640"

  rm -rf "$tmpdir"
}

@test "store_config - append never updates in place" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "first" | store_config "$tmpfile"
  echo "second" | store_config "$tmpfile" "append"

  run cat "$tmpfile"
  assert_line --index 0 "first"
  assert_line --index 1 "second"

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
