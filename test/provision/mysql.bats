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
             upgrade_mariadb_data mariadb_rollback_help detach_live_data \
             wait_for_stage_mariadb finish_mariadb_upgrade \
             mariadb_upgrade_marker existing_mysql_root_pass; do
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

# store_config runs as root in a dir the mysql user owns
@test "mysql - configure refuses an extra.cnf symlink" {
  local _target="$BATS_TEST_TMPDIR/host-file"
  echo untouched > "$_target"
  rm -f "$STAGE_MNT/data/etc/extra.cnf"
  ln -s "$_target" "$STAGE_MNT/data/etc/extra.cnf"
  store_config() { echo "STORE:$1"; }
  run configure_mysql
  assert_failure
  assert_output --partial "is a symlink"
  refute_output --partial "STORE:"
  run cat "$_target"
  assert_output "untouched"
}

@test "mysql - configure refuses an extra.cnf.mt6 symlink" {
  local _target="$BATS_TEST_TMPDIR/host-file"
  echo untouched > "$_target"
  rm -f "$STAGE_MNT/data/etc/extra.cnf.mt6"
  ln -s "$_target" "$STAGE_MNT/data/etc/extra.cnf.mt6"
  store_config() { echo "STORE:$1"; }
  run configure_mysql
  assert_failure
  assert_output --partial "is a symlink"
  refute_output --partial "STORE:"
  run cat "$_target"
  assert_output "untouched"
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

# the data, not the jail's mount, says there is a live datadir: a stopped
# jail has its data unmounted while the stage still mounts it
_live_data() {
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  mkdir -p "$ZFS_DATA_MNT/mysql/db/mysql"
}

# two mysqlds cannot share a datadir, so the stage lets go of the live one
@test "mysql - start detaches the live data before mysqld starts" {
  _live_data
  unmount_data() { echo "UNMOUNT:$*"; }
  stage_exec()   { echo "EXEC:$*"; }
  chown() { :; }
  configure_mysql_root_password() { :; }
  configure_mysql_keys() { :; }

  run start_mysql
  assert_success
  assert_line --index 0 "UNMOUNT:mysql"
  assert_line --index 1 "EXEC:service mysql-server start"
}

# the unmount leaves the stage an empty /data, and the server needs its
# datadir and option file there
@test "mysql - start gives the stage its own datadir and option file" {
  _live_data
  printf '[mysqld]\ninnodb_doublewrite = off\n' > "$STAGE_MNT/data/etc/extra.cnf"
  unmount_data() { rm -rf "$STAGE_MNT/data"; mkdir "$STAGE_MNT/data"; }
  stage_exec()   { :; }
  chown() { echo "CHOWN:$*"; }
  configure_mysql_root_password() { :; }
  configure_mysql_keys() { :; }

  run start_mysql
  assert_success
  assert_output --partial "CHOWN:88:88 $STAGE_MNT/data/etc"
  assert_output --partial "CHOWN:88:88 $STAGE_MNT/data/db"
  assert [ -d "$STAGE_MNT/data/db" ]
  run cat "$STAGE_MNT/data/etc/extra.cnf"
  assert_output --partial "innodb_doublewrite = off"
}

# the option file may hold secrets, a umask of 022 must not open it up
@test "mysql - start keeps the staged option file private" {
  _live_data
  printf '[mysqld]\nplugin_load_add = file_key_management\n' > "$STAGE_MNT/data/etc/extra.cnf"
  chmod 600 "$STAGE_MNT/data/etc/extra.cnf"
  unmount_data() { rm -rf "$STAGE_MNT/data"; mkdir "$STAGE_MNT/data"; }
  stage_exec()   { :; }
  chown() { :; }
  configure_mysql_root_password() { :; }
  configure_mysql_keys() { :; }

  umask 022
  run start_mysql
  assert_success
  run ls -l "$STAGE_MNT/data/etc/extra.cnf"
  assert_output --regexp '^-rw------- '
}

@test "mysql - start without live data leaves the data mounted" {
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/empty-data"
  unmount_data() { echo "UNMOUNT:$*"; }
  stage_exec()   { echo "EXEC:$*"; }
  configure_mysql_root_password() { :; }
  configure_mysql_keys() { :; }

  run start_mysql
  assert_success
  refute_output --partial "UNMOUNT"
}

# mysql.sh runs under set -e, where a missing stub ends provisioning
@test "mysql - start survives set -e on a host with live data" {
  _live_data
  unmount_data() { :; }
  stage_exec() { echo "EXEC:$*"; }
  chown() { :; }
  configure_mysql_root_password() { :; }
  configure_mysql_keys() { :; }
  start_under_errexit() { ( set -e; start_mysql ); }

  run start_under_errexit
  assert_success
  assert_output --partial "EXEC:service mysql-server start"
}

# the stage runs on its own empty datadir, the upgrade is a later step
@test "mysql - start does not run mariadb-upgrade" {
  export TOASTER_MARIADB="1"
  stage_exec() { echo "EXEC:$*"; }
  configure_mysql_root_password() { :; }
  configure_mysql_keys() { :; }
  run start_mysql
  assert_success
  refute_output --partial "mariadb-upgrade"
}

@test "mysql - upgrade_mariadb_tables starts the stage server, upgrades, stops it" {
  export TOASTER_MARIADB="1"
  stage_exec() { echo "EXEC:$*"; }
  stage_sysrc() { echo "SYSRC:$*"; }
  wait_for_stage_mariadb() { echo "WAIT"; }
  run upgrade_mariadb_tables
  assert_success
  assert_line --index 1 "EXEC:service mysql-server start"
  assert_line --index 2 "WAIT"
  assert_line --index 3 --partial "EXEC:mariadb-upgrade"
  assert_line --index 4 "EXEC:service mysql-server stop"
}

# the stage has a jail-network address and the live grants
@test "mysql - upgrade_mariadb_tables runs a socket-only server without events or replication" {
  export TOASTER_MARIADB="1"
  stage_exec() { echo "EXEC:$*"; }
  stage_sysrc() { echo "SYSRC:$*"; }
  wait_for_stage_mariadb() { :; }
  run upgrade_mariadb_tables
  assert_success
  assert_line --index 0 --partial "SYSRC:mysql_args="
  assert_line --index 0 --partial "--skip-networking"
  assert_line --index 0 --partial "--event-scheduler=DISABLED"
  assert_line --index 0 --partial "--skip-slave-start"
}

# the promoted jail keeps the stage's rc.conf
@test "mysql - upgrade_mariadb_tables removes the restricted args before promotion" {
  export TOASTER_MARIADB="1"
  stage_exec() { echo "EXEC:$*"; }
  stage_sysrc() { echo "SYSRC:$*"; }
  wait_for_stage_mariadb() { :; }
  run upgrade_mariadb_tables
  assert_success
  assert_line --index 4 "SYSRC:-x mysql_args"
}

@test "mysql - upgrade_mariadb_tables stops short when mariadb-upgrade fails" {
  export TOASTER_MARIADB="1"
  stage_exec() { case "$1" in mariadb-upgrade) return 1 ;; *) echo "EXEC:$*" ;; esac; }
  stage_sysrc() { :; }
  wait_for_stage_mariadb() { :; }
  run upgrade_mariadb_tables
  assert_failure
}

@test "mysql - upgrade_mariadb_tables skips mysql" {
  export TOASTER_MARIADB="0"
  stage_exec() { echo "EXEC:$*"; }
  run upgrade_mariadb_tables
  assert_success
  refute_output --partial "EXEC"
}

@test "mysql - wait_for_stage_mariadb waits for the server" {
  export _ping_count="$BATS_TEST_TMPDIR/pings"
  : > "$_ping_count"
  sleep() { :; }
  jexec() { echo x >> "$_ping_count"; [ "$(wc -l < "$_ping_count")" -ge 3 ]; }
  run wait_for_stage_mariadb
  assert_success
}

@test "mysql - wait_for_stage_mariadb gives up when the server never starts" {
  sleep() { :; }
  jexec() { return 1; }
  run wait_for_stage_mariadb
  assert_failure
  assert_output --partial "did not start"
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

# --- configure_mysql_root_password: the existing root password ---

# the live jail, a log of the client calls, and no way to make a new password
_root_pw_setup() {
  export ZFS_JAIL_MNT="$BATS_TEST_TMPDIR/jails"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/empty-data"
  export TOASTER_MYSQL_PASS=""
  export TOASTER_MARIADB="1"
  mkdir -p "$ZFS_JAIL_MNT/mysql/root"
  _calls="$BATS_TEST_TMPDIR/calls"; : > "$_calls"
  # SHOW DATABASES (the call with --password) fails on a stage with no root password yet
  stage_exec() {
    cat >/dev/null; echo "EXEC:$*" >> "$_calls"
    case "$*" in *--password=*) return "${_show_rc:-0}" ;; esac
  }
  get_random_pass() { echo "RANDOM-PASS"; }
  write_pass_to_conf() { :; }
}

@test "mysql - root password: reads the password MT6 wrote to root/.my.cnf" {
  _root_pw_setup
  printf '[client]\nuser = root\npassword = s3cret\n' > "$ZFS_JAIL_MNT/mysql/root/.my.cnf"
  configure_mysql_root_password
  [ "$TOASTER_MYSQL_PASS" = "s3cret" ]
  run grep -c "ALTER\|RANDOM" "$_calls"
  assert_output "0"
}

@test "mysql - root password: parses password=value without spaces, quotes and a space" {
  _root_pw_setup
  printf '[client]\npassword=nospace\n' > "$ZFS_JAIL_MNT/mysql/root/.my.cnf"
  run existing_mysql_root_pass
  assert_output "nospace"

  printf '[client]\npassword = "quoted pw"\n' > "$ZFS_JAIL_MNT/mysql/root/.my.cnf"
  run existing_mysql_root_pass
  assert_output "quoted pw"

  printf '# password = old\n[client]\nuser = root\n  password =   x=y  \n' > "$ZFS_JAIL_MNT/mysql/root/.my.cnf"
  run existing_mysql_root_pass
  assert_output "x=y"
}

@test "mysql - root password: does not look at root/my.cnf" {
  _root_pw_setup
  printf '[client]\npassword = wrongfile\n' > "$ZFS_JAIL_MNT/mysql/root/my.cnf"
  run existing_mysql_root_pass
  assert_output ""
}

@test "mysql - root password: falls back to the previous jail's .my.cnf" {
  _root_pw_setup
  mkdir -p "$ZFS_JAIL_MNT/mysql.last/root"
  printf '[client]\npassword = fromlast\n' > "$ZFS_JAIL_MNT/mysql.last/root/.my.cnf"
  run existing_mysql_root_pass
  assert_output "fromlast"
}

@test "mysql - root password: an empty stage gets the existing password, not a random one" {
  _root_pw_setup
  mkdir -p "$ZFS_DATA_MNT/mysql/db/mysql"
  printf '[client]\npassword = s3cret\n' > "$ZFS_JAIL_MNT/mysql/root/.my.cnf"
  _show_rc=1
  configure_mysql_root_password
  [ "$TOASTER_MYSQL_PASS" = "s3cret" ]
  run grep "ALTER" "$_calls"
  refute_output --partial "RANDOM"
  run cat "$_calls"
  assert_output --partial "EXEC:mariadb --password=s3cret"
}

@test "mysql - root password: existing data and no known password is an error, nothing is changed" {
  _root_pw_setup
  mkdir -p "$ZFS_DATA_MNT/mysql/db/mysql"
  run configure_mysql_root_password
  assert_failure
  assert_output --partial "TOASTER_MYSQL_PASS"
  run cat "$_calls"
  assert_output ""
}

@test "mysql - root password: a fresh install generates one and sets it" {
  _root_pw_setup
  _show_rc=1
  configure_mysql_root_password
  [ "$TOASTER_MYSQL_PASS" = "RANDOM-PASS" ]
  run cat "$_calls"
  assert_output --partial "EXEC:mariadb -u root"
}

@test "mysql - root password: a set TOASTER_MYSQL_PASS is used as is" {
  _root_pw_setup
  export TOASTER_MYSQL_PASS="fromconf"
  printf '[client]\npassword = s3cret\n' > "$ZFS_JAIL_MNT/mysql/root/.my.cnf"
  configure_mysql_root_password
  [ "$TOASTER_MYSQL_PASS" = "fromconf" ]
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

# --- upgrade_mariadb_data behavior ---

_upgrade_stubs() {
  export MARIADB_UPGRADE_FROM="10.11.10"
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  mkdir -p "$ZFS_DATA_MNT/mysql"
  stage_exec()   { echo "EXEC:$*"; }
  stop_jail()    { echo "STOP:$*"; }
  jail_is_running() { return 1; }
  sysrc()        { echo "SYSRC:$*"; }
  enable_jail()  { echo "ENABLE:$*"; }
  zfs()          { echo "ZFS:$*"; }
  mount()        { echo "MOUNT:$*"; }
  unmount_data() { echo "UNMOUNT:$*"; }
  upgrade_mariadb_tables() { echo "TABLES"; }
}

@test "mysql - upgrade_mariadb_data does nothing without an upgrade" {
  _upgrade_stubs
  export MARIADB_UPGRADE_FROM=""
  run upgrade_mariadb_data
  assert_success
  assert_output ""
}

# the old server takes writes until it stops, so it stops first, then the
# snapshot, then the upgrade runs in the stage on the live data
@test "mysql - upgrade_mariadb_data stops, snapshots, then upgrades the live data" {
  _upgrade_stubs
  run upgrade_mariadb_data
  assert_success
  assert_line --index 1 "EXEC:service mysql-server stop"
  assert_line --index 2 "STOP:mysql"
  assert_line --index 3 --regexp "ZFS:snapshot .*/mysql@mariadb-10\.11\.10-[0-9]+"
  assert_line --index 4 --regexp "MOUNT:-t nullfs .*/data/mysql .*/stage/data"
  assert_line --index 5 "TABLES"
  assert_line --index 6 "UNMOUNT:mysql"
}

# no trap runs on a reboot or power loss, so the old jail must not be in
# jail_list while 12.3 rewrites its data
@test "mysql - upgrade_mariadb_data keeps the old jail from booting first" {
  _upgrade_stubs
  run upgrade_mariadb_data
  assert_success
  assert_line --index 0 'SYSRC:jail_list-= mysql'
  refute_output --partial "ENABLE:mysql"
}

# a marker in the data survives a crash, written after the snapshot so that
# rolling back to it clears it
@test "mysql - upgrade_mariadb_data leaves a marker naming the snapshot" {
  _upgrade_stubs
  run upgrade_mariadb_data
  assert_success
  run cat "$ZFS_DATA_MNT/mysql/.mariadb-upgrade"
  assert_output --regexp "/mysql@mariadb-10\.11\.10-[0-9]+"
}

# stop_jail swallows a failed stop
@test "mysql - upgrade_mariadb_data refuses to snapshot a jail that is still up" {
  _upgrade_stubs
  jail_is_running() { return 0; }
  run upgrade_mariadb_data
  assert_failure
  assert_output --partial "did not stop"
  assert_output --partial "ENABLE:mysql"
  refute_output --partial "ZFS:"
  refute_output --partial "TABLES"
}

# promotion never began, the old jail must not be left stopped
@test "mysql - upgrade_mariadb_data restarts the old jail when the snapshot fails" {
  _upgrade_stubs
  zfs() { case "$1" in snapshot) return 1 ;; *) echo "ZFS:$*" ;; esac; }
  service() { echo "SERVICE:$*"; }
  run upgrade_mariadb_data
  assert_failure
  assert_output --partial "SERVICE:jail start mysql"
  assert_output --partial "ENABLE:mysql"
  assert_output --partial "could not snapshot"
  refute_output --partial "TABLES"
  refute_output --partial "The upgrade failed"
  assert [ ! -f "$ZFS_DATA_MNT/mysql/.mariadb-upgrade" ]
}

# the live data was changed by then, so say how to undo it
@test "mysql - upgrade_mariadb_data prints rollback steps when the upgrade fails" {
  _upgrade_stubs
  upgrade_mariadb_tables() { return 1; }
  run upgrade_mariadb_data
  assert_failure
  assert_output --partial "The upgrade failed"
  assert_output --regexp "zfs rollback .*/mysql@mariadb-10\.11\.10-[0-9]+"
}

@test "mysql - upgrade_mariadb_data prints rollback steps when the mount fails" {
  _upgrade_stubs
  mount() { return 1; }
  run upgrade_mariadb_data
  assert_failure
  assert_output --partial "The upgrade failed"
}

# --- finish_mariadb_upgrade behavior ---

@test "mysql - finish_mariadb_upgrade removes the marker" {
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  mkdir -p "$ZFS_DATA_MNT/mysql"
  echo snap > "$ZFS_DATA_MNT/mysql/.mariadb-upgrade"
  export MARIADB_SNAPSHOT="zroot/data/mysql@mariadb-10.11.10-20260101000000"
  run finish_mariadb_upgrade
  assert_success
  assert [ ! -f "$ZFS_DATA_MNT/mysql/.mariadb-upgrade" ]
}

# the new server is serving clients, a rollback would discard their writes
@test "mysql - finish_mariadb_upgrade disarms the rollback trap" {
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  mkdir -p "$ZFS_DATA_MNT/mysql"
  export MARIADB_SNAPSHOT="zroot/data/mysql@mariadb-10.11.10-20260101000000"
  mariadb_rollback_help() { echo "ROLLBACK HELP"; }
  late_failure() {
    trap '[ $? = 0 ] || mariadb_rollback_help' EXIT
    finish_mariadb_upgrade
    exit 1
  }
  run late_failure
  assert_failure
  refute_output --partial "ROLLBACK HELP"
}

@test "mysql - finish_mariadb_upgrade does nothing without a snapshot" {
  export MARIADB_SNAPSHOT=""
  run finish_mariadb_upgrade
  assert_success
  assert_output ""
}

# --- mariadb_rollback_help behavior ---

@test "mysql - mariadb_rollback_help swaps the jail back once it was renamed" {
  export MARIADB_SNAPSHOT="zroot/data/mysql@mariadb-10.11.10-20260101000000"
  export MARIADB_OLD_JAIL_GUID="1234"
  jail_is_running() { return 1; }
  zfs() { case "$*" in *"guid $ZFS_JAIL_VOL/mysql.last") echo 1234 ;; *) return 1 ;; esac; }
  run mariadb_rollback_help
  assert_success
  assert_output --partial "zfs rollback $MARIADB_SNAPSHOT"
  assert_output --partial "jail -r stage"
  assert_output --partial "zfs rename $ZFS_JAIL_VOL/mysql.last $ZFS_JAIL_VOL/mysql"
}

# a mysql.failed left by an earlier rollback made both renames fail
@test "mysql - mariadb_rollback_help names the failed dataset uniquely" {
  export MARIADB_SNAPSHOT="zroot/data/mysql@mariadb-10.11.10-20260101000000"
  export MARIADB_OLD_JAIL_GUID="1234"
  jail_is_running() { return 1; }
  zfs() { case "$*" in *"guid $ZFS_JAIL_VOL/mysql.last") echo 1234 ;; *) return 1 ;; esac; }
  run mariadb_rollback_help
  assert_success
  assert_output --regexp "zfs rename $ZFS_JAIL_VOL/mysql $ZFS_JAIL_VOL/mysql\.failed-[0-9]{14}"
}

# a failed rename must stop the sequence short of starting the wrong server
@test "mysql - mariadb_rollback_help chains the steps so a failure stops them" {
  export MARIADB_SNAPSHOT="zroot/data/mysql@mariadb-10.11.10-20260101000000"
  export MARIADB_OLD_JAIL_GUID="1234"
  jail_is_running() { return 1; }
  zfs() { case "$*" in *"guid $ZFS_JAIL_VOL/mysql.last") echo 1234 ;; *) return 1 ;; esac; }
  run mariadb_rollback_help
  assert_success
  assert_output --partial "&& zfs rename $ZFS_JAIL_VOL/mysql "
  assert_output --partial "&& zfs rename $ZFS_JAIL_VOL/mysql.last"
  assert_output --partial 'sysrc jail_list+=" mysql"'
  assert_output --partial "&& service jail start mysql"
}

# mysql.last may be an older provision's jail, never advise swapping that in
@test "mysql - mariadb_rollback_help leaves the jail alone when mysql.last is older" {
  export MARIADB_SNAPSHOT="zroot/data/mysql@mariadb-10.11.10-20260101000000"
  export MARIADB_OLD_JAIL_GUID="1234"
  jail_is_running() { return 1; }
  zfs() { case "$*" in *"guid $ZFS_JAIL_VOL/mysql.last") echo 9999 ;; *) return 1 ;; esac; }
  run mariadb_rollback_help
  assert_success
  refute_output --partial "zfs rename"
  assert_output --partial "zfs rollback $MARIADB_SNAPSHOT"
  assert_output --partial "&& service jail start mysql"
}

@test "mysql - mariadb_rollback_help leaves the jail alone without a mysql.last" {
  export MARIADB_SNAPSHOT="zroot/data/mysql@mariadb-10.11.10-20260101000000"
  export MARIADB_OLD_JAIL_GUID="1234"
  jail_is_running() { return 1; }
  zfs() { return 1; }
  run mariadb_rollback_help
  assert_success
  refute_output --partial "zfs rename"
}

# the new server may have taken writes by then
@test "mysql - mariadb_rollback_help warns when the new jail is already running" {
  export MARIADB_SNAPSHOT="zroot/data/mysql@mariadb-10.11.10-20260101000000"
  export MARIADB_OLD_JAIL_GUID="1234"
  jail_is_running() { return 0; }
  zfs() { case "$*" in *"guid $ZFS_JAIL_VOL/mysql.last") echo 1234 ;; *) return 1 ;; esac; }
  run mariadb_rollback_help
  assert_success
  assert_output --partial "may have accepted writes"
}

@test "mysql - mariadb_rollback_help does not warn before the new jail ran" {
  export MARIADB_SNAPSHOT="zroot/data/mysql@mariadb-10.11.10-20260101000000"
  export MARIADB_OLD_JAIL_GUID="1234"
  jail_is_running() { return 1; }
  zfs() { return 1; }
  run mariadb_rollback_help
  assert_success
  refute_output --partial "may have accepted writes"
}

@test "mysql - mariadb_rollback_help is silent without a snapshot" {
  export MARIADB_SNAPSHOT=""
  run mariadb_rollback_help
  assert_success
  assert_output ""
}

# --- the marker of an unfinished upgrade ---

@test "mysql - check_mariadb_upgrade halts on the marker of an unfinished upgrade" {
  export TOASTER_MARIADB="1"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  _with_data
  echo "zroot/data/mysql@mariadb-10.11.10-20260101000000" > "$ZFS_DATA_MNT/mysql/.mariadb-upgrade"
  pkg() { echo "mariadb1011-server-10.11.10"; }
  run check_mariadb_upgrade
  assert_failure
  assert_output --partial "did not finish"
  assert_output --partial "mariadb-10.11.10-20260101000000"
}
