
setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
}

@test "./include/djb.sh" {
  run ./include/djb.sh
  [ "$status" -eq 0 ]
}

@test "./include/editor.sh" {
  run ./include/editor.sh
  [ "$status" -eq 0 ]
}

@test "./include/mta.sh" {
  run ./include/mta.sh
  [ "$status" -eq 0 ]
}

@test "./include/mysql.sh" {
  run ./include/mysql.sh
  [ "$status" -eq 0 ]
}

@test "./include/nginx.sh" {
  run ./include/nginx.sh
  [ "$status" -eq 0 ]
}

@test "./include/php.sh" {
  run ./include/php.sh
  [ "$status" -eq 0 ]
}

@test "./include/shell.sh" {
  run ./include/shell.sh
  [ "$status" -eq 0 ]
}

@test "./include/user.sh" {
  run ./include/user.sh
  [ "$status" -eq 0 ]
}

@test "./include/vpopmail.sh" {
  run ./include/vpopmail.sh
  [ "$status" -eq 0 ]
}
