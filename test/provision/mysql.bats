#!/usr/bin/env bats
# Functional tests for provision/mysql.sh
#
# Performance design (matches dns.bats pattern):
# - setup_file() runs ONCE: sources the full mysql.sh (execution block included),
#   and saves the resulting STAGE_MNT tree + stripped function-only script.
# - setup() runs per-test (fast): copies cached STAGE_MNT and sources only the
#   function definitions (no execution block, no openssl, no stage side-effects).
#
# Pre-requisites for setup_file:
#   - STAGE_MNT/usr/local/etc/mysql/my.cnf   (configure_mysql sed target)
#   - STAGE_MNT/root/                         (write_pass_to_conf creates .my.cnf)
#   - ZFS_DATA_MNT/mysql/db/{private,public}_key.pem  (dummy — skips openssl calls)
#   - CWD set to BATS_FILE_TMPDIR             (write_pass_to_conf appends to
#                                              mail-toaster.conf safely)

setup_file() {
  local _stage="$BATS_FILE_TMPDIR/stage"
  local _data="$BATS_FILE_TMPDIR/data"
  local _fns="$BATS_FILE_TMPDIR/mysql_fns_only.sh"

  # Strip the execution block so setup() can source function definitions only.
  awk '/^if \[.*TOASTER_MYSQL/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/mysql.sh" > "$_fns"

  export MT6_TEST_ENV=1
  export STAGE_MNT="$_stage"
  export ZFS_DATA_MNT="$_data"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  # Pre-create files needed by the execution block.
  mkdir -p "$_stage/usr/local/etc/mysql"
  mkdir -p "$_stage/usr/local/etc/newsyslog.conf.d"
  mkdir -p "$_stage/data/etc"
  mkdir -p "$_stage/root"
  mkdir -p "$_data/mysql/db"

  cat > "$_stage/usr/local/etc/mysql/my.cnf" <<'EOF'
[mysqld]
datadir                         = /var/db/mysql
innodb_buffer_pool_size         = 1G
EOF

  # store_config stub discards content, so pre-create extra.cnf so that
  # configure_mysql_ram can append to it.
  touch "$_stage/data/etc/extra.cnf"

  # Dummy key files so configure_mysql_keys skips the openssl calls.
  touch "$_data/mysql/db/private_key.pem"
  touch "$_data/mysql/db/public_key.pem"

  # Change to tmpdir so write_pass_to_conf writes mail-toaster.conf here
  # instead of the repository root.
  cd "$BATS_FILE_TMPDIR" || exit 1

  # Source the full provision script once (execution block runs here).
  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../provision/mysql.sh"
}

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export ZFS_DATA_MNT="$BATS_FILE_TMPDIR/data"

  # Fresh per-test STAGE_MNT copied from the cached template (fast).
  export STAGE_MNT; STAGE_MNT=$(mktemp -d)
  cp -r "$BATS_FILE_TMPDIR/stage/." "$STAGE_MNT/"

  # Source function definitions only (no execution block).
  # shellcheck source=/dev/null
  . "$BATS_FILE_TMPDIR/mysql_fns_only.sh"
}

teardown() {
  rm -rf "$STAGE_MNT"
}

# --- JAIL variable exports ---

@test "mysql - JAIL_START_EXTRA is empty" {
  assert_equal "$JAIL_START_EXTRA" ""
}

@test "mysql - JAIL_CONF_EXTRA is empty" {
  assert_equal "$JAIL_CONF_EXTRA" ""
}

@test "mysql - JAIL_FSTAB is empty" {
  assert_equal "$JAIL_FSTAB" ""
}

# --- Function existence ---

@test "mysql - defines install_db_server" {
  run type install_db_server
  assert_success
}

@test "mysql - defines install_mysql" {
  run type install_mysql
  assert_success
}

@test "mysql - defines install_mariadb" {
  run type install_mariadb
  assert_success
}

@test "mysql - defines configure_mysql" {
  run type configure_mysql
  assert_success
}

@test "mysql - defines start_mysql" {
  run type start_mysql
  assert_success
}

@test "mysql - defines test_mysql" {
  run type test_mysql
  assert_success
}

@test "mysql - defines write_pass_to_conf" {
  run type write_pass_to_conf
  assert_success
}

@test "mysql - defines configure_mysql_keys" {
  run type configure_mysql_keys
  assert_success
}

@test "mysql - defines configure_mysql_root_password" {
  run type configure_mysql_root_password
  assert_success
}

@test "mysql - defines migrate_mysql_dbs" {
  run type migrate_mysql_dbs
  assert_success
}

# --- configure_mysql outcomes (verified against the post-setup_file my.cnf) ---

@test "mysql - configure rewrites datadir from /var/db/mysql to /data/db" {
  run grep "datadir" "$STAGE_MNT/usr/local/etc/mysql/my.cnf"
  assert_success
  assert_output --partial "/data/db"
  refute_output --partial "/var/db/mysql"
}

@test "mysql - configure writes extra.cnf with innodb settings" {
  mkdir -p "$STAGE_MNT/data/etc"
  store_config() {
    local _file="$1"
    mkdir -p "$(dirname "$_file")"
    cat - > "$_file"
  }
  configure_mysql
  run grep "innodb_file_per_table" "$STAGE_MNT/data/etc/extra.cnf"
  assert_success
}

@test "mysql - configure writes newsyslog rotation config" {
  mkdir -p "$STAGE_MNT/data/etc" "$STAGE_MNT/usr/local/etc/newsyslog.conf.d"
  store_config() {
    local _file="$1"
    mkdir -p "$(dirname "$_file")"
    cat - > "$_file"
  }
  configure_mysql
  [ -f "$STAGE_MNT/usr/local/etc/newsyslog.conf.d/mysql.conf" ]
}

@test "mysql - configure enables mysql service via sysrc" {
  stage_sysrc() { echo "SYSRC:$*"; }
  run configure_mysql
  assert_success
  assert_output --partial "SYSRC:mysql_enable=YES"
}

@test "mysql - configure sets mysql_dbdir via sysrc" {
  stage_sysrc() { echo "SYSRC:$*"; }
  run configure_mysql
  assert_success
  assert_output --partial "SYSRC:mysql_dbdir=/data/db"
}

# --- install_mysql / install_mariadb behavior ---

@test "mysql - install_mysql installs mysql80-server package" {
  stage_pkg_install() { echo "PKG:$*"; }
  run install_mysql
  assert_success
  assert_output --partial "PKG:mysql80-server"
}

@test "mysql - install_mariadb installs mariadb package" {
  stage_pkg_install() { echo "PKG:$*"; }
  run install_mariadb
  assert_success
  assert_output --partial "PKG:mariadb"
}

@test "mysql - install_db_server installs mysql when TOASTER_MARIADB is unset" {
  export TOASTER_MARIADB=""
  mkdir -p "$STAGE_MNT/data/etc" "$STAGE_MNT/data/db"
  stage_pkg_install() { echo "PKG:$*"; }
  run install_db_server
  assert_success
  assert_output --partial "PKG:mysql"
}

@test "mysql - install_db_server installs mariadb when TOASTER_MARIADB=1" {
  export TOASTER_MARIADB="1"
  mkdir -p "$STAGE_MNT/data/etc" "$STAGE_MNT/data/db"
  stage_pkg_install() { echo "PKG:$*"; }
  run install_db_server
  assert_success
  assert_output --partial "PKG:mariadb"
}

# --- start_mysql behavior ---

@test "mysql - start calls service mysql-server start" {
  stage_exec()  { echo "EXEC:$*"; }
  configure_mysql_root_password() { :; }
  configure_mysql_keys() { :; }
  run start_mysql
  assert_success
  assert_output --partial "EXEC:service mysql-server start"
}

# --- test_mysql behavior ---

@test "mysql - test checks port 3306" {
  stage_listening() { echo "PORT:$*"; }
  stage_exec() { :; }
  run test_mysql
  assert_success
  assert_output --partial "PORT:3306"
}

# --- write_pass_to_conf behavior ---

@test "mysql - write_pass_to_conf creates .my.cnf with password" {
  export TOASTER_MYSQL_PASS="supersecret"
  mkdir -p "$STAGE_MNT/root"
  rm -f "$STAGE_MNT/root/.my.cnf"
  preserve_file() { :; }
  cd "$BATS_FILE_TMPDIR" || skip "tmpdir unavailable"
  write_pass_to_conf
  run grep "password" "$STAGE_MNT/root/.my.cnf"
  assert_success
  assert_output --partial "supersecret"
}

@test "mysql - configure_mysql_ram appends innodb_buffer_pool_size when RAM < 8GB" {
  local _cnf="$BATS_FILE_TMPDIR/extra_ram_test.cnf"
  touch "$_cnf"
  # sysctl stub returns 1GB (< 8GB threshold) — low-memory path must fire.
  configure_mysql_ram "$_cnf"
  run grep "innodb_buffer_pool_size" "$_cnf"
  assert_success
  assert_output --partial "512M"
}

@test "mysql - configure_mysql_ram skips when RAM >= 8GB" {
  local _cnf="$BATS_FILE_TMPDIR/extra_ram_high.cnf"
  touch "$_cnf"
  sysctl() { echo "8589934592"; }  # exactly 8GB — at or above threshold, skip
  configure_mysql_ram "$_cnf"
  run grep "innodb_buffer_pool_size" "$_cnf"
  assert_failure  # nothing appended
}

# --- migrate_mysql_dbs behavior ---

@test "mysql - migrate_mysql_dbs skips when jail is not running" {
  jail_is_running() { return 1; }
  run migrate_mysql_dbs
  assert_success
}
