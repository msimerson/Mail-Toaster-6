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

# --- smtp_forward.ini ---

main_section() {
  awk '/^[[:space:]]*\[/ { exit } { print }' "$1"
}

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

@test "haraka_ini_default adds a key under an explicit [main]" {
  printf '; comment\n[main]\nhost=172.16.15.8\n\n[example.com]\nhost=172.16.15.9\n' \
    > "$HARAKA_CONF/smtp_forward.ini"

  haraka_ini_default smtp_forward.ini enable_outbound true

  run cat "$HARAKA_CONF/smtp_forward.ini"
  assert_output "; comment
[main]
enable_outbound=true
host=172.16.15.8

[example.com]
host=172.16.15.9"
}

# --- qmail-deliverable.ini ---

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

# qmail-deliverable >= 1.4.1 falls back to the main section's split
@test "configure_haraka_qmail_deliverable leaves the domain sections alone" {
  printf 'host=172.16.15.8\n\n[example.com]\nnext_hop=lmtp://172.16.15.15\n\n  [example.net]\n  host=172.16.15.9\n' \
    > "$HARAKA_CONF/qmail-deliverable.ini"

  configure_haraka_qmail_deliverable

  run ini_section "$HARAKA_CONF/qmail-deliverable.ini" example.com
  assert_output "next_hop=lmtp://172.16.15.15"
  run ini_section "$HARAKA_CONF/qmail-deliverable.ini" example.net
  assert_output "  host=172.16.15.9"
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

# --- config/me ---

@test "configure_haraka_me writes the hostname when config/me is missing" {
  export TOASTER_HOSTNAME="mail.example.com"
  rm -f "$HARAKA_CONF/me"

  configure_haraka_me

  assert_equal "$(cat "$HARAKA_CONF/me")" "mail.example.com"
}

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

# --- jails that send mail may relay ---

# $1 overrides the jails, all of which are provisioned
relay_jails() {
  HARAKA_RELAY_JAILS="${1-"php wordpress"}"
  local _j
  for _j in $HARAKA_RELAY_JAILS; do mkdir -p "$ZFS_JAIL_MNT/$_j"; done
}

@test "configure_haraka_relay enables the relay plugin first, with the ACL on" {
  printf '# syslog\nconnect.p0f\nspf\n' > "$HARAKA_CONF/plugins"

  relay_jails
  configure_haraka_relay

  [ "$(head -n 1 "$HARAKA_CONF/plugins")" = "relay" ]
  run grep -c '^relay$' "$HARAKA_CONF/plugins"
  assert_output "1"

  run cat "$HARAKA_CONF/relay.ini"
  assert_success
  assert_line "[relay]"
  assert_line "acl=true"
}

@test "configure_haraka_relay allows the IPv4 of each relaying jail, and only those" {
  unset PUBLIC_IP6
  relay_jails
  configure_haraka_relay

  run cat "$HARAKA_CONF/relay_acl_allow"
  assert_success
  assert_line "$(get_jail_ip4 php)/32"
  assert_line "$(get_jail_ip4 wordpress)/32"
  refute_output --partial "$(get_jail_ip4 haraka)"
  refute_output --partial "172.16.15.0/"
  refute_output --partial ":"
}

@test "configure_haraka_relay also allows the IPv6 when the host has one" {
  export PUBLIC_IP6="2001:db8::1"
  relay_jails
  configure_haraka_relay

  run cat "$HARAKA_CONF/relay_acl_allow"
  assert_line "$(get_jail_ip6 php)/128"
  assert_line "$(get_jail_ip4 php)/32"
}

@test "HARAKA_RELAY_JAILS picks the jails" {
  unset PUBLIC_IP6
  relay_jails joomla
  configure_haraka_relay

  run cat "$HARAKA_CONF/relay_acl_allow"
  assert_output "$(get_jail_ip4 joomla)/32"
}

@test "configure_haraka_relay skips a jail that is not provisioned" {
  unset PUBLIC_IP6
  HARAKA_RELAY_JAILS="php wordpress"
  mkdir -p "$ZFS_JAIL_MNT/wordpress"

  configure_haraka_relay

  run cat "$HARAKA_CONF/relay_acl_allow"
  assert_output "$(get_jail_ip4 wordpress)/32"
}

@test "configure_haraka_relay skips a name outside JAIL_ORDERED_LIST, whatever DNS says" {
  unset PUBLIC_IP6
  relay_jails "wordpress elsewhere"
  eval "$(declare -f get_jail_ip4 | sed '1s/get_jail_ip4/list_get_jail_ip4/')"
  get_jail_ip4() { if [ "$1" = elsewhere ]; then echo "192.0.2.99"; else list_get_jail_ip4 "$1"; fi; }

  configure_haraka_relay

  run cat "$HARAKA_CONF/relay_acl_allow"
  assert_output "$(get_jail_ip4 wordpress)/32"
}

@test "an empty HARAKA_RELAY_JAILS leaves relaying off" {
  printf 'spf\n' > "$HARAKA_CONF/plugins"
  relay_jails ""
  configure_haraka_relay

  [ ! -e "$HARAKA_CONF/relay.ini" ]
  [ ! -e "$HARAKA_CONF/relay_acl_allow" ]
  run grep -c relay "$HARAKA_CONF/plugins"
  assert_output "0"
}

@test "configure_haraka_relay twice changes nothing" {
  export PUBLIC_IP6="2001:db8::1"
  relay_jails
  configure_haraka_relay
  local _p _i _a
  _p=$(cat "$HARAKA_CONF/plugins"); _i=$(cat "$HARAKA_CONF/relay.ini")
  _a=$(cat "$HARAKA_CONF/relay_acl_allow")

  configure_haraka_relay
  [ "$_p" = "$(cat "$HARAKA_CONF/plugins")" ]
  [ "$_i" = "$(cat "$HARAKA_CONF/relay.ini")" ]
  [ "$_a" = "$(cat "$HARAKA_CONF/relay_acl_allow")" ]
}

@test "configure_haraka_relay keeps the entries an admin added" {
  unset PUBLIC_IP6
  printf '192.0.2.7/32\n' > "$HARAKA_CONF/relay_acl_allow"
  relay_jails
  configure_haraka_relay
  configure_haraka_relay

  run cat "$HARAKA_CONF/relay_acl_allow"
  assert_line "192.0.2.7/32"
  assert_line "$(get_jail_ip4 php)/32"
}

@test "configure_haraka_relay does not duplicate an entry the admin already made" {
  unset PUBLIC_IP6
  printf '%s/32\n' "$(get_jail_ip4 php)" > "$HARAKA_CONF/relay_acl_allow"
  relay_jails
  configure_haraka_relay

  run grep -c "$(get_jail_ip4 php)/32" "$HARAKA_CONF/relay_acl_allow"
  assert_output "1"
}

@test "configure_haraka_relay removes the entry of a jail that left HARAKA_RELAY_JAILS" {
  unset PUBLIC_IP6
  relay_jails
  printf '192.0.2.7/32\n' >> "$HARAKA_CONF/relay_acl_allow"
  configure_haraka_relay

  relay_jails php
  configure_haraka_relay

  run cat "$HARAKA_CONF/relay_acl_allow"
  assert_line "$(get_jail_ip4 php)/32"
  assert_line "192.0.2.7/32"
  refute_output --partial "$(get_jail_ip4 wordpress)"
}

@test "configure_haraka_relay replaces the entry of a jail that moved" {
  unset PUBLIC_IP6
  relay_jails php
  configure_haraka_relay
  local _old; _old="$(get_jail_ip4 php)/32"

  JAIL_ORDERED_LIST="syslog base newjail $JAIL_ORDERED_LIST"
  configure_haraka_relay

  run cat "$HARAKA_CONF/relay_acl_allow"
  assert_line "$(get_jail_ip4 php)/32"
  refute_line "$_old"
}

@test "configure_haraka_relay removes the IPv6 entries when the host loses its address" {
  export PUBLIC_IP6="2001:db8::1"
  relay_jails php
  configure_haraka_relay
  run grep -c ":" "$HARAKA_CONF/relay_acl_allow"
  assert_output "1"

  unset PUBLIC_IP6
  configure_haraka_relay
  run grep -c ":" "$HARAKA_CONF/relay_acl_allow"
  assert_output "0"
}

@test "configure_haraka_relay turns on an acl that is off or commented out" {
  printf '[relay]\nforce_routing=x\n; acl=false\n' > "$HARAKA_CONF/relay.ini"
  relay_jails
  configure_haraka_relay
  run cat "$HARAKA_CONF/relay.ini"
  assert_line "acl=true"
  assert_line "force_routing=x"
  refute_output --partial "acl=false"

  printf '[relay]\nforce_routing=x\n' > "$HARAKA_CONF/relay.ini"
  relay_jails
  configure_haraka_relay
  run cat "$HARAKA_CONF/relay.ini"
  assert_line "acl=true"
  assert_line "force_routing=x"
}
