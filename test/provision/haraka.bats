#!/usr/bin/env bats
# Functional tests for provision/haraka.sh
#
# Every test edits the config tree, so each gets its own $BATS_TEST_TMPDIR.

setup() {
  load helper

  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"

  export ZFS_DATA_MNT="$STAGE_MNT/data"
  export ZFS_JAIL_MNT="$STAGE_MNT/jails"
  export ZFS_DATA_VOL="zroot${ZFS_DATA_MNT}"
  export ZFS_JAIL_VOL="zroot${ZFS_JAIL_MNT}"

  HARAKA_CONF="$ZFS_DATA_MNT/haraka/config"

  # configure_haraka_syslog uncomments the syslog plugin in an existing file
  mkdir -p "$HARAKA_CONF"
  printf '# syslog\n' > "$HARAKA_CONF/plugins"

  provision_fns haraka preinstall_checks
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

tls_setup() {
  load '../../include/tls.sh'
  export TOASTER_HOSTNAME="mail.example.com"
  HOST_TLS_CRT="$BATS_TEST_TMPDIR/server.crt"
  HOST_TLS_KEY="$BATS_TEST_TMPDIR/server.key"
  echo host-crt > "$HOST_TLS_CRT"
  echo host-key > "$HOST_TLS_KEY"
  haraka_enable_plugin() { :; }
}

@test "configure_haraka_tls writes one PEM when config/tls exists" {
  tls_setup
  mkdir -p "$HARAKA_CONF/tls"

  ( set -e; configure_haraka_tls )

  assert_equal "$(cat "$HARAKA_CONF/tls/mail.example.com.pem")" "$(printf 'host-key\nhost-crt')"
  assert [ ! -e "$HARAKA_CONF/tls_key.pem" ]
}

@test "configure_haraka_tls writes tls_cert.pem and tls_key.pem without config/tls" {
  tls_setup

  ( set -e; configure_haraka_tls )

  assert_equal "$(cat "$HARAKA_CONF/tls_cert.pem")" host-crt
  assert_equal "$(cat "$HARAKA_CONF/tls_key.pem")" host-key
  assert_equal "$(_file_mode "$HARAKA_CONF/tls_key.pem")" 600
}

@test "configure_haraka_tls replaces a tls_cert.pem that has no key" {
  tls_setup
  echo le-crt > "$HARAKA_CONF/tls_cert.pem"

  ( set -e; configure_haraka_tls )

  assert_equal "$(cat "$HARAKA_CONF/tls_key.pem")" host-key
  assert_equal "$(cat "$HARAKA_CONF/tls_cert.pem")" host-crt
  assert_equal "$(cat "$HARAKA_CONF/tls_cert.pem.orphan")" le-crt
}

@test "configure_haraka_tls leaves an installed pair alone" {
  tls_setup
  echo le-crt > "$HARAKA_CONF/tls_cert.pem"
  echo le-key > "$HARAKA_CONF/tls_key.pem"

  ( set -e; configure_haraka_tls )

  assert_equal "$(cat "$HARAKA_CONF/tls_cert.pem")" le-crt
  assert_equal "$(cat "$HARAKA_CONF/tls_key.pem")" le-key
}

@test "configure_haraka_tls skips when the host has no cert" {
  tls_setup
  rm "$HOST_TLS_KEY"

  ( set -e; configure_haraka_tls )

  assert [ ! -e "$HARAKA_CONF/tls_cert.pem" ]
}

# --- authenticated mail to a vpopmail alias ---
#
# qmail-deliverable leaves queue.next_hop at the Dovecot LMTP URL for an alias
# too. For an authenticated sender smtp_forward stands aside unless
# enable_outbound is set, and outbound then follows that next_hop to Dovecot,
# which answers "550 5.1.1 User doesn't exist".

# the keys that are in the main section, ie before the first [section]
main_section() {
  awk '/^[[:space:]]*\[/ { exit } { print }' "$1"
}

# the lines of one [section], an indented header included
ini_section() {
  awk -v want="$2" '
    /^[[:space:]]*\[/ { s = $0; sub(/^[[:space:]]*\[/, "", s); sub(/\].*$/, "", s); on = (s == want); next }
    on { print }
  ' "$1"
}

@test "configure_haraka_smtp_forward enables outbound forwarding on a new install" {
  configure_haraka_smtp_forward

  run cat "$HARAKA_CONF/smtp_forward.ini"
  assert_success
  assert_output --partial "host=172.16.15."
  assert_output --partial "port=25"
  assert_output --partial "enable_outbound=true"
}

# smtp_forward.ini is only written when missing, so a host provisioned before
# this existed has to get the key too
@test "configure_haraka_smtp_forward adds enable_outbound to an existing file" {
  printf 'host=172.16.15.8\nport=25\n' > "$HARAKA_CONF/smtp_forward.ini"

  configure_haraka_smtp_forward

  run main_section "$HARAKA_CONF/smtp_forward.ini"
  assert_line "enable_outbound=true"
  assert_line "host=172.16.15.8"
  assert_line "port=25"
}

@test "configure_haraka_smtp_forward keeps an operator's enable_outbound" {
  printf 'host=172.16.15.8\nenable_outbound = false\n' > "$HARAKA_CONF/smtp_forward.ini"

  configure_haraka_smtp_forward

  run cat "$HARAKA_CONF/smtp_forward.ini"
  assert_output --partial "enable_outbound = false"
  refute_output --partial "enable_outbound=true"
}

# a per-domain setting is not the global one
@test "configure_haraka_smtp_forward sets the main key when only a domain has one" {
  printf 'host=172.16.15.8\n\n[example.com]\nenable_outbound=false\n' \
    > "$HARAKA_CONF/smtp_forward.ini"

  configure_haraka_smtp_forward

  run main_section "$HARAKA_CONF/smtp_forward.ini"
  assert_line "enable_outbound=true"
  run cat "$HARAKA_CONF/smtp_forward.ini"
  assert_output --partial "[example.com]"
  assert_output --partial "enable_outbound=false"
}

@test "configure_haraka_smtp_forward is idempotent" {
  configure_haraka_smtp_forward
  configure_haraka_smtp_forward

  run grep -c '^enable_outbound' "$HARAKA_CONF/smtp_forward.ini"
  assert_output "1"
}

# Haraka accepts an indented [section]: the key under it is not main's
@test "configure_haraka_smtp_forward sets the main key when a domain's section is indented" {
  printf 'host=172.16.15.8\n\n  [example.com]\n  enable_outbound=false\n' \
    > "$HARAKA_CONF/smtp_forward.ini"

  configure_haraka_smtp_forward

  run main_section "$HARAKA_CONF/smtp_forward.ini"
  assert_line "enable_outbound=true"
  run ini_section "$HARAKA_CONF/smtp_forward.ini" example.com
  assert_output --partial "enable_outbound=false"
}

@test "configure_haraka_smtp_forward keeps an enable_outbound set under [main]" {
  printf '[main]\nhost=172.16.15.8\nenable_outbound=false\n' > "$HARAKA_CONF/smtp_forward.ini"

  configure_haraka_smtp_forward

  run grep -c '^enable_outbound' "$HARAKA_CONF/smtp_forward.ini"
  assert_output "1"
  run cat "$HARAKA_CONF/smtp_forward.ini"
  refute_output --partial "enable_outbound=true"
}

# --- a message for an alias and a mailbox ---

@test "configure_haraka_qmail_deliverable keeps the routing and defers a split" {
  configure_haraka_qmail_deliverable

  run cat "$HARAKA_CONF/qmail-deliverable.ini"
  assert_success
  assert_output --partial "check_outbound=true"
  assert_output --partial "queue=smtp_forward"
  assert_output --regexp "next_hop=lmtp://172\.16\.15\."
  assert_output --partial "split=defer"
}

@test "configure_haraka_qmail_deliverable adds split to an existing file in the main section" {
  printf 'check_outbound=true\nhost=172.16.15.8\nqueue=smtp_forward\n\n[example.com]\nnext_hop=lmtp://172.16.15.15\n' \
    > "$HARAKA_CONF/qmail-deliverable.ini"

  configure_haraka_qmail_deliverable

  run main_section "$HARAKA_CONF/qmail-deliverable.ini"
  assert_line "split=defer"
  assert_line "queue=smtp_forward"
  run cat "$HARAKA_CONF/qmail-deliverable.ini"
  assert_output --partial "next_hop=lmtp://172.16.15.15"
}

@test "configure_haraka_qmail_deliverable sets split in the main section when a domain's is indented" {
  printf 'host=172.16.15.8\n\n  [example.com]\n  split=outbound\n' > "$HARAKA_CONF/qmail-deliverable.ini"

  configure_haraka_qmail_deliverable

  run main_section "$HARAKA_CONF/qmail-deliverable.ini"
  assert_line "split=defer"
  run ini_section "$HARAKA_CONF/qmail-deliverable.ini" example.com
  assert_output --partial "split=outbound"
}

# a domain with its own section does not inherit the main section's split
@test "configure_haraka_qmail_deliverable sets split in a domain's own section" {
  printf 'host=172.16.15.8\nqueue=smtp_forward\n\n[example.com]\nnext_hop=lmtp://172.16.15.15\n\n[example.net]\nhost=172.16.15.9\n' \
    > "$HARAKA_CONF/qmail-deliverable.ini"

  configure_haraka_qmail_deliverable

  run ini_section "$HARAKA_CONF/qmail-deliverable.ini" example.com
  assert_line "split=defer"
  assert_line "next_hop=lmtp://172.16.15.15"
  run ini_section "$HARAKA_CONF/qmail-deliverable.ini" example.net
  assert_line "split=defer"
  assert_line "host=172.16.15.9"
}

@test "configure_haraka_qmail_deliverable keeps a domain's own split, indented or not" {
  printf 'host=172.16.15.8\n\n[example.com]\nsplit=outbound\n\n  [example.net]\n  split = outbound\n\n[example.org]\nnext_hop=lmtp://x\n' \
    > "$HARAKA_CONF/qmail-deliverable.ini"

  configure_haraka_qmail_deliverable

  run ini_section "$HARAKA_CONF/qmail-deliverable.ini" example.com
  assert_output "split=outbound"
  run ini_section "$HARAKA_CONF/qmail-deliverable.ini" example.net
  refute_output --partial "defer"
  run ini_section "$HARAKA_CONF/qmail-deliverable.ini" example.org
  assert_line "split=defer"
}

@test "configure_haraka_qmail_deliverable does not add split twice to a domain" {
  printf 'host=172.16.15.8\n\n[example.com]\nnext_hop=lmtp://172.16.15.15\n' \
    > "$HARAKA_CONF/qmail-deliverable.ini"

  configure_haraka_qmail_deliverable
  cp "$HARAKA_CONF/qmail-deliverable.ini" "$BATS_TEST_TMPDIR/once"
  configure_haraka_qmail_deliverable

  run cmp "$HARAKA_CONF/qmail-deliverable.ini" "$BATS_TEST_TMPDIR/once"
  assert_success
  run grep -c '^split' "$HARAKA_CONF/qmail-deliverable.ini"
  assert_output "2"
}

@test "configure_haraka_qmail_deliverable leaves a [main] section's split alone" {
  printf '[main]\nhost=172.16.15.8\nsplit=outbound\n' > "$HARAKA_CONF/qmail-deliverable.ini"

  configure_haraka_qmail_deliverable

  run grep -c '^split' "$HARAKA_CONF/qmail-deliverable.ini"
  assert_output "1"
  run cat "$HARAKA_CONF/qmail-deliverable.ini"
  refute_output --partial "split=defer"
}

@test "configure_haraka_qmail_deliverable keeps an operator's split" {
  printf 'host=172.16.15.8\nsplit=outbound\n' > "$HARAKA_CONF/qmail-deliverable.ini"

  configure_haraka_qmail_deliverable

  run cat "$HARAKA_CONF/qmail-deliverable.ini"
  assert_output --partial "split=outbound"
  refute_output --partial "split=defer"
}

# --- DKIM signing ---

# the dkim plugin reads dkim.ini, and its shipped default signs nothing
dkim_setup() {
  export TOASTER_MAIL_DOMAIN="example.com"
  local _dkim="$STAGE_MNT/usr/local/lib/node_modules/haraka/node_modules/haraka-plugin-dkim/config"
  mkdir -p "$_dkim"
  cat > "$_dkim/dkim.ini" <<'EOF'
[main]


[sign]
enabled = false
selector = mail
domain = example.com
headers = From, Sender, Subject

[canon]
; body = relaxed  ; allowed: simple, relaxed; default: simple


[verify]
enabled = true
EOF
  # the key generation is not under test
  mkdir -p "$HARAKA_CONF/dkim/example.com"
  touch "$HARAKA_CONF/dkim/dkim_key_gen.sh"
}

@test "configure_haraka_dkim creates dkim.ini with signing enabled" {
  dkim_setup
  configure_haraka_dkim

  run awk '/^\[sign\]/ { s = 1; next } /^\[/ { s = 0 } s' "$HARAKA_CONF/dkim.ini"
  assert_line "enabled = true"
  refute_output --partial "enabled = false"
}

@test "configure_haraka_dkim leaves verification and the other settings alone" {
  dkim_setup
  configure_haraka_dkim

  run awk '/^\[verify\]/ { s = 1; next } /^\[/ { s = 0 } s' "$HARAKA_CONF/dkim.ini"
  assert_line "enabled = true"
  run cat "$HARAKA_CONF/dkim.ini"
  assert_output --partial "selector = mail"
  assert_output --partial "headers = From, Sender, Subject"
}

@test "configure_haraka_dkim keeps a dkim.ini an operator edited" {
  dkim_setup
  printf '[sign]\nenabled = false\nselector = jun2026\n' > "$HARAKA_CONF/dkim.ini"
  cp "$HARAKA_CONF/dkim.ini" "$BATS_TEST_TMPDIR/dkim.ini.orig"

  configure_haraka_dkim

  cmp "$HARAKA_CONF/dkim.ini" "$BATS_TEST_TMPDIR/dkim.ini.orig"
}

# --- the name Haraka greets with ---

@test "configure_haraka_me writes the hostname when config/me is missing" {
  export TOASTER_HOSTNAME="mail.example.com"
  rm -f "$HARAKA_CONF/me"

  configure_haraka_me

  assert_equal "$(cat "$HARAKA_CONF/me")" "mail.example.com"
}

# haraka -i writes the jail's own name, which sent a new host's EHLO as "haraka"
@test "configure_haraka_me replaces the jail hostname haraka -i wrote" {
  export TOASTER_HOSTNAME="mail.example.com"
  echo haraka > "$HARAKA_CONF/me"

  configure_haraka_me

  assert_equal "$(cat "$HARAKA_CONF/me")" "mail.example.com"
}

@test "configure_haraka_me replaces an empty or blank config/me" {
  export TOASTER_HOSTNAME="mail.example.com"
  printf ' \n' > "$HARAKA_CONF/me"

  configure_haraka_me

  assert_equal "$(cat "$HARAKA_CONF/me")" "mail.example.com"
}

@test "configure_haraka_me keeps a name an operator chose" {
  export TOASTER_HOSTNAME="mail.example.com"
  echo mx1.example.net > "$HARAKA_CONF/me"

  configure_haraka_me

  assert_equal "$(cat "$HARAKA_CONF/me")" "mx1.example.net"
}

@test "configure_haraka_me is idempotent" {
  export TOASTER_HOSTNAME="mail.example.com"
  echo haraka > "$HARAKA_CONF/me"

  configure_haraka_me
  configure_haraka_me

  assert_equal "$(cat "$HARAKA_CONF/me")" "mail.example.com"
}
