#!/usr/bin/env bats

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  load '../../include/nginx.sh'
}

mt6-include() { :; }
tell_status() { :; }

# faithful copy of include/util.sh store_config: always writes <file>.mt6,
# installs the live file only when absent (or on overwrite/append)
store_config() {
  local _operation=${2:-""}
  [ -d "$(dirname "$1")" ] || mkdir -p "$(dirname "$1")"
  cat - > "$1.mt6"
  if [ ! -f "$1" ] || [ "$_operation" = "overwrite" ]; then
    cp "$1.mt6" "$1"
  elif [ "$_operation" = "append" ]; then
    cat "$1.mt6" >> "$1"
  fi
}

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

@test "configure_nginx_server_d - works when PUBLIC_IP6 is unset" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  unset PUBLIC_IP6
  export _NGINX_SERVER="server_name test.example.com;"

  configure_nginx_server_d myjail

  [ -f "$tmpdir/myjail/etc/nginx/server.d/myjail.conf" ]

  rm -rf "$tmpdir"
}

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

@test "configure_nginx_server_d - leaves .mt6 reference for preserved config" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export PUBLIC_IP6=""
  export _NGINX_SERVER="server_name test.example.com;"

  mkdir -p "$tmpdir/myjail/etc/nginx/server.d"
  echo "original content" > "$tmpdir/myjail/etc/nginx/server.d/myjail.conf"

  configure_nginx_server_d myjail

  run grep "test.example.com" "$tmpdir/myjail/etc/nginx/server.d/myjail.conf.mt6"
  assert_success

  rm -rf "$tmpdir"
}

@test "configure_nginx - leaves .mt6 reference for preserved config" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  stage_sysrc() { :; }
  get_jail_ip() { echo "172.16.15.1"; }
  get_jail_ip6() { echo "::1"; }

  mkdir -p "$tmpdir/myjail/etc/nginx"
  echo "original content" > "$tmpdir/myjail/etc/nginx/nginx.conf"

  configure_nginx myjail

  run cat "$tmpdir/myjail/etc/nginx/nginx.conf"
  assert_output "original content"

  run grep "worker_processes" "$tmpdir/myjail/etc/nginx/nginx.conf.mt6"
  assert_success

  rm -rf "$tmpdir"
}
