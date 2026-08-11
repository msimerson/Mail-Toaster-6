#!/usr/bin/env bats

setup() {
  load '../test_helper/load'
  load '../../include/nginx.sh'
}

mt6-include() { :; }
tell_status() { :; }

get_public_ip4() { :; }
get_public_ip6() { :; }

# faithful copy of include/jail.sh get_jail_data
get_jail_data() { echo "$ZFS_DATA_MNT/$1"; }

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

# nginx_listen() - both families, absent one commented out

@test "nginx_listen - both families present" {
  export PUBLIC_IP4="192.0.2.1"
  export PUBLIC_IP6="2001:db8::1"

  run nginx_listen 80
  assert_line --index 0 --regexp '^[[:space:]]+listen[[:space:]]+80;$'
  assert_line --index 1 --regexp '^[[:space:]]+listen  \[::\]:80;$'
}

@test "nginx_listen - IPv6 absent is commented out" {
  export PUBLIC_IP4="192.0.2.1"
  export PUBLIC_IP6=""

  run nginx_listen 80
  assert_line --index 0 --regexp '^[[:space:]]+listen[[:space:]]+80;$'
  assert_line --index 1 --regexp '^[[:space:]]+#listen  \[::\]:80;$'
}

@test "nginx_listen - IPv4 absent is commented out" {
  export PUBLIC_IP4=""
  export PUBLIC_IP6="2001:db8::1"

  run nginx_listen 80
  assert_line --index 0 --regexp '^[[:space:]]+#listen[[:space:]]+80;$'
  assert_line --index 1 --regexp '^[[:space:]]+listen  \[::\]:80;$'
}

@test "nginx_listen - defaults to port 80" {
  export PUBLIC_IP4="192.0.2.1"
  export PUBLIC_IP6="2001:db8::1"

  run nginx_listen
  assert_output --partial "listen       80;"
  assert_output --partial "listen  [::]:80;"
}

@test "nginx_listen - appends options to both families" {
  export PUBLIC_IP4="192.0.2.1"
  export PUBLIC_IP6=""

  run nginx_listen 443 ssl
  assert_output --partial "listen       443 ssl;"
  assert_output --partial "#listen  [::]:443 ssl;"
}

@test "nginx_listen - both families absent are both commented out" {
  export PUBLIC_IP4=""
  export PUBLIC_IP6=""

  run nginx_listen 80
  assert_line --index 0 --regexp '^[[:space:]]+#listen[[:space:]]+80;$'
  assert_line --index 1 --regexp '^[[:space:]]+#listen  \[::\]:80;$'
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
  export PUBLIC_IP4="192.0.2.1"
  export PUBLIC_IP6=""
  export _NGINX_SERVER="server_name test.example.com;"

  configure_nginx_server_d myjail

  run grep "listen" "$tmpdir/myjail/etc/nginx/server.d/myjail.conf"
  assert_success
  assert_output --partial "80"

  rm -rf "$tmpdir"
}

@test "configure_nginx_server_d - comments out IPv6 listen when PUBLIC_IP6 empty" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export PUBLIC_IP4="192.0.2.1"
  export PUBLIC_IP6=""
  export _NGINX_SERVER="server_name test.example.com;"

  configure_nginx_server_d myjail

  run grep "\[::\]:80" "$tmpdir/myjail/etc/nginx/server.d/myjail.conf"
  assert_success
  assert_output --partial "#listen"

  rm -rf "$tmpdir"
}

@test "configure_nginx_server_d - enables IPv6 listen when PUBLIC_IP6 set" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export PUBLIC_IP4="192.0.2.1"
  export PUBLIC_IP6="2001:db8::1"
  export _NGINX_SERVER="server_name test.example.com;"

  configure_nginx_server_d myjail

  run grep "\[::\]:80" "$tmpdir/myjail/etc/nginx/server.d/myjail.conf"
  assert_success
  refute_output --partial "#"

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
  get_jail_ip4() { echo "172.16.15.1"; }
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
