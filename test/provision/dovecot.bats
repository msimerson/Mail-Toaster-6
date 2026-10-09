#!/usr/bin/env bats
# Functional tests for provision/dovecot.sh

setup_file() {
  export DOVECOT_FNS="$BATS_FILE_TMPDIR/dovecot_fns_only.sh"
  sed '/^base_snapshot_exists/,$d' \
    "$BATS_TEST_DIRNAME/../../provision/dovecot.sh" > "$DOVECOT_FNS"
}

setup() {
  load '../test_helper/load'

  export MT6_TEST_ENV=1
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export ZFS_DATA_MNT="$STAGE_MNT/data"
  export ZFS_JAIL_MNT="$BATS_TEST_TMPDIR/jails"
  export TOASTER_HOSTNAME="mail.example.com"
  export TOASTER_MAIL_DOMAIN="example.com"

  LOCAL_CONF="$ZFS_DATA_MNT/dovecot/etc/local.conf"
  mkdir -p "$(dirname "$LOCAL_CONF")"

  # shellcheck source=/dev/null
  . "$DOVECOT_FNS"

  # the pair must exist before local.conf names it
  install_jail_tls_pair() { cp "$LOCAL_CONF" "$BATS_TEST_TMPDIR/at_install"; }
}

local_conf() {
  cat > "$LOCAL_CONF" <<EOF2
# default TLS certificate (no SNI)
ssl_cert = </data/etc/tls/certs/$1.pem
ssl_key = </data/etc/tls/private/$1.pem

#local_name example.com {
#  ssl_cert = </data/etc/tls/certs/example.com.pem
#}
EOF2
}

@test "configure_tls_certs names a new install's cert for TOASTER_HOSTNAME" {
  local_conf dovecot
  configure_tls_certs

  run grep '^ssl_' "$LOCAL_CONF"
  assert_line "ssl_cert = </data/etc/tls/certs/mail.example.com.pem"
  assert_line "ssl_key = </data/etc/tls/private/mail.example.com.pem"
  run grep -c 'certs/dovecot.pem' "$BATS_TEST_TMPDIR/at_install"
  assert_output 1
}

@test "configure_tls_certs repoints a cert named for TOASTER_MAIL_DOMAIN" {
  local_conf example.com
  configure_tls_certs

  run grep '^ssl_' "$LOCAL_CONF"
  assert_line "ssl_cert = </data/etc/tls/certs/mail.example.com.pem"
  assert_line "ssl_key = </data/etc/tls/private/mail.example.com.pem"
}

@test "configure_tls_certs leaves indented SNI blocks alone" {
  local_conf example.com
  configure_tls_certs

  run cat "$LOCAL_CONF"
  assert_line "#  ssl_cert = </data/etc/tls/certs/example.com.pem"
}

@test "configure_tls_certs leaves an admin's cert choice alone" {
  local_conf imap.example.org
  configure_tls_certs

  run grep '^ssl_cert' "$LOCAL_CONF"
  assert_output "ssl_cert = </data/etc/tls/certs/imap.example.org.pem"
}

@test "configure_tls_certs is a no-op when hostname is the mail domain" {
  export TOASTER_HOSTNAME="example.com"
  local_conf example.com
  cp "$LOCAL_CONF" "$BATS_TEST_TMPDIR/before"
  configure_tls_certs

  run diff "$BATS_TEST_TMPDIR/before" "$LOCAL_CONF"
  assert_success
}

@test "configure_tls_certs comments ssl_cert out of 10-ssl.conf" {
  local_conf mail.example.com
  local _sslconf="$ZFS_DATA_MNT/dovecot/etc/conf.d/10-ssl.conf"
  mkdir -p "$(dirname "$_sslconf")"
  printf 'ssl_cert = </etc/ssl/certs/dovecot.pem\nssl_key = </etc/ssl/private/dovecot.pem\n' > "$_sslconf"
  configure_tls_certs

  run cat "$_sslconf"
  assert_line "#ssl_cert = </etc/ssl/certs/dovecot.pem"
  assert_line "#ssl_key = </etc/ssl/private/dovecot.pem"
}
