setup() {
  load './test_helper/bats-support/load'
  load './test_helper/bats-assert/load'
}

@test "./lib/net.sh" {
  run ./lib/net.sh
  assert_success
}

@test "./lib/unprovision.sh" {
  run ./lib/unprovision.sh
  assert_success
}

@test "./lib/zfs.sh" {
  run ./lib/zfs.sh
  assert_success
}
