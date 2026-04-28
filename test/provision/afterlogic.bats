#!/usr/bin/env bats
# Functional tests for provision/afterlogic.sh

setup_file() {
  local _data="$BATS_FILE_TMPDIR/data"
  local _stage="$BATS_FILE_TMPDIR/stage"
  local _fns="$BATS_FILE_TMPDIR/afterlogic_fns_only.sh"

  awk '/^tell_settings AFTERLOGIC/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/afterlogic.sh" > "$_fns"

  export MT6_TEST_ENV=1
  export STAGE_MNT="$_stage"
  export ZFS_DATA_MNT="$_data"
  export ZFS_JAIL_MNT="$_data/jails"
  export TOASTER_MSA="haraka"
  export JAIL_NET_PREFIX="172.16.15"
  export JAIL_ORDERED_LIST="dns mysql vpopmail haraka webmail haproxy dovecot afterlogic"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  mkdir -p "$_data/afterlogic/etc/nginx" "$_stage/usr/local/www/afterlogic"

  # shellcheck source=/dev/null
  . "$_fns"
  # Source real nginx.sh so configure_nginx_server_d actually writes the conf file
  . "$BATS_TEST_DIRNAME/../../include/nginx.sh"
  configure_nginx_server
}

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export ZFS_DATA_MNT="$BATS_FILE_TMPDIR/data"
  export SERVER_CONF="$ZFS_DATA_MNT/afterlogic/etc/nginx/server.d/afterlogic.conf"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  # shellcheck source=/dev/null
  . "$BATS_FILE_TMPDIR/afterlogic_fns_only.sh"
}

# --- JAIL variable exports ---

@test "afterlogic - JAIL_START_EXTRA is empty" {
  assert_equal "$JAIL_START_EXTRA" ""
}

@test "afterlogic - JAIL_CONF_EXTRA is empty" {
  assert_equal "$JAIL_CONF_EXTRA" ""
}

@test "afterlogic - JAIL_FSTAB is empty" {
  assert_equal "$JAIL_FSTAB" ""
}

# --- nginx server config ---

@test "afterlogic nginx - server_name is afterlogic" {
  run grep 'server_name' "$SERVER_CONF"
  assert_output --partial 'afterlogic'
}

@test "afterlogic nginx - root points to afterlogic www dir" {
  run grep 'root' "$SERVER_CONF"
  assert_output --partial '/usr/local/www/afterlogic'
}

@test "afterlogic nginx - index.php is configured" {
  run grep 'index' "$SERVER_CONF"
  assert_output --partial 'index.php'
}

@test "afterlogic nginx - PHP-FPM fastcgi_pass configured" {
  run grep 'fastcgi_pass' "$SERVER_CONF"
  assert_output --partial 'php'
}

@test "afterlogic nginx - data directory is denied" {
  run grep -A1 'location.*data' "$SERVER_CONF"
  assert_output --partial 'deny all'
}

@test "afterlogic nginx - try_files configured for pretty URLs" {
  run grep 'try_files' "$SERVER_CONF"
  assert_output --partial 'index.php'
}

# --- security headers ---

@test "afterlogic nginx - X-Content-Type-Options nosniff" {
  run grep 'X-Content-Type-Options' "$SERVER_CONF"
  assert_output --partial 'nosniff'
}

@test "afterlogic nginx - X-Frame-Options SAMEORIGIN" {
  run grep 'X-Frame-Options' "$SERVER_CONF"
  assert_output --partial 'SAMEORIGIN'
}

@test "afterlogic nginx - X-XSS-Protection block mode" {
  run grep 'X-XSS-Protection' "$SERVER_CONF"
  assert_output --partial 'mode=block'
}

@test "afterlogic nginx - Strict-Transport-Security header" {
  run grep 'Strict-Transport-Security' "$SERVER_CONF"
  assert_output --partial 'max-age='
}

@test "afterlogic nginx - Referrer-Policy header" {
  run grep 'Referrer-Policy' "$SERVER_CONF"
  assert_success
}

@test "afterlogic nginx - security headers use always flag" {
  run grep -c 'always;' "$SERVER_CONF"
  assert [ "$output" -ge 5 ]
}
