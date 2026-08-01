#!/usr/bin/env bats
# Functional tests for provision/roundcube.sh

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export STAGE_MNT; STAGE_MNT=$(mktemp -d /tmp/mt6rcXXXXXX)
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  export ZFS_DATA_MNT="$STAGE_MNT/data"
  export ZFS_JAIL_MNT="$STAGE_MNT/jails"
  export ZFS_DATA_VOL="zroot${ZFS_DATA_MNT}"
  export ZFS_JAIL_VOL="zroot${ZFS_JAIL_MNT}"

  NGINX_CONF="$ZFS_DATA_MNT/roundcube/etc/nginx/server.d/roundcube.conf"
  mkdir -p "$(dirname "$NGINX_CONF")"

  # source the function definitions only; the execution block at the bottom
  # provisions a jail
  sed '/^tell_settings ROUNDCUBE$/,$d' "$BATS_TEST_DIRNAME/../../provision/roundcube.sh" \
    > "$STAGE_MNT/roundcube-functions.sh"
  # shellcheck source=/dev/null
  . "$STAGE_MNT/roundcube-functions.sh"
}

teardown() {
  rm -rf "$STAGE_MNT"
}

@test "migrate_roundcube_nginx_conf retires a pre-1.7 server block" {
  echo "root /usr/local/www/roundcube;" > "$NGINX_CONF"

  migrate_roundcube_nginx_conf

  [ ! -f "$NGINX_CONF" ]
  run cat "$NGINX_CONF.pre-1.7"
  assert_output --partial "root /usr/local/www/roundcube;"
}

@test "migrate_roundcube_nginx_conf keeps a 1.7 server block" {
  echo "root /usr/local/www/roundcube/public_html;" > "$NGINX_CONF"

  migrate_roundcube_nginx_conf

  [ -f "$NGINX_CONF" ]
  [ ! -f "$NGINX_CONF.pre-1.7" ]
}

@test "migrate_roundcube_nginx_conf is a no-op on a new install" {
  run migrate_roundcube_nginx_conf

  assert_success
  [ ! -f "$NGINX_CONF.pre-1.7" ]
}

@test "roundcube_init_db posts to the 1.7 installer entry point" {
  pkg() { :; }
  start_roundcube() { :; }
  curl() { echo "$*" > "$STAGE_MNT/curl.args"; }

  roundcube_init_db

  run cat "$STAGE_MNT/curl.args"
  assert_output --partial "/installer.php?_step=3"
  # installer/ moved outside the document root in 1.7
  refute_output --partial "/installer/index.php"
}

@test "roundcube_init_db fails loudly when the installer 404s" {
  pkg() { :; }
  start_roundcube() { :; }
  curl() { return 22; }
  # the stub's fatal_err does not exit; mail-toaster.sh's does
  fatal_err() { echo "FATAL: $1"; exit 1; }

  run roundcube_init_db

  assert_failure
  assert_output --partial "installer did not respond"
}

@test "update_roundcube_db applies pending schema updates" {
  stage_exec() { echo "$*" > "$STAGE_MNT/updatedb.args"; }

  update_roundcube_db

  run cat "$STAGE_MNT/updatedb.args"
  assert_output --partial "bin/updatedb.sh"
  assert_output --partial "--package=roundcube"
  assert_output --partial "--dir=/usr/local/www/roundcube/SQL"
}

@test "update_roundcube_db warns instead of aborting the provision" {
  stage_exec() { return 1; }
  tell_status() { echo "$1"; }

  run update_roundcube_db

  assert_success
  assert_output --partial "schema update failed"
  assert_output --partial "--version="
}
