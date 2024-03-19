
setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
}

@test "./include/djb.sh" {
  run ./include/djb.sh
  assert_success
}

@test "./include/editor.sh" {
  run ./include/editor.sh
  assert_success
}

@test "./include/mta.sh" {
  run ./include/mta.sh
  assert_success
}

@test "./include/mysql.sh" {
  run ./include/mysql.sh
  assert_success
}

@test "./include/nginx.sh" {
  run ./include/nginx.sh
  assert_success
}

@test "./include/php.sh" {
  run ./include/php.sh
  assert_success
}

@test "./include/shell.sh" {
  run ./include/shell.sh
  assert_success
}

@test "./include/user.sh" {
  run ./include/user.sh
  assert_success
}

@test "./include/vpopmail.sh" {
  run ./include/vpopmail.sh
  assert_success
}
