#!/usr/bin/env bats
# Functional tests for provision/redis.sh
#
# setup_file sources redis.sh once, executing install and configure against
# $BATS_FILE_TMPDIR. Tests read what that run produced; only the tests that
# call a function with its own stubs pay to source the definitions.

setup_file() {
  export MT6_TEST_ENV=1
  export STAGE_MNT="$BATS_FILE_TMPDIR/stage"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export REDIS_CONF="$STAGE_MNT/usr/local/etc/redis.conf"
  export REDIS_FNS="$BATS_FILE_TMPDIR/redis_fns_only.sh"

  awk '/^base_snapshot_exists/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/redis.sh" > "$REDIS_FNS"

  # configure_redis edits redis.conf in place, so it has to exist first
  mkdir -p "$STAGE_MNT/usr/local/etc"
  cat > "$REDIS_CONF" <<'EOF'
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

setup() {
  load '../test_helper/load'
}

load_redis_fns() {
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  # shellcheck source=/dev/null
  . "$REDIS_FNS"
}

@test "redis - declares no jail extras" {
  assert_equal "$JAIL_START_EXTRA" ""
  assert_equal "$JAIL_CONF_EXTRA" ""
  assert_equal "$JAIL_FSTAB" ""
}

@test "redis - defines the jail lifecycle functions" {
  load_redis_fns
  local _fn
  for _fn in install_redis configure_redis start_redis test_redis; do
    run type "$_fn"
    assert_success
  done
}

# --- configure_redis outcomes ---

@test "redis - configure rewrites redis.conf for the jail" {
  run grep "stop-writes-on-bgsave-error" "$REDIS_CONF"
  assert_output --partial "no"
  refute_output --partial "yes"

  run grep "^dir" "$REDIS_CONF"
  assert_output --partial "/data/db/"

  run grep "syslog-enabled" "$REDIS_CONF"
  assert_output --partial "yes"

  # the jail's own address is the only one it answers on
  run grep "^protected-mode" "$REDIS_CONF"
  assert_output --partial "no"
  run grep "^#bind" "$REDIS_CONF"
  assert_success
}

@test "redis - configure creates the data directories and log rotation" {
  [ -d "$STAGE_MNT/data/db" ]
  [ -d "$STAGE_MNT/data/log" ]
  [ -d "$STAGE_MNT/data/etc" ]
  [ -f "$STAGE_MNT/usr/local/etc/newsyslog.conf.d/redis.conf" ]
}

# --- install / start / test behaviour ---

@test "redis - install uses redis package" {
  load_redis_fns
  stage_pkg_install() { echo "PKG:$*"; }
  run install_redis
  assert_success
  assert_output --partial "PKG:redis"
}

@test "redis - start enables the service and starts it" {
  load_redis_fns
  stage_sysrc() { echo "SYSRC:$*"; }
  stage_exec()  { echo "EXEC:$*"; }
  run start_redis
  assert_success
  assert_output --partial "SYSRC:redis_enable=YES"
  assert_output --partial "EXEC:service redis start"
}

@test "redis - test checks port 6379" {
  load_redis_fns
  stage_listening() { echo "PORT:$*"; }
  run test_redis
  assert_success
  assert_output --partial "PORT:6379"
}
