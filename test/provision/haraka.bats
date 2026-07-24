#!/usr/bin/env bats
# Functional tests for provision/haraka.sh

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export STAGE_MNT; STAGE_MNT=$(mktemp -d /tmp/mt6hkXXXXXX)
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  export ZFS_DATA_MNT="$STAGE_MNT/data"
  export ZFS_JAIL_MNT="$STAGE_MNT/jails"
  export ZFS_DATA_VOL="zroot${ZFS_DATA_MNT}"
  export ZFS_JAIL_VOL="zroot${ZFS_JAIL_MNT}"

  HARAKA_CONF="$ZFS_DATA_MNT/haraka/config"

  # configure_haraka_syslog uncomments the syslog plugin in an existing file
  mkdir -p "$HARAKA_CONF"
  printf '# syslog\n' > "$HARAKA_CONF/plugins"

  # source the function definitions only; the execution block at the bottom
  # provisions a jail
  sed '/^preinstall_checks$/,$d' "$BATS_TEST_DIRNAME/../../provision/haraka.sh" \
    > "$STAGE_MNT/haraka-functions.sh"
  # shellcheck source=/dev/null
  . "$STAGE_MNT/haraka-functions.sh"
}

teardown() {
  rm -rf "$STAGE_MNT"
}

@test "configure_haraka_syslog logs to the data volume" {
  configure_haraka_syslog

  run cat "$STAGE_MNT/etc/syslog.conf"
  assert_success
  assert_output --partial "/data/log/maillog"
  refute_output --partial "/var/log/maillog"
}

@test "configure_haraka_syslog creates the log dir and maillog" {
  configure_haraka_syslog

  [ -d "$ZFS_DATA_MNT/haraka/log" ]
  [ -f "$ZFS_DATA_MNT/haraka/log/maillog" ]
}

@test "configure_haraka_syslog points log-reader at the data volume" {
  configure_haraka_syslog

  run cat "$HARAKA_CONF/log.reader.ini"
  assert_success
  assert_output --partial "file=/data/log/maillog"
}

@test "configure_haraka_log_rotation rotates the maillog on the data volume" {
  configure_haraka_log_rotation

  run cat "$STAGE_MNT/etc/newsyslog.conf.d/haraka.conf"
  assert_success
  assert_output --partial "/data/log/maillog"
  # haraka.conf is the only place mail log retention is set
  assert_line --regexp "^/data/log/maillog[[:space:]]+644[[:space:]]+21"
}

# --- listen address follows IPv6 availability ---

@test "haraka_listen_addr returns 0.0.0.0 when no public IPv6" {
  unset PUBLIC_IP6
  run haraka_listen_addr
  assert_output "0.0.0.0"
}

@test "haraka_listen_addr returns [::0] when public IPv6 present" {
  export PUBLIC_IP6="2001:db8::1"
  run haraka_listen_addr
  assert_output "[::0]"
}

@test "configure_haraka_smtp_ini binds IPv4 when no public IPv6" {
  printf ';listen=[::0]:25\n' > "$HARAKA_CONF/smtp.ini"
  unset PUBLIC_IP6
  configure_haraka_smtp_ini

  run cat "$HARAKA_CONF/smtp.ini"
  assert_output --partial "listen=0.0.0.0:25,0.0.0.0:465,0.0.0.0:587"
  refute_output --partial "[::0]"
}

@test "configure_haraka_smtp_ini binds IPv6 when public IPv6 present" {
  printf ';listen=[::0]:25\n' > "$HARAKA_CONF/smtp.ini"
  export PUBLIC_IP6="2001:db8::1"
  configure_haraka_smtp_ini

  run cat "$HARAKA_CONF/smtp.ini"
  assert_output --partial "listen=[::0]:25,[::0]:465,[::0]:587"
}

@test "configure_haraka_http binds IPv4 when no public IPv6" {
  rm -f "$HARAKA_CONF/http.ini"
  unset PUBLIC_IP6
  configure_haraka_http

  run cat "$HARAKA_CONF/http.ini"
  assert_output --partial "listen=0.0.0.0:80"
}
