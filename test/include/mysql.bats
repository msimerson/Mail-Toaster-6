
setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  # Mock some variables that are normally set by mail-toaster.sh
  export ZFS_JAIL_MNT="/jails"
  export TOASTER_MYSQL_PASS="secret"

  # Source the file under test
  load '../../include/mysql.sh'
}

# Mock jexec since it's a FreeBSD-specific command
jexec() {
  local _input
  read -r _input
  if [[ "$_input" == *"SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='testdb';"* ]]; then
    echo "testdb"
  fi
}

@test "mysql_password_set - with .my.cnf" {
  # Mock _root for this test
  local _tmp_root=$(mktemp -d)
  _root="$_tmp_root"
  touch "$_root/.my.cnf"
  echo "password = some_pass" > "$_root/.my.cnf"

  run mysql_password_set
  assert_success

  rm -rf "$_tmp_root"
}

@test "mysql_password_set - without .my.cnf" {
  local _tmp_root=$(mktemp -d)
  _root="$_tmp_root"

  run mysql_password_set
  assert_failure

  rm -rf "$_tmp_root"
}

@test "mysql_bin - with password set" {
  # Mock mysql_password_set to return 0
  mysql_password_set() { return 0; }

  run mysql_bin
  assert_output "/usr/local/bin/mysql"
}

@test "mysql_bin - with TOASTER_MYSQL_PASS" {
  mysql_password_set() { return 1; }
  export TOASTER_MYSQL_PASS="mypass"

  run mysql_bin
  assert_output '/usr/local/bin/mysql --password="mypass"'
}

@test "mysql_db_exists - exists" {
  mysql_bin() { echo "mysql"; }
  # Mock jexec to return something when checked
  jexec() {
    local _input; read -r _input
    if [[ "$_input" == *"SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='testdb';"* ]]; then
      echo "testdb"
    fi
  }

  run mysql_db_exists testdb
  assert_success
  assert_output --partial "testdb db exists"
}

@test "mysql_db_exists - does not exist" {
  mysql_bin() { echo "mysql"; }
  jexec() {
    local _input; read -r _input
    echo ""
  }

  run mysql_db_exists testdb
  assert_failure
  assert_output --partial "testdb db does not exist"
}
