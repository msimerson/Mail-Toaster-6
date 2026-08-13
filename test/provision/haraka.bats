#!/usr/bin/env bats
# Functional tests for provision/haraka.sh
#
# Every test edits the config tree, so each gets its own $BATS_TEST_TMPDIR.
# setup_file strips the execution block once; setup only sources the result.

setup_file() {
  export HARAKA_FNS="$BATS_FILE_TMPDIR/haraka_fns_only.sh"
  sed '/^preinstall_checks$/,$d' \
    "$BATS_TEST_DIRNAME/../../provision/haraka.sh" > "$HARAKA_FNS"
}

setup() {
  load '../test_helper/load'

  export MT6_TEST_ENV=1
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  export ZFS_DATA_MNT="$STAGE_MNT/data"
  export ZFS_JAIL_MNT="$STAGE_MNT/jails"
  export ZFS_DATA_VOL="zroot${ZFS_DATA_MNT}"
  export ZFS_JAIL_VOL="zroot${ZFS_JAIL_MNT}"

  HARAKA_CONF="$ZFS_DATA_MNT/haraka/config"

  # configure_haraka_syslog uncomments the syslog plugin in an existing file
  mkdir -p "$HARAKA_CONF"
  printf '# syslog\n' > "$HARAKA_CONF/plugins"

  # shellcheck source=/dev/null
  . "$HARAKA_FNS"
}

@test "configure_haraka_syslog keeps the maillog on the data volume" {
  configure_haraka_syslog

  run cat "$STAGE_MNT/etc/syslog.conf"
  assert_success
  assert_output --partial "/data/log/maillog"
  refute_output --partial "/var/log/maillog"

  [ -d "$ZFS_DATA_MNT/haraka/log" ]
  [ -f "$ZFS_DATA_MNT/haraka/log/maillog" ]

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

@test "haraka_listen_addr follows IPv6 availability" {
  unset PUBLIC_IP6
  run haraka_listen_addr
  assert_output "0.0.0.0"

  export PUBLIC_IP6="2001:db8::1"
  run haraka_listen_addr
  assert_output "[::0]"
}

# haraka.sh populates no address itself, so reading PUBLIC_IP6 straight left an
# IPv6 only host listening on 0.0.0.0 and taking no mail at all
@test "haraka_listen_addr does not depend on its caller for PUBLIC_IP6" {
  # the real has_public_ip6, which jail_has_ip6 defers to
  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../include/network.sh"

  # stub what it shells out to. These must come after the source above, or
  # network.sh replaces get_public_facing_nic with the real one, which reads the
  # host routing table and fails wherever netstat has no "default" line.
  get_public_facing_nic() { export PUBLIC_NIC="em0"; }
  ifconfig() { echo "	inet6 2001:db8::1 prefixlen 64"; }

  unset PUBLIC_IP6
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

  printf ';listen=[::0]:25\n' > "$HARAKA_CONF/smtp.ini"
  export PUBLIC_IP6="2001:db8::1"
  configure_haraka_smtp_ini
  run cat "$HARAKA_CONF/smtp.ini"
  assert_output --partial "listen=[::0]:25,[::0]:465,[::0]:587"
}

# --- plugin enabling survives Haraka dropping the commented entries ---

@test "haraka_enable_plugin uncomments an entry Haraka still ships" {
  printf '# status\n# watch\n# syslog\n' > "$HARAKA_CONF/plugins"
  haraka_enable_plugin watch > /dev/null

  run cat "$HARAKA_CONF/plugins"
  assert_line "watch"
  refute_line "# watch"
}

@test "haraka_enable_plugin appends when Haraka ships no entry" {
  printf '# status\n# syslog\n' > "$HARAKA_CONF/plugins"
  haraka_enable_plugin watch > /dev/null
  haraka_enable_plugin p0f > /dev/null

  run cat "$HARAKA_CONF/plugins"
  assert_line "watch"
  assert_line "p0f"

  # the plugins it was not asked about stay as Haraka shipped them
  assert_line "# status"
  assert_line "# syslog"
}

@test "haraka_enable_plugin does not double-add an enabled plugin" {
  printf '# status\nwatch\n' > "$HARAKA_CONF/plugins"
  haraka_enable_plugin watch > /dev/null

  run grep -c '^watch$' "$HARAKA_CONF/plugins"
  assert_output "1"
}

@test "configure_haraka_watch enables the plugin and writes watch.ini" {
  printf '# status\n# syslog\n' > "$HARAKA_CONF/plugins"
  export TOASTER_HOSTNAME="mail.example.com"
  configure_haraka_watch > /dev/null

  run cat "$HARAKA_CONF/plugins"
  assert_line "watch"

  run cat "$HARAKA_CONF/watch.ini"
  assert_output --partial "url=wss://mail.example.com/watch"
  # an empty hostname would leave wss:/// and the browser nowhere to connect
  refute_output --partial "wss:///"
  assert_line --regexp '^url=wss://[a-z0-9.-]+/watch$'
}

@test "configure_haraka_plugins enables the whole default set" {
  printf '# process_title\n# spf\n# bounce\n# uribl\n# attachment\n# dkim\n# karma\n# fcrdns\n' \
    > "$HARAKA_CONF/plugins"
  configure_haraka_plugins > /dev/null

  run cat "$HARAKA_CONF/plugins"
  for p in process_title spf bounce uribl attachment dkim karma fcrdns; do
    assert_line "$p"
  done
  refute_output --partial "# "
}

@test "configure_haraka_plugins is idempotent" {
  printf '# process_title\n# spf\n' > "$HARAKA_CONF/plugins"
  configure_haraka_plugins > /dev/null
  configure_haraka_plugins > /dev/null

  run grep -c '^spf$' "$HARAKA_CONF/plugins"
  assert_output "1"
}

@test "configure_haraka_http binds IPv4 when no public IPv6" {
  rm -f "$HARAKA_CONF/http.ini"
  unset PUBLIC_IP6
  configure_haraka_http

  run cat "$HARAKA_CONF/http.ini"
  assert_output --partial "listen=0.0.0.0:80"
}
