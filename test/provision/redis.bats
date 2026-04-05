#!/usr/bin/env bats
# Functional tests for provision/redis.sh
# redis.sh uses `set -e`; configure_redis uses `sed -i.bak` (GNU-compatible).
# We pre-create a stub redis.conf so configure_redis succeeds.

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export STAGE_MNT; STAGE_MNT=$(mktemp -d)
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  # Pre-create directories and stub redis.conf so configure_redis can run
  mkdir -p "$STAGE_MNT/usr/local/etc"
  cat > "$STAGE_MNT/usr/local/etc/redis.conf" <<'EOF'
stop-writes-on-bgsave-error yes
dir /var/db/redis/
# syslog-enabled no
logfile ""
bind 127.0.0.1
protected-mode yes
EOF

  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../provision/redis.sh"
}

teardown() {
  rm -rf "$STAGE_MNT"
}

# --- JAIL variable exports ---

@test "redis - JAIL_START_EXTRA is empty (no special capabilities)" {
  assert_equal "$JAIL_START_EXTRA" ""
}

@test "redis - JAIL_CONF_EXTRA is empty" {
  assert_equal "$JAIL_CONF_EXTRA" ""
}

@test "redis - JAIL_FSTAB is empty" {
  assert_equal "$JAIL_FSTAB" ""
}

# --- Function existence ---

@test "redis - defines install_redis" {
  run type install_redis
  assert_success
}

@test "redis - defines configure_redis" {
  run type configure_redis
  assert_success
}

@test "redis - defines start_redis" {
  run type start_redis
  assert_success
}

@test "redis - defines test_redis" {
  run type test_redis
  assert_success
}

# --- configure_redis outcomes ---

@test "redis - configure disables stop-writes-on-bgsave-error" {
  run grep "stop-writes-on-bgsave-error" "$STAGE_MNT/usr/local/etc/redis.conf"
  assert_output --partial "no"
  refute_output --partial "yes"
}

@test "redis - configure sets data dir to /data/db/" {
  run grep "^dir" "$STAGE_MNT/usr/local/etc/redis.conf"
  assert_output --partial "/data/db/"
}

@test "redis - configure enables syslog" {
  run grep "syslog-enabled" "$STAGE_MNT/usr/local/etc/redis.conf"
  assert_output --partial "yes"
}

@test "redis - configure disables protected-mode" {
  run grep "^protected-mode" "$STAGE_MNT/usr/local/etc/redis.conf"
  assert_output --partial "no"
}

@test "redis - configure comments out bind directive" {
  run grep "^#bind" "$STAGE_MNT/usr/local/etc/redis.conf"
  assert_success
}

@test "redis - configure creates newsyslog rotation config" {
  [ -f "$STAGE_MNT/usr/local/etc/newsyslog.conf.d/redis.conf" ]
}

@test "redis - configure creates data subdirectories" {
  [ -d "$STAGE_MNT/data/db" ]
  [ -d "$STAGE_MNT/data/log" ]
  [ -d "$STAGE_MNT/data/etc" ]
}

# --- install_redis behaviour ---

@test "redis - install uses redis package" {
  stage_pkg_install() { echo "PKG:$*"; }
  run install_redis
  assert_success
  assert_output --partial "PKG:redis"
}

# --- start_redis behaviour ---

@test "redis - start enables redis service" {
  stage_sysrc() { echo "SYSRC:$*"; }
  stage_exec()  { :; }
  run start_redis
  assert_success
  assert_output --partial "SYSRC:redis_enable=YES"
}

@test "redis - start calls service redis start" {
  stage_sysrc() { :; }
  stage_exec()  { echo "EXEC:$*"; }
  run start_redis
  assert_success
  assert_output --partial "EXEC:service redis start"
}

# --- test_redis behaviour ---

@test "redis - test checks port 6379" {
  stage_listening() { echo "PORT:$*"; }
  run test_redis
  assert_success
  assert_output --partial "PORT:6379"
}
