#!/usr/bin/env bats

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  load '../../include/nginx.sh'
}

mt6-include() { :; }
tell_status() { :; }

# contains() - pure string membership test

@test "contains - substring found" {
  run contains "hello world" "world"
  assert_success
}

@test "contains - substring not found" {
  run contains "hello world" "foo"
  assert_failure
}

@test "contains - exact match" {
  run contains "hello" "hello"
  assert_success
}

@test "contains - prefix match" {
  run contains "hello world" "hello"
  assert_success
}

@test "contains - suffix match" {
  run contains "hello world" "world"
  assert_success
}

@test "contains - case sensitive (no match)" {
  run contains "Hello World" "hello"
  assert_failure
}

@test "contains - substring longer than string" {
  run contains "hi" "hello"
  assert_failure
}

@test "contains - listen keyword present" {
  run contains "listen 80; server_name example.com;" "listen"
  assert_success
}

@test "contains - listen keyword absent" {
  run contains "server_name example.com;" "listen"
  assert_failure
}

# configure_nginx_server_d - creates nginx server block config

@test "configure_nginx_server_d - creates config file" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export PUBLIC_IP6=""
  export _NGINX_SERVER="server_name test.example.com;"

  configure_nginx_server_d myjail

  [ -f "$tmpdir/myjail/etc/nginx/server.d/myjail.conf" ]

  rm -rf "$tmpdir"
}

@test "configure_nginx_server_d - uses custom server name" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export PUBLIC_IP6=""
  export _NGINX_SERVER="server_name custom.example.com;"

  configure_nginx_server_d myjail myserver

  [ -f "$tmpdir/myjail/etc/nginx/server.d/myserver.conf" ]

  rm -rf "$tmpdir"
}

@test "configure_nginx_server_d - contains listen 80" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export PUBLIC_IP6=""
  export _NGINX_SERVER="server_name test.example.com;"

  configure_nginx_server_d myjail

  run grep "listen" "$tmpdir/myjail/etc/nginx/server.d/myjail.conf"
  assert_success
  assert_output --partial "80"

  rm -rf "$tmpdir"
}

@test "configure_nginx_server_d - adds IPv6 listen when PUBLIC_IP6 set" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export PUBLIC_IP6="2001:db8::1"
  export _NGINX_SERVER="server_name test.example.com;"

  configure_nginx_server_d myjail

  run grep "\[::\]" "$tmpdir/myjail/etc/nginx/server.d/myjail.conf"
  assert_success

  rm -rf "$tmpdir"
}

@test "configure_nginx_server_d - preserves existing config" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export PUBLIC_IP6=""
  export _NGINX_SERVER="server_name test.example.com;"

  mkdir -p "$tmpdir/myjail/etc/nginx/server.d"
  echo "original content" > "$tmpdir/myjail/etc/nginx/server.d/myjail.conf"

  configure_nginx_server_d myjail

  run cat "$tmpdir/myjail/etc/nginx/server.d/myjail.conf"
  assert_output "original content"

  rm -rf "$tmpdir"
}
