#!/usr/bin/env bats
# Functional tests for provision/host.sh
#
# configure_pf_conf writes /etc/pf.conf, so setup extracts the function
# definitions and each test calls it with store_config caught in $BATS_TEST_TMPDIR.

setup_file() {
  export HOST_FNS="$BATS_FILE_TMPDIR/host_fns_only.sh"
  sed '/^update_host$/,$d' \
    "$BATS_TEST_DIRNAME/../../provision/host.sh" > "$HOST_FNS"
}

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export PUBLIC_NIC="vtnet0"
  export JAIL_NET_PREFIX="172.16.15"
  export JAIL_NET_MASK="/19"
  export JAIL_NET6="fd7a:e5cd:1fc1:c597:dead:beef:cafe"

  PF_CONF="$BATS_TEST_TMPDIR/pf.conf"

  # shellcheck source=/dev/null
  . "$HOST_FNS"

  # configure_pf_conf names /etc/pf.conf; catch it before it reaches the host
  store_config() { cat - > "$PF_CONF"; }
  # the stub reports and returns; a real one exits, so stop here either way
  fatal_err()    { echo "FATAL: $*"; exit 1; }
}

# get_public_ip4/6 return early when the address is already set, as the real
# ones do for a PUBLIC_IP4 configured in mail-toaster.conf
host_has() {
  export PUBLIC_IP4="$1" PUBLIC_IP6="$2"
  get_public_ip4() { :; }
  get_public_ip6() { :; }
}

# each get_public_ip* resolves its own family's default route into PUBLIC_NIC,
# so the last one called used to decide ext_if for both
@test "configure_pf_conf - each family NATs on its own interface" {
  export PUBLIC_IP4="203.0.113.7" PUBLIC_IP6="2001:db8::1"
  get_public_ip4() { export PUBLIC_NIC="em0"; }
  get_public_ip6() { export PUBLIC_NIC="gif0"; }

  configure_pf_conf > /dev/null

  run cat "$PF_CONF"
  assert_line 'ext_if="em0"'
  assert_line 'ext_if6="gif0"'
}

# scoping the rule to an interface let ssh over a v6 tunnel escape the limit.
# It matches every interface now, so the jail network is excluded by source.
@test "configure_pf_conf - ssh is rate limited on every interface" {
  export PUBLIC_IP4="203.0.113.7" PUBLIC_IP6="2001:db8::1"
  get_public_ip4() { export PUBLIC_NIC="em0"; }
  get_public_ip6() { export PUBLIC_NIC="gif0"; }

  configure_pf_conf > /dev/null

  run cat "$PF_CONF"
  assert_line --partial 'pass in quick proto tcp from ! <ssh_exempt> to port ssh'
  refute_line --partial 'on $ext_if proto tcp to port ssh'
  refute_line --partial 'on $ext_ifs proto tcp to port ssh'
}

@test "configure_pf_conf - jail and loopback sources are exempt from the ssh limit" {
  host_has "203.0.113.7" "2001:db8::1"

  configure_pf_conf > /dev/null

  run cat "$PF_CONF"
  assert_line 'table <ssh_exempt> { $jail_ip4, $jail_ip6, 127.0.0.0/8, ::1 } persist'
}

@test "configure_pf_conf - one interface is not listed twice" {
  export PUBLIC_IP4="203.0.113.7" PUBLIC_IP6="2001:db8::1"
  get_public_ip4() { export PUBLIC_NIC="em0"; }
  get_public_ip6() { export PUBLIC_NIC="em0"; }

  configure_pf_conf > /dev/null

  run cat "$PF_CONF"
  assert_line 'ext_ifs="{ em0 }"'
}

@test "configure_pf_conf - a single family host NATs both rules on its one interface" {
  export PUBLIC_IP4="" PUBLIC_IP6="2001:db8::1"
  get_public_ip4() { export PUBLIC_NIC="gif0"; }
  get_public_ip6() { export PUBLIC_NIC="gif0"; }

  configure_pf_conf > /dev/null

  run cat "$PF_CONF"
  assert_line 'ext_if="gif0"'
  assert_line 'ext_if6="gif0"'
}

@test "configure_pf_conf - a dual stack host NATs and tables both families" {
  host_has "203.0.113.7" "2001:db8::1"

  configure_pf_conf > /dev/null

  run cat "$PF_CONF"
  assert_line 'table <ext_ip>  { $ext_ip4, $ext_ip6 } persist'
  assert_line 'table <ext_ip4> { $ext_ip4 } persist'
  assert_line 'table <ext_ip6> { $ext_ip6 } persist'
  assert_line 'nat on $ext_if  inet  from $jail_ip4 to any -> ($ext_if)'
  assert_line 'nat on $ext_if6 inet6 from $jail_ip6 to any -> <ext_ip6>'
}

# an empty macro inside { } expands to an empty table, which pf accepts. A
# dangling comma in the <ext_ip> list does not parse, so only that list varies.
@test "configure_pf_conf - an IPv4 only host omits IPv6 from the ext_ip list" {
  host_has "203.0.113.7" ""

  configure_pf_conf > /dev/null

  run cat "$PF_CONF"
  assert_line 'table <ext_ip>  { $ext_ip4 } persist'
  refute_line --regexp '^table <ext_ip> .*,'
}

@test "configure_pf_conf - an IPv6 only host omits IPv4 from the ext_ip list" {
  host_has "" "2001:db8::1"

  configure_pf_conf > /dev/null

  run cat "$PF_CONF"
  assert_line 'table <ext_ip>  { $ext_ip6 } persist'
  refute_line --regexp '^table <ext_ip> .*,'
}

@test "configure_pf_conf - the per-family tables and NAT rules never vary" {
  local _case
  for _case in "203.0.113.7 2001:db8::1" "203.0.113.7 " " 2001:db8::1"; do
    # shellcheck disable=SC2086
    host_has $_case
    configure_pf_conf > /dev/null

    run cat "$PF_CONF"
    assert_line 'table <ext_ip4> { $ext_ip4 } persist'
    assert_line 'table <ext_ip6> { $ext_ip6 } persist'
    assert_line 'nat on $ext_if  inet  from $jail_ip4 to any -> ($ext_if)'
    assert_line 'nat on $ext_if6 inet6 from $jail_ip6 to any -> <ext_ip6>'
  done
}

@test "configure_pf_conf - a host with neither family is an error, not a broken pf.conf" {
  host_has "" ""

  run configure_pf_conf
  assert_failure
  assert_output --partial "no public IPv4 or IPv6"
}

@test "configure_pf_conf - without a public NIC it stops before writing" {
  export PUBLIC_NIC=""
  host_has "203.0.113.7" "2001:db8::1"

  run configure_pf_conf
  assert_failure
  assert_output --partial "PUBLIC_NIC unset"
}

# ipinfo.io publishes no AAAA, so on an IPv6 only host every one of these
# lookups fails. Under set -e an unguarded assignment took the host build with it.
@test "lookup_geo_defaults - a failed lookup is not fatal" {
  fetch() { return 1; }

  lookup_geo_defaults

  assert_equal "$_cc$_state$_city" ""
}

@test "lookup_geo_defaults - the values reach the caller" {
  fetch() { echo "US"; }

  lookup_geo_defaults
  assert_equal "$_cc" "US"
}

# openssl req rejects "/C=", so a subject built from a failed lookup produced no
# certificate at all
@test "configure_tls_certs - an unanswered lookup still yields a valid subject" {
  fetch() { return 1; }
  openssl() { echo "openssl $*"; }
  mkdir -p "$BATS_TEST_TMPDIR/ssl/private" "$BATS_TEST_TMPDIR/ssl/certs"

  run configure_tls_certs < /dev/null
  assert_output --partial "subject: /O=Mail Toaster/CN=$TOASTER_HOSTNAME"
  refute_output --partial "/C=/"
  refute_output --partial "/ST=/"
}

@test "configure_tls_certs - an answered lookup names the locality" {
  fetch() { echo "US"; }
  openssl() { echo "openssl $*"; }
  mkdir -p "$BATS_TEST_TMPDIR/ssl/private" "$BATS_TEST_TMPDIR/ssl/certs"

  run configure_tls_certs < /dev/null
  assert_output --partial "subject: /C=US/ST=US/L=US/O=Mail Toaster/CN=$TOASTER_HOSTNAME"
}

# a wildcard listener on the host swallows the jails' traffic whichever family
# it is bound to, and on an IPv6 only host it is the IPv6 one that matters
@test "check_global_listeners - both address families are inspected" {
  local _flags="$BATS_TEST_TMPDIR/sockstat.flags"
  sockstat() { echo "$*" > "$_flags"; }

  check_global_listeners > /dev/null

  run cat "$_flags"
  assert_output --partial "-4"
  assert_output --partial "-6"
}

# --- syslogd listens on the families the jails can send from ---

syslogd_flags() {
  grep()    { return 1; }
  service() { :; }
  sysrc()   { echo "$*" > "$BATS_TEST_TMPDIR/sysrc"; }

  update_syslogd > /dev/null
  cat "$BATS_TEST_TMPDIR/sysrc"
}

# the -a rule already allowed the jail IPv6 range, but nothing ever bound it
@test "update_syslogd - binds IPv6 when the jails have it" {
  host_has "203.0.113.7" "2001:db8::1"

  run syslogd_flags
  assert_output --partial "-b $JAIL_NET_PREFIX.1"
  assert_output --partial "-b [$JAIL_NET6:1]"
  assert_output --partial "-a [$JAIL_NET6:0]/112:*"
}

@test "update_syslogd - binds IPv4 only when the jails have no IPv6" {
  host_has "203.0.113.7" ""

  run syslogd_flags
  assert_output --partial "-b $JAIL_NET_PREFIX.1"
  refute_output --partial "-b [$JAIL_NET6:1]"
}
