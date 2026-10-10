#!/usr/bin/env bats

setup() {
  load '../test_helper/load'
  load '../../include/util.sh'
  load '../../include/tls.sh'

  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  export TOASTER_HOSTNAME="mail.example.com"
  export TOASTER_MAIL_DOMAIN="example.com"

  HOST_SSL="$BATS_TEST_TMPDIR/host_ssl"
  mkdir -p "$HOST_SSL/certs" "$HOST_SSL/private"
  echo host-crt > "$HOST_SSL/certs/server.crt"
  echo host-key > "$HOST_SSL/private/server.key"
  HOST_TLS_CRT="$HOST_SSL/certs/server.crt"
  HOST_TLS_KEY="$HOST_SSL/private/server.key"

  ETC="$ZFS_DATA_MNT/postfix/etc"
  TLS="$ETC/tls"
  CRT="$TLS/certs/mail.example.com.pem"
  KEY="$TLS/private/mail.example.com.pem"
  OLD_CRT="$TLS/certs/example.com.pem"
  OLD_KEY="$TLS/private/example.com.pem"
}

tell_status() { :; }

# faithful copy of include/jail.sh get_jail_data
get_jail_data() { echo "$ZFS_DATA_MNT/$1"; }

@test "install_jail_tls_pair installs the host pair, named for TOASTER_HOSTNAME" {
  ( set -e; install_jail_tls_pair postfix )

  assert_equal "$(cat "$CRT")" host-crt
  assert_equal "$(cat "$KEY")" host-key
  assert [ ! -e "$OLD_CRT" ]
  assert_equal "$(_file_mode "$TLS/certs")" 755
  assert_equal "$(_file_mode "$TLS/private")" 700
  assert_equal "$(_file_mode "$CRT")" 644
  assert_equal "$(_file_mode "$KEY")" 600
}

@test "install_jail_tls_pair leaves an installed pair alone" {
  mkdir -p "$TLS/certs" "$TLS/private"
  echo le-crt > "$CRT"
  echo le-key > "$KEY"

  ( set -e; install_jail_tls_pair postfix )

  assert_equal "$(cat "$CRT")" le-crt
  assert_equal "$(cat "$KEY")" le-key
}

@test "install_jail_tls_pair replaces a cert that has no key" {
  mkdir -p "$TLS/certs"
  echo stray-crt > "$CRT"

  ( set -e; install_jail_tls_pair postfix )

  assert_equal "$(cat "$CRT")" host-crt
  assert_equal "$(cat "$KEY")" host-key
  assert_equal "$(cat "$CRT.orphan")" stray-crt
}

@test "install_jail_tls_pair replaces a key that has no cert" {
  mkdir -p "$TLS/private"
  echo stray-key > "$KEY"

  ( set -e; install_jail_tls_pair postfix )

  assert_equal "$(cat "$CRT")" host-crt
  assert_equal "$(cat "$KEY")" host-key
  assert_equal "$(cat "$KEY.orphan")" stray-key
}

@test "install_jail_tls_pair copies a pair named for TOASTER_MAIL_DOMAIN" {
  mkdir -p "$TLS/certs" "$TLS/private"
  echo old-crt > "$OLD_CRT"
  echo old-key > "$OLD_KEY"

  ( set -e; install_jail_tls_pair postfix )

  assert_equal "$(cat "$CRT")" old-crt
  assert_equal "$(cat "$KEY")" old-key
  assert_equal "$(_file_mode "$KEY")" 600
  # the running jail still reads these until it is replaced
  assert [ -f "$OLD_CRT" ]
  assert [ -f "$OLD_KEY" ]
}

@test "install_jail_tls_pair ignores half a TOASTER_MAIL_DOMAIN pair" {
  mkdir -p "$TLS/certs"
  echo old-crt > "$OLD_CRT"

  ( set -e; install_jail_tls_pair postfix )

  assert_equal "$(cat "$CRT")" host-crt
  assert_equal "$(cat "$KEY")" host-key
}

@test "install_jail_tls_pair works when hostname and mail domain match" {
  export TOASTER_HOSTNAME="example.com"

  ( set -e; install_jail_tls_pair postfix )

  assert_equal "$(cat "$OLD_CRT")" host-crt
  assert_equal "$(cat "$OLD_KEY")" host-key
}

@test "install_jail_tls_pair tightens a pre-existing private dir" {
  mkdir -p -m 0755 "$TLS/private"

  ( set -e; install_jail_tls_pair postfix )

  assert_equal "$(_file_mode "$TLS/private")" 700
}

@test "install_jail_tls_pair renames a legacy ssl dir" {
  mkdir -p "$ETC/ssl/certs" "$ETC/ssl/private"
  echo old-crt > "$ETC/ssl/certs/mail.example.com.pem"
  echo old-key > "$ETC/ssl/private/mail.example.com.pem"

  ( set -e; install_jail_tls_pair postfix )

  assert [ ! -d "$ETC/ssl" ]
  assert_equal "$(cat "$CRT")" old-crt
  assert_equal "$(cat "$KEY")" old-key
}

@test "install_jail_tls_pair uses the named jail's data dir" {
  ( set -e; install_jail_tls_pair dovecot )

  assert [ -f "$ZFS_DATA_MNT/dovecot/etc/tls/certs/mail.example.com.pem" ]
  assert [ ! -e "$TLS" ]
}

@test "install_tls_pem writes key then cert to one 0600 file" {
  local _pem="$BATS_TEST_TMPDIR/haproxy/etc/tls.d/mail.example.com.pem"

  ( set -e; install_tls_pem "$_pem" )

  assert_equal "$(cat "$_pem")" "$(printf 'host-key\nhost-crt')"
  assert_equal "$(_file_mode "$_pem")" 600
}

@test "install_tls_pem leaves an installed PEM alone" {
  local _pem="$BATS_TEST_TMPDIR/tls.d/mail.example.com.pem"
  mkdir -p "$(dirname "$_pem")"
  echo le-pem > "$_pem"

  ( set -e; install_tls_pem "$_pem" )

  assert_equal "$(cat "$_pem")" le-pem
}
