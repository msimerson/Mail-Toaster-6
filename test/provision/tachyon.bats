#!/usr/bin/env bats
# Functional tests for provision/tachyon.sh

setup_file() {
  export TACHYON_FNS="$BATS_FILE_TMPDIR/tachyon_fns_only.sh"
  awk '/^base_snapshot_exists/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/tachyon.sh" > "$TACHYON_FNS"
}

setup() {
  load '../test_helper/load'

  export MT6_TEST_ENV=1
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  unset TACHYON_VERSION

  mkdir -p "$STAGE_MNT/tmp" "$ZFS_DATA_MNT/tachyon"

  # shellcheck source=/dev/null
  . "$TACHYON_FNS"
}

make_release_tarball() {
  local _src="$BATS_TEST_TMPDIR/release"
  mkdir -p "$_src/tachyon/v/9.9.9" "$_src/data"
  echo "<?php" > "$_src/index.php"
  echo "<?php" > "$_src/tachyon/v/9.9.9/include.php"
  echo "deny" > "$_src/data/.htaccess"
  tar -cz -C "$_src" -f "$BATS_TEST_TMPDIR/tachyon.tar.gz" .
}

@test "tachyon - declares no jail extras" {
  assert_equal "$JAIL_START_EXTRA" ""
  assert_equal "$JAIL_CONF_EXTRA" ""
  assert_equal "$JAIL_FSTAB" ""
}

@test "tachyon_release_url defaults to the latest release" {
  run tachyon_release_url
  assert_output "https://github.com/kimusan/Tachyon/releases/latest/download/tachyon-latest.tar.gz"
}

@test "tachyon_release_url pins TACHYON_VERSION" {
  TACHYON_VERSION="4.3.1"
  run tachyon_release_url
  assert_output "https://github.com/kimusan/Tachyon/releases/download/v4.3.1/tachyon-4.3.1.tar.gz"
}

@test "install_tachyon unpacks the release into the web root" {
  make_release_tarball
  fetch() { cp "$BATS_TEST_TMPDIR/tachyon.tar.gz" "$2"; }

  install_tachyon

  [ -f "$STAGE_MNT/usr/local/www/tachyon/index.php" ]
  [ -f "$STAGE_MNT/usr/local/www/tachyon/tachyon/v/9.9.9/include.php" ]
  [ ! -e "$STAGE_MNT/usr/local/www/tachyon/data" ]
  [ ! -e "$STAGE_MNT/tmp/tachyon.tar.gz" ]
}

@test "install_tachyon aborts when the download fails" {
  run bash -c ". '$TACHYON_FNS'; fetch() { return 1; }; install_tachyon; echo unreachable"

  assert_failure
  refute_output --partial "unreachable"
  refute_output --partial "not a valid identifier"
}

@test "set_data_path points Tachyon at the persistent /data" {
  set_data_path

  run cat "$STAGE_MNT/usr/local/www/tachyon/include.php"
  assert_output --partial "define('APP_DATA_FOLDER_PATH', '/data/');"
}

@test "import_snappymail_data copies _data_ and SALT.php, not jail config" {
  local _snappy="$ZFS_DATA_MNT/snappymail"
  mkdir -p "$_snappy/_data_/_default_/configs" "$_snappy/etc/nginx/server.d"
  echo "admin_login = x" > "$_snappy/_data_/_default_/configs/application.ini"
  echo "<?php //salt" > "$_snappy/SALT.php"
  echo "server {}" > "$_snappy/etc/nginx/server.d/snappymail.conf"

  import_snappymail_data

  run cat "$ZFS_DATA_MNT/tachyon/_data_/_default_/configs/application.ini"
  assert_output "admin_login = x"
  run cat "$ZFS_DATA_MNT/tachyon/SALT.php"
  assert_output "<?php //salt"
  [ ! -e "$ZFS_DATA_MNT/tachyon/etc/nginx/server.d/snappymail.conf" ]
}

@test "import_snappymail_data leaves existing tachyon data alone" {
  mkdir -p "$ZFS_DATA_MNT/snappymail/_data_" "$ZFS_DATA_MNT/tachyon/_data_"
  echo "snappy" > "$ZFS_DATA_MNT/snappymail/SALT.php"
  echo "tachyon" > "$ZFS_DATA_MNT/tachyon/SALT.php"

  import_snappymail_data

  run cat "$ZFS_DATA_MNT/tachyon/SALT.php"
  assert_output "tachyon"
}

@test "import_snappymail_data is a no-op without snappymail" {
  run import_snappymail_data

  assert_success
  [ ! -e "$ZFS_DATA_MNT/tachyon/_data_" ]
}

@test "install_default_json points at dovecot and haraka" {
  install_default_json

  run cat "$ZFS_DATA_MNT/tachyon/_data_/_default_/domains/default.json"
  assert_output --partial '"host": "dovecot"'
  assert_output --partial '"host": "haraka"'
}

@test "install_default_json keeps an admin-edited domain" {
  local _json="$ZFS_DATA_MNT/tachyon/_data_/_default_/domains/default.json"
  mkdir -p "$(dirname "$_json")"
  echo '{"name": "edited"}' > "$_json"

  install_default_json

  run cat "$_json"
  assert_output '{"name": "edited"}'
}

@test "test_tachyon passes when the login page loads" {
  fetch() { echo '<script src="/tachyon/tachyon/v/4.3.1/static/js/boot.js">'; }

  run test_tachyon

  assert_success
}

@test "test_tachyon fails when the login page does not load" {
  fetch() { echo '[105] Missing tachyon'; }
  fatal_err() { echo "FATAL: $1"; exit 1; }

  run test_tachyon

  assert_failure
  assert_output --partial "did not serve its login page"
}

@test "configure_nginx_server routes /tachyon/ to PHP with PATH_INFO" {
  configure_nginx_server_d() { echo "$_NGINX_SERVER" > "$STAGE_MNT/nginx.conf"; }

  configure_nginx_server

  run cat "$STAGE_MNT/nginx.conf"
  assert_output --partial "root   /usr/local/www;"
  assert_output --partial "location /tachyon/ {"
  assert_output --partial 'PATH_INFO        $fastcgi_path_info'
}
