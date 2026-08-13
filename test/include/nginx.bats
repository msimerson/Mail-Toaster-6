#!/usr/bin/env bats

setup() {
  load '../test_helper/load'
  load '../../include/nginx.sh'
  # the real store_config: "update" is what carries a changed template onto a
  # rebuild, and a copy of it here would not prove that
  load '../../include/util.sh'
}

mt6-include() { :; }
tell_status() { :; }

get_public_ip4() { :; }
get_public_ip6() { :; }

# faithful copy of include/jail.sh jail_has_ip6
jail_has_ip6() { get_public_ip6; [ -n "${PUBLIC_IP6:-}" ]; }

# faithful copy of include/jail.sh get_jail_data
get_jail_data() { echo "$ZFS_DATA_MNT/$1"; }

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

# nginx_listen() - both families, IPv6 commented out when the jail has none

@test "nginx_listen - a jail with IPv6 listens on both families" {
  export PUBLIC_IP6="2001:db8::1"

  run nginx_listen 80
  assert_line --index 0 --regexp '^[[:space:]]+listen[[:space:]]+80;$'
  assert_line --index 1 --regexp '^[[:space:]]+listen  \[::\]:80;$'
}

@test "nginx_listen - a jail without IPv6 has that listen commented out" {
  export PUBLIC_IP6=""

  run nginx_listen 80
  assert_line --index 0 --regexp '^[[:space:]]+listen[[:space:]]+80;$'
  assert_line --index 1 --regexp '^[[:space:]]+#listen  \[::\]:80;$'
}

# Every jail has a private IPv4 address whatever the host has. Commenting this
# listen out left nginx bound to [::] only, where the haproxy backends and the
# bsd_cache DNS records could not reach it.
@test "nginx_listen - IPv4 listens with or without a public IPv4" {
  export PUBLIC_IP4="" PUBLIC_IP6="2001:db8::1"
  run nginx_listen 80
  assert_line --index 0 --regexp '^[[:space:]]+listen[[:space:]]+80;$'

  export PUBLIC_IP4="" PUBLIC_IP6=""
  run nginx_listen 80
  assert_line --index 0 --regexp '^[[:space:]]+listen[[:space:]]+80;$'
  assert_line --index 1 --regexp '^[[:space:]]+#listen  \[::\]:80;$'
}

@test "nginx_listen - defaults to port 80" {
  export PUBLIC_IP6="2001:db8::1"

  run nginx_listen
  assert_output --partial "listen       80;"
  assert_output --partial "listen  [::]:80;"
}

@test "nginx_listen - appends options to both families" {
  export PUBLIC_IP6=""

  run nginx_listen 443 ssl
  assert_output --partial "listen       443 ssl;"
  assert_output --partial "#listen  [::]:443 ssl;"
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

# --- a rebuild follows the host it is rebuilt on ---

# The listen directives are decided at build time. A toaster first built with
# no IPv6 has them commented out, and nothing but a rebuild can enable them.
@test "configure_nginx_server_d - a rebuild enables IPv6 once the host has it" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export _NGINX_SERVER="server_name test.example.com;"
  local _conf="$tmpdir/myjail/etc/nginx/server.d/myjail.conf"

  export PUBLIC_IP6=""
  configure_nginx_server_d myjail
  run grep "\[::\]:80" "$_conf"
  assert_output --partial "#listen"

  export PUBLIC_IP6="2001:db8::1"
  configure_nginx_server_d myjail
  run grep "\[::\]:80" "$_conf"
  assert_success
  refute_output --partial "#listen"

  rm -rf "$tmpdir"
}

@test "configure_nginx_server_d - a rebuild comments IPv6 out once the host loses it" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export _NGINX_SERVER="server_name test.example.com;"
  local _conf="$tmpdir/myjail/etc/nginx/server.d/myjail.conf"

  export PUBLIC_IP6="2001:db8::1"
  configure_nginx_server_d myjail

  export PUBLIC_IP6=""
  configure_nginx_server_d myjail
  run grep "\[::\]:80" "$_conf"
  assert_output --partial "#listen"

  rm -rf "$tmpdir"
}

# an admin who edited the server block keeps it, IPv6 or not
@test "configure_nginx_server_d - a rebuild leaves an edited config alone" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export _NGINX_SERVER="server_name test.example.com;"
  local _conf="$tmpdir/myjail/etc/nginx/server.d/myjail.conf"

  export PUBLIC_IP6=""
  configure_nginx_server_d myjail
  echo "# hand written" >> "$_conf"

  export PUBLIC_IP6="2001:db8::1"
  configure_nginx_server_d myjail

  run cat "$_conf"
  assert_output --partial "# hand written"
  # the shadow still shows what a pristine config would have held
  run grep "\[::\]:80" "$_conf.mt6"
  refute_output --partial "#listen"

  rm -rf "$tmpdir"
}
