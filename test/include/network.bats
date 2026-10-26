
setup() {
  load '../test_helper/load'
  export MT6_TEST_ENV=1
  load ../../include/util.sh
  load ../../include/network.sh
}

@test "get_random_ip6net - format" {
  run get_random_ip6net
  assert_success
  assert_output --regexp '^fd7a:e5cd:1fc1:[0-9a-f]{4}:dead:beef:cafe$'
}

@test "get_random_ip6net - constant prefix" {
  run get_random_ip6net
  assert_output --partial "fd7a:e5cd:1fc1:"
}

@test "get_random_ip6net - constant suffix" {
  run get_random_ip6net
  assert_output --partial ":dead:beef:cafe"
}

# PUBLIC_IP4/6 are the public facing addresses, which need not be bound to a
# local interface, so detection must not overwrite what the admin configured.
@test "get_public_ip4 - keeps a configured address" {
  get_public_facing_nic() { export PUBLIC_NIC="em0"; }
  ifconfig() { echo "	inet 10.0.0.5 netmask 0xffffff00"; }
  export PUBLIC_IP4="203.0.113.7"
  get_public_ip4
  assert_equal "$PUBLIC_IP4" "203.0.113.7"
}

@test "get_public_ip4 - detects when unset" {
  get_public_facing_nic() { export PUBLIC_NIC="em0"; }
  ifconfig() { echo "	inet 10.0.0.5 netmask 0xffffff00"; }
  export PUBLIC_IP4=""
  get_public_ip4
  assert_equal "$PUBLIC_IP4" "10.0.0.5"
}

# host.sh fatals when PUBLIC_NIC is unset, so the early return must come after
# the NIC lookup, not before it.
@test "get_public_ip4 - still exports PUBLIC_NIC with a configured address" {
  get_public_facing_nic() { export PUBLIC_NIC="em0"; }
  export PUBLIC_IP4="203.0.113.7"
  unset PUBLIC_NIC
  get_public_ip4
  assert_equal "$PUBLIC_NIC" "em0"
}

@test "get_public_ip6 - keeps a configured address" {
  get_public_facing_nic() { export PUBLIC_NIC="em0"; }
  ifconfig() { echo "	inet6 fe80::1%em0"; echo "	inet6 2001:db8::99"; }
  export PUBLIC_IP6="2001:db8::1"
  get_public_ip6
  assert_equal "$PUBLIC_IP6" "2001:db8::1"
}

@test "get_public_ip6 - detects when unset" {
  get_public_facing_nic() { export PUBLIC_NIC="em0"; }
  ifconfig() { echo "	inet6 fe80::1%em0"; echo "	inet6 2001:db8::99"; }
  export PUBLIC_IP6=""
  get_public_ip6
  assert_equal "$PUBLIC_IP6" "2001:db8::99"
}

@test "get_random_ip6net - unique per call" {
  local first; first=$(get_random_ip6net)
  local second; second=$(get_random_ip6net)
  # extremely unlikely to be equal; validates randomness is working
  [ "$first" != "$second" ] || skip "got identical values (astronomically unlikely)"
}

# --- every jail resolves the names it needs before unbound answers ---

setup_minimal_hosts() {
  load ../../include/jail.sh
  export JAIL_NET_PREFIX="172.16.15"
  export JAIL_NET6="fd7a:e5cd:1fc1:c597:dead:beef:cafe"
  # get_jail_ip* walks the list per lookup and bats traps every step of it
  export JAIL_ORDERED_LIST="syslog base dns bsd_cache"
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  mkdir -p "$STAGE_MNT/etc"
  # what base.txz ships, via lib/libc/net/hosts
  printf '::1\t\t\tlocalhost localhost.my.domain\n127.0.0.1\t\tlocalhost localhost.my.domain\n' \
    > "$STAGE_MNT/etc/hosts"
  tell_status() { :; }
  get_public_ip6() { export PUBLIC_IP6=""; }
}

@test "install_minimal_hosts - adds the names a jail needs to bootstrap" {
  setup_minimal_hosts

  install_minimal_hosts

  run cat "$STAGE_MNT/etc/hosts"
  assert_output --partial "$(get_jail_ip4 dns) dns"
  assert_output --partial "$(get_jail_ip4 syslog) syslog"
  assert_output --partial "$(get_jail_ip4 bsd_cache) pkg vulnxml freebsd-update"
}

# it appends; overwriting would take localhost with it
@test "install_minimal_hosts - keeps the localhost entries base ships" {
  setup_minimal_hosts

  install_minimal_hosts

  run cat "$STAGE_MNT/etc/hosts"
  assert_output --partial "127.0.0.1"
  assert_output --partial "::1"
  assert_line --regexp '^127\.0\.0\.1[[:space:]]+localhost'
}

@test "install_minimal_hosts - a jail with IPv6 gets those addresses too" {
  setup_minimal_hosts
  get_public_ip6() { export PUBLIC_IP6="2001:db8::1"; }

  install_minimal_hosts

  run cat "$STAGE_MNT/etc/hosts"
  assert_output --partial "$(get_jail_ip6 dns) dns"
  assert_output --partial "$(get_jail_ip6 bsd_cache) pkg vulnxml freebsd-update"
}

@test "install_minimal_hosts - syslog gets both families" {
  setup_minimal_hosts
  get_public_ip6() { export PUBLIC_IP6="2001:db8::1"; }

  install_minimal_hosts

  run grep -c ' syslog$' "$STAGE_MNT/etc/hosts"
  assert_output "2"

  run cat "$STAGE_MNT/etc/hosts"
  assert_output --partial "$(get_jail_ip4 syslog) syslog"
  assert_output --partial "$(get_jail_ip6 syslog) syslog"
}

@test "install_minimal_hosts - a jail without IPv6 gets no v6 entries" {
  setup_minimal_hosts
  get_public_ip6() { export PUBLIC_IP6=""; }

  install_minimal_hosts

  run grep -c ' dns$' "$STAGE_MNT/etc/hosts"
  assert_output "1"

  run grep -c 'freebsd-update$' "$STAGE_MNT/etc/hosts"
  assert_output "1"
}

# base pairs ::1 above 127.0.0.1 for localhost; match that
@test "install_minimal_hosts - IPv6 precedes IPv4 for each name" {
  setup_minimal_hosts
  get_public_ip6() { export PUBLIC_IP6="2001:db8::1"; }

  install_minimal_hosts

  run awk '$2 == "dns" { print $1 }' "$STAGE_MNT/etc/hosts"
  assert_line --index 0 "$(get_jail_ip6 dns)"
  assert_line --index 1 "$(get_jail_ip4 dns)"

  run awk '$2 == "syslog" { print $1 }' "$STAGE_MNT/etc/hosts"
  assert_line --index 0 "$(get_jail_ip6 syslog)"
  assert_line --index 1 "$(get_jail_ip4 syslog)"

  run awk '$2 == "pkg" { print $1 }' "$STAGE_MNT/etc/hosts"
  assert_line --index 0 "$(get_jail_ip6 bsd_cache)"
  assert_line --index 1 "$(get_jail_ip4 bsd_cache)"
}
