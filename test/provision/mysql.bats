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
#                                              $MT6_CONF safely)

setup_file() {
  load helper
  local _stage="$BATS_FILE_TMPDIR/stage"
  local _data="$BATS_FILE_TMPDIR/data"

  export STAGE_MNT="$_stage"
  export ZFS_DATA_MNT="$_data"

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

  # Change to tmpdir so write_pass_to_conf writes $MT6_CONF here
  # instead of the repository root.
  cd "$BATS_FILE_TMPDIR" || exit 1
  mkdir -p conf.d

  provision_run mysql
}

setup() {
  load helper
  export ZFS_DATA_MNT="$BATS_FILE_TMPDIR/data"

  # Fresh per-test STAGE_MNT copied from the cached template (fast).
  export STAGE_MNT; STAGE_MNT=$(mktemp -d)
  cp -r "$BATS_FILE_TMPDIR/stage/." "$STAGE_MNT/"

  provision_fns mysql
}

teardown() {
  rm -rf "$STAGE_MNT"
}

# --- JAIL variable exports ---

@test "mysql - defines the functions the provisioner calls" {
  local _fn
  for _fn in install_db_server install_mysql install_mariadb configure_mysql \
             start_mysql test_mysql write_pass_to_conf configure_mysql_keys \
             configure_mysql_root_password migrate_mysql_dbs \
             check_mysql_native_passwords migrate_extra_cnf \
             upgrade_mariadb_tables check_mariadb_upgrade db_client \
             snapshot_mariadb_data mariadb_rollback_help; do
    run type "$_fn"
    assert_success
  done
}

# --- configure_mysql outcomes (verified against the post-setup_file my.cnf) ---

@test "mysql - configure rewrites datadir from /var/db/mysql to /data/db" {
  run grep "datadir" "$STAGE_MNT/usr/local/etc/mysql/my.cnf"
  assert_success
  assert_output --partial "/data/db"
  refute_output --partial "/var/db/mysql"
}

@test "mysql - configure rewrites MariaDB datadir in conf.d/server.cnf" {
  export TOASTER_MARIADB="1"
  mkdir -p "$STAGE_MNT/usr/local/etc/mysql/conf.d"
  cat > "$STAGE_MNT/usr/local/etc/mysql/conf.d/server.cnf" <<'EOF'
[server]
datadir                         = /var/db/mysql
EOF
  # data/etc/my.cnf must be absent so the rewrite branch runs.
  rm -f "$STAGE_MNT/data/etc/my.cnf"
  run configure_mysql
  assert_success
  run grep "datadir" "$STAGE_MNT/usr/local/etc/mysql/conf.d/server.cnf"
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
  run grep "innodb_doublewrite" "$STAGE_MNT/data/etc/extra.cnf"
  assert_success
  run grep -E "innodb_file_per_table|innodb_checksum_algorithm" "$STAGE_MNT/data/etc/extra.cnf"
  assert_failure
}

# an edited extra.cnf is preserved, so the settings MariaDB 12 refuses go
@test "mysql - migrate_extra_cnf strips obsolete innodb settings" {
  export TOASTER_MARIADB="1"
  local _cnf="$BATS_TEST_TMPDIR/extra.cnf"
  cat > "$_cnf" <<'EOF'
[mysqld]
innodb_doublewrite = off
innodb_file_per_table = 1
innodb_checksum_algorithm = none
innodb_flush_neighbors = 0
EOF
  migrate_extra_cnf "$_cnf"
  run cat "$_cnf"
  refute_output --partial "innodb_file_per_table"
  refute_output --partial "innodb_checksum_algorithm"
  assert_output --partial "innodb_doublewrite = off"
  assert_output --partial "innodb_flush_neighbors = 0"
}

@test "mysql - migrate_extra_cnf strips hyphenated and quoted settings" {
  export TOASTER_MARIADB="1"
  local _cnf="$BATS_TEST_TMPDIR/extra.cnf"
  cat > "$_cnf" <<'EOF'
[mysqld]
innodb-checksum-algorithm = "none"
  Innodb-File-Per-Table='ON'  # the default
innodb_checksum_algorithm = 'strict_innodb'
innodb-flush-neighbors = 0
EOF
  migrate_extra_cnf "$_cnf"
  run cat "$_cnf"
  refute_output --partial "checksum"
  refute_output --partial "file-per-table"
  refute_output --partial "File-Per-Table"
  assert_output --partial "innodb-flush-neighbors = 0"
}

@test "mysql - migrate_extra_cnf keeps settings an operator chose" {
  export TOASTER_MARIADB="1"
  local _cnf="$BATS_TEST_TMPDIR/extra.cnf"
  cat > "$_cnf" <<'EOF'
[mysqld]
innodb_file_per_table = OFF
innodb_checksum_algorithm = strict_full_crc32
innodb-checksum-algorithm = "crc32"
EOF
  cp "$_cnf" "$_cnf.orig"
  migrate_extra_cnf "$_cnf"
  cmp "$_cnf" "$_cnf.orig"
}

# MySQL 8.4 accepts these, an operator's strict_none must survive
@test "mysql - migrate_extra_cnf leaves a MySQL config alone" {
  export TOASTER_MARIADB="0"
  local _cnf="$BATS_TEST_TMPDIR/extra.cnf"
  cat > "$_cnf" <<'EOF'
[mysqld]
innodb_file_per_table = 1
innodb_checksum_algorithm = strict_none
EOF
  cp "$_cnf" "$_cnf.orig"
  migrate_extra_cnf "$_cnf"
  cmp "$_cnf" "$_cnf.orig"
}

# the mysql user owns data/etc, a link there must not redirect a root write
@test "mysql - migrate_extra_cnf does not write through a symlink" {
  export TOASTER_MARIADB="1"
  local _target="$BATS_TEST_TMPDIR/host-file"
  printf 'innodb_checksum_algorithm = none\n' > "$_target"
  ln -s "$_target" "$BATS_TEST_TMPDIR/extra.cnf"
  run migrate_extra_cnf "$BATS_TEST_TMPDIR/extra.cnf"
  assert_success
  run cat "$_target"
  assert_output "innodb_checksum_algorithm = none"
}

@test "mysql - migrate_extra_cnf keeps its temp file out of the cnf dir" {
  export TOASTER_MARIADB="1"
  local _dir="$BATS_TEST_TMPDIR/etc"
  mkdir -p "$_dir"
  printf 'innodb_checksum_algorithm = none\n' > "$_dir/extra.cnf"
  migrate_extra_cnf "$_dir/extra.cnf"
  run ls "$_dir"
  assert_output "extra.cnf"
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

@test "mysql - configure enables the service and points it at /data/db" {
  stage_sysrc() { echo "SYSRC:$*"; }
  run configure_mysql
  assert_success
  assert_output --partial "SYSRC:mysql_enable=YES"
  assert_output --partial "SYSRC:mysql_dbdir=/data/db"
}

# --- install_mysql / install_mariadb behavior ---

@test "mysql - install_mysql installs a mysql server package" {
  stage_pkg_install() { echo "PKG:$*"; }
  run install_mysql
  assert_success
  assert_output --regexp "PKG:mysql[0-9]+-server"
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

# two mysqlds cannot share a datadir, so the stage lets go of the live one
@test "mysql - start unmounts the live data before mysqld starts" {
  export ZFS_JAIL_MNT="$BATS_TEST_TMPDIR/jails"
  mkdir -p "$ZFS_JAIL_MNT/mysql/data/db/mysql"
  unmount_data() { echo "UNMOUNT:$*"; }
  stage_exec()   { echo "EXEC:$*"; }
  configure_mysql_root_password() { :; }
  configure_mysql_keys() { :; }

  run start_mysql
  assert_success
  assert_line --index 0 "UNMOUNT:mysql"
  assert_line --index 1 "EXEC:service mysql-server start"
}

@test "mysql - start without a live mysql jail leaves the data mounted" {
  export ZFS_JAIL_MNT="$BATS_TEST_TMPDIR/jails"
  unmount_data() { echo "UNMOUNT:$*"; }
  stage_exec()   { echo "EXEC:$*"; }
  configure_mysql_root_password() { :; }
  configure_mysql_keys() { :; }

  run start_mysql
  assert_success
  refute_output --partial "UNMOUNT"
}

# mysql.sh runs under set -e, where a missing stub ends provisioning
@test "mysql - start survives set -e on a host running a mysql jail" {
  export ZFS_JAIL_MNT="$BATS_TEST_TMPDIR/jails"
  mkdir -p "$ZFS_JAIL_MNT/mysql/data/db/mysql"
  stage_exec() { echo "EXEC:$*"; }
  configure_mysql_root_password() { :; }
  configure_mysql_keys() { :; }
  start_under_errexit() { ( set -e; start_mysql ); }

  run start_under_errexit
  assert_success
  assert_output --partial "EXEC:service mysql-server start"
}

# the staged jail has an empty datadir, so the upgrade belongs after promotion
@test "mysql - start does not run mariadb-upgrade in the stage" {
  export TOASTER_MARIADB="1"
  stage_exec() { echo "EXEC:$*"; }
  configure_mysql_root_password() { :; }
  configure_mysql_keys() { :; }
  run start_mysql
  assert_success
  refute_output --partial "mariadb-upgrade"
}

@test "mysql - upgrade_mariadb_tables runs mariadb-upgrade in the mysql jail" {
  export TOASTER_MARIADB="1"
  jexec() { echo "JEXEC:$*"; }
  run upgrade_mariadb_tables
  assert_success
  assert_output --partial "JEXEC:mysql mariadb-upgrade"
}

@test "mysql - upgrade_mariadb_tables waits for the server" {
  export TOASTER_MARIADB="1"
  export _ping_count="$BATS_TEST_TMPDIR/pings"
  : > "$_ping_count"
  sleep() { :; }
  jexec() {
    case "$2" in
      mariadb-admin) echo x >> "$_ping_count"; [ "$(wc -l < "$_ping_count")" -ge 3 ] ;;
      *) echo "JEXEC:$*" ;;
    esac
  }
  run upgrade_mariadb_tables
  assert_success
  assert_output --partial "JEXEC:mysql mariadb-upgrade"
}

@test "mysql - upgrade_mariadb_tables gives up when the server never starts" {
  export TOASTER_MARIADB="1"
  sleep() { :; }
  jexec() { return 1; }
  run upgrade_mariadb_tables
  assert_failure
  assert_output --partial "did not start"
}

@test "mysql - upgrade_mariadb_tables skips mysql" {
  export TOASTER_MARIADB="0"
  jexec() { echo "JEXEC:$*"; }
  run upgrade_mariadb_tables
  assert_success
  refute_output --partial "JEXEC"
}

# --- test_mysql behavior ---

@test "mysql - test checks port 3306" {
  stage_listening() { echo "PORT:$*"; }
  stage_exec() { :; }
  run test_mysql
  assert_success
  assert_output --partial "PORT:3306"
}

# MariaDB 11+ warns when its client runs by the mysql name
@test "mysql - test uses the mariadb client when TOASTER_MARIADB=1" {
  export TOASTER_MARIADB="1"
  stage_listening() { :; }
  stage_exec() { echo "EXEC:$*"; }
  run test_mysql
  assert_success
  assert_output --partial "EXEC:mariadb --password="
}

@test "mysql - test uses the mysql client for MySQL" {
  export TOASTER_MARIADB="0"
  stage_listening() { :; }
  stage_exec() { echo "EXEC:$*"; }
  run test_mysql
  assert_success
  assert_output --partial "EXEC:mysql --password="
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

# --- check_mysql_native_passwords behavior ---

@test "mysql - check_mysql_native_passwords skips when jail is not running" {
  jail_is_running() { return 1; }
  run check_mysql_native_passwords
  assert_success
}

@test "mysql - check_mysql_native_passwords skips when running version is 8.4" {
  jail_is_running() { return 0; }
  pkg() { echo "mysql84-server-8.4.0"; }
  run check_mysql_native_passwords
  assert_success
}

@test "mysql - check_mysql_native_passwords passes when 8.0 has no deprecated plugins" {
  jail_is_running() { return 0; }
  pkg() { echo "mysql80-server-8.0.36"; }
  jexec() { :; }  # empty output: no rows returned
  run check_mysql_native_passwords
  assert_success
  refute_output --partial "HALT"
}

@test "mysql - check_mysql_native_passwords halts when 8.0 has deprecated plugins" {
  jail_is_running() { return 0; }
  pkg() { echo "mysql80-server-8.0.36"; }
  jexec() {
    echo "ALTER USER 'app'@'%' IDENTIFIED WITH caching_sha2_password BY '<new_password>';"
  }
  run check_mysql_native_passwords
  assert_failure
  assert_output --partial "HALT"
  assert_output --partial "ALTER USER 'app'@'%'"
  assert_output --partial "caching_sha2_password"
}

# --- check_mariadb_upgrade behavior ---

# existing data, whether or not the jail runs, is what needs protecting
_with_data() {
  mkdir -p "$ZFS_DATA_MNT/mysql/db/mysql"
  export ZFS_JAIL_MNT="$BATS_TEST_TMPDIR/jails"
}

@test "mysql - check_mariadb_upgrade skips a fresh install" {
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/empty-data"
  pkg() { echo "PKG:$*"; }
  run check_mariadb_upgrade
  assert_success
  refute_output --partial "PKG:"
}

@test "mysql - check_mariadb_upgrade reads the package db of a stopped jail" {
  export TOASTER_MARIADB="1"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  _with_data
  jail_is_running() { return 1; }
  pkg() { echo "PKG:$*" >&2; echo "mariadb1011-server-10.11.10"; }
  check_mariadb_upgrade
  [ "$MARIADB_UPGRADE_FROM" = "10.11.10" ]
}

@test "mysql - check_mariadb_upgrade halts on a stopped mysql to mariadb switch" {
  export TOASTER_MARIADB="1"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  _with_data
  jail_is_running() { return 1; }
  pkg() { echo "mysql84-server-8.4.0"; }
  run check_mariadb_upgrade
  assert_failure
  assert_output --partial "HALT"
}

@test "mysql - check_mariadb_upgrade halts when the engine cannot be determined" {
  export TOASTER_MARIADB="1"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  _with_data
  pkg() { return 1; }
  run check_mariadb_upgrade
  assert_failure
  assert_output --partial "could not be determined"
}

@test "mysql - check_mariadb_upgrade halts on an empty package query" {
  export TOASTER_MARIADB="0"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  _with_data
  pkg() { :; }
  run check_mariadb_upgrade
  assert_failure
  assert_output --partial "could not be determined"
}

@test "mysql - check_mariadb_upgrade flags an upgrade of 10.11" {
  export TOASTER_MARIADB="1"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  _with_data
  pkg() { echo "mariadb1011-server-10.11.10     Multithreaded SQL database (server)"; }
  zfs() { echo "ZFS:$*"; }
  run check_mariadb_upgrade
  assert_success
  refute_output --partial "ZFS:"
  check_mariadb_upgrade
  [ "$MARIADB_UPGRADE_FROM" = "10.11.10" ]
}

@test "mysql - check_mariadb_upgrade flags nothing when already on 12.3" {
  export TOASTER_MARIADB="1"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  _with_data
  pkg() { echo "mariadb123-server-12.3.3"; }
  check_mariadb_upgrade
  [ -z "$MARIADB_UPGRADE_FROM" ]
}

@test "mysql - check_mariadb_upgrade halts rather than downgrade from 12.4" {
  export TOASTER_MARIADB="1"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  _with_data
  pkg() { echo "mariadb124-server-12.4.1"; }
  run check_mariadb_upgrade
  assert_failure
  assert_output --partial "newer than the 12.3"
}

@test "mysql - check_mariadb_upgrade halts rather than downgrade from 13.0" {
  export TOASTER_MARIADB="1"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  _with_data
  pkg() { echo "mariadb130-server-13.0.1"; }
  run check_mariadb_upgrade
  assert_failure
  assert_output --partial "newer than the 12.3"
}

@test "mysql - check_mariadb_upgrade halts on a mariadb to mysql switch" {
  export TOASTER_MARIADB="0"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  _with_data
  pkg() { echo "mariadb1011-server-10.11.10"; }
  run check_mariadb_upgrade
  assert_failure
  assert_output --partial "HALT"
}

@test "mysql - check_mariadb_upgrade passes a mysql upgrade through" {
  export TOASTER_MARIADB="0"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  _with_data
  pkg() { echo "mysql80-server-8.0.36"; }
  check_mariadb_upgrade
  [ -z "$MARIADB_UPGRADE_FROM" ]
}

# --- snapshot_mariadb_data behavior ---

# the old server takes writes until it stops, so it stops first
@test "mysql - snapshot_mariadb_data stops the old jail, then snapshots" {
  export MARIADB_UPGRADE_FROM="10.11.10"
  stop_jail() { echo "STOP:$*"; }
  zfs() { echo "ZFS:$*"; }
  run snapshot_mariadb_data
  assert_success
  assert_line --index 0 --regexp "STOP:mysql"
  assert_output --regexp "ZFS:snapshot .*/mysql@mariadb-10\.11\.10-[0-9]+"
}

@test "mysql - snapshot_mariadb_data does nothing without an upgrade" {
  export MARIADB_UPGRADE_FROM=""
  stop_jail() { echo "STOP:$*"; }
  zfs() { echo "ZFS:$*"; }
  run snapshot_mariadb_data
  assert_success
  refute_output --partial "STOP:"
  refute_output --partial "ZFS:"
}

@test "mysql - mariadb_rollback_help covers both sides of promotion" {
  export MARIADB_SNAPSHOT="zroot/data/mysql@mariadb-10.11.10-20260101000000"
  run mariadb_rollback_help
  assert_success
  assert_output --partial "zfs rollback $MARIADB_SNAPSHOT"
  assert_output --partial "jail -r stage"
  assert_output --partial "mysql.last"
  assert_output --partial "still the old jail"
}

@test "mysql - mariadb_rollback_help is silent without a snapshot" {
  export MARIADB_SNAPSHOT=""
  run mariadb_rollback_help
  assert_success
  assert_output ""
}
