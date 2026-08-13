#!/usr/bin/env bats
# Functional tests for provision/dns.sh
#
# setup_file sources dns.sh once, executing configure_unbound against
# $BATS_FILE_TMPDIR. Tests read what that run produced; only the tests that
# call a function pay to source the definitions.
#
# bats traps DEBUG, which makes every subshell spawn expensive. get_mt6_data
# spawns one per jail via $(get_jail_ip4 ...), so running configure_unbound per
# test cost more than the rest of the file put together.

setup_file() {
  export MT6_TEST_ENV=1
  export STAGE_MNT="$BATS_FILE_TMPDIR/stage"
  export ZFS_DATA_MNT="$BATS_FILE_TMPDIR/data"
  # Single-entry list: only jails referenced by name in dns.sh matter.
  export JAIL_ORDERED_LIST="dns"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export DNS_FNS="$BATS_FILE_TMPDIR/dns_fns_only.sh"

  awk '/^base_snapshot_exists/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/dns.sh" > "$DNS_FNS"

  mkdir -p "$STAGE_MNT/usr/local/etc/unbound" "$STAGE_MNT/usr/local/sbin" \
           "$STAGE_MNT/etc" "$ZFS_DATA_MNT/dns"

  # Minimal unbound.conf.sample with all patterns tweak_unbound_conf targets.
  cat > "$STAGE_MNT/usr/local/etc/unbound/unbound.conf.sample" <<'EOF'
server:
	# prefer-ip6: no
	# interface: 192.0.2.153
	# interface: 192.0.2.154
	# use-syslog: no
	# chroot: "/var/unbound"
	# hide-identity: no
	# hide-version: no
	# access-control: ::ffff:127.0.0.1 allow
	# local-data-ptr: "192.0.2.3 www.example.com"

remote-control:
	control-enable: no

	# fwd.example.com
	# stub-host: ns.example.com.
EOF

  printf '#!/bin/sh\nDESTDIR=/usr/local/etc/unbound\n' \
    > "$STAGE_MNT/usr/local/sbin/unbound-control-setup"

  get_reverse_ip()  { echo "1.15.16.172.in-addr.arpa"; }
  get_reverse_ip6() { echo "1.0.0.0.fd7a.ip6.arpa"; }

  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../provision/dns.sh"
}

setup() {
  load '../test_helper/load'
  UNBOUND_CONF="$STAGE_MNT/usr/local/etc/unbound/unbound.conf"
}

load_dns_fns() {
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  # stubs/mail-toaster.sh does not provide these
  get_reverse_ip()  { echo "1.15.16.172.in-addr.arpa"; }
  get_reverse_ip6() { echo "1.0.0.0.fd7a.ip6.arpa"; }
  # shellcheck source=/dev/null
  . "$DNS_FNS"
}

# --- JAIL variable exports ---

@test "dns - declares the jail extras unbound needs" {
  assert_equal "$JAIL_START_EXTRA" ""
  assert_equal "$JAIL_FSTAB" ""
  echo "$JAIL_CONF_EXTRA" | grep -q 'allow.raw_sockets'
  echo "$JAIL_CONF_EXTRA" | grep -q 'exec.poststart'
  echo "$JAIL_CONF_EXTRA" | grep -q 'exec.prestop'
}

@test "dns - defines the jail lifecycle functions" {
  load_dns_fns
  local _fn
  for _fn in install_unbound configure_unbound start_unbound test_unbound \
             get_mt6_data switch_host_resolver; do
    run type "$_fn"
    assert_success
  done
}

# --- install_unbound behaviour ---

@test "dns - install uses unbound package" {
  load_dns_fns
  stage_pkg_install() { echo "PKG:$*"; }
  run install_unbound
  assert_success
  assert_output --partial "PKG:unbound"
}

# --- get_mt6_data behaviour ---

@test "dns - get_mt6_data serves the toaster's own records" {
  load_dns_fns
  run get_mt6_data
  assert_output --partial "local-zone: $TOASTER_MAIL_DOMAIN"
  assert_output --partial '"stage'
  assert_output --partial 'A '
  assert_output --partial 'v=spf1'
  assert_output --partial 'ip4:'
}

# a hostname inside the mail domain is already covered by the domain's MX
@test "dns - get_mt6_data adds an MX only when the hostname differs" {
  load_dns_fns
  run get_mt6_data
  assert_output --partial "MX 0"

  export TOASTER_HOSTNAME="$TOASTER_MAIL_DOMAIN"
  run get_mt6_data
  refute_output --partial "MX 0"
}

@test "dns - get_mt6_data publishes ip6 in SPF only when PUBLIC_IP6 is set" {
  load_dns_fns
  export PUBLIC_IP6="2001:db8::1"
  run get_mt6_data
  assert_output --partial "ip6:2001:db8::1"

  export PUBLIC_IP6=""
  run get_mt6_data
  refute_output --partial "ip6:2001:db8"
}

@test "dns - get_mt6_data publishes AAAA records when the jails have IPv6" {
  load_dns_fns
  export PUBLIC_IP6="2001:db8::1"
  run get_mt6_data
  assert_output --partial "AAAA"
  assert_output --partial "1.0.0.0.fd7a.ip6.arpa"
}

# an AAAA for an address no jail is listening on is a connection every client
# tries first and waits out
@test "dns - get_mt6_data publishes no AAAA records when the jails have none" {
  load_dns_fns
  export PUBLIC_IP6=""
  run get_mt6_data
  refute_output --partial "AAAA"
  refute_output --partial "ip6.arpa"
}

@test "dns - get_mt6_data still publishes A records without IPv6" {
  load_dns_fns
  export PUBLIC_IP6=""
  run get_mt6_data
  assert_output --partial "local-data: \"dns		A "
  assert_output --partial "in-addr.arpa PTR dns"
}

# --- tweak_unbound_conf outcomes (verified on the post-setup unbound.conf) ---

@test "dns - configure listens on both address families" {
  run grep "interface: 0.0.0.0" "$UNBOUND_CONF"
  assert_success
  run grep "interface: ::0" "$UNBOUND_CONF"
  assert_success
}

@test "dns - configure enables syslog, unsets chroot and hides the server" {
  run grep "use-syslog:" "$UNBOUND_CONF"
  assert_success
  refute_output --partial "# use-syslog"

  run grep 'chroot:' "$UNBOUND_CONF"
  assert_output --partial 'chroot: ""'

  run grep "hide-identity:" "$UNBOUND_CONF"
  assert_output --partial "yes"
  run grep "hide-version:" "$UNBOUND_CONF"
  assert_output --partial "yes"
}

@test "dns - configure adds forward.conf include" {
  run grep 'include: "/data/forward.conf"' "$UNBOUND_CONF"
  assert_success
}

# --- enable_control outcomes (post-setup file/directory checks) ---

@test "dns - enable_control writes the control config under /data" {
  [ -d "$ZFS_DATA_MNT/dns/control" ]
  [ -f "$ZFS_DATA_MNT/dns/control.conf" ]

  run grep "control-enable: yes" "$ZFS_DATA_MNT/dns/control.conf"
  assert_success
  run grep "control-interface: 0.0.0.0" "$ZFS_DATA_MNT/dns/control.conf"
  assert_success
  run grep "^DESTDIR=/data/control" "$STAGE_MNT/usr/local/sbin/unbound-control-setup"
  assert_success
}

# --- start_unbound behaviour ---

@test "dns - start enables unbound and starts it" {
  load_dns_fns
  stage_sysrc() { echo "SYSRC:$*"; }
  stage_exec()  { echo "EXEC:$*"; }
  run start_unbound
  assert_success
  assert_output --partial "SYSRC:unbound_enable=YES"
  assert_output --partial "EXEC:service unbound start"
}

# --- test_unbound behaviour ---

@test "dns - test checks unbound is running and resolves through it" {
  load_dns_fns
  stage_test_running() { echo "RUNNING:$*"; }
  stage_exec()         { echo "EXEC:$*"; }
  run test_unbound
  assert_success
  assert_output --partial "RUNNING:unbound"
  assert_output --partial "EXEC:host dns"
}

@test "dns - test leaves resolv.conf on the dns jail, not the stage IP it probed with" {
  load_dns_fns
  # it writes into the tree, so work on a copy the other tests do not read
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  mkdir -p "$STAGE_MNT/etc"
  stage_test_running() { :; }
  stage_exec()         { :; }

  test_unbound

  run cat "$STAGE_MNT/etc/resolv.conf"
  assert_output --partial "nameserver $(get_jail_ip4 dns)"
  refute_output --partial "$(get_jail_ip4 stage)"
}

# --- switch_host_resolver behaviour ---

@test "dns - switch_host_resolver writes the poststart and prestop hooks" {
  load_dns_fns
  store_exec() { echo "EXEC:$1"; cat - > /dev/null; }

  run switch_host_resolver
  assert_output --partial "EXEC:$(get_jail_host_etc dns)/rc.d/poststart.sh"
  assert_output --partial "EXEC:$(get_jail_host_etc dns)/rc.d/prestop.sh"
}

# --- install_access_conf behaviour ---

setup_access_conf() {
  load_dns_fns
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  mkdir -p "$ZFS_DATA_MNT/dns"
  ACCESS_CONF="$ZFS_DATA_MNT/dns/access.conf"
}

@test "dns - access.conf includes the public IPv4 when one is known" {
  setup_access_conf
  get_public_ip4() { export PUBLIC_IP4="203.0.113.7"; }

  install_access_conf

  run cat "$ACCESS_CONF"
  assert_output --partial "access-control: 203.0.113.7 allow"
}

@test "dns - access.conf omits the entry rather than emit the empty one unbound rejects" {
  setup_access_conf
  get_public_ip4() { export PUBLIC_IP4=""; }

  install_access_conf

  run grep -c "access-control:[[:space:]]*allow" "$ACCESS_CONF"
  assert_output "0"
}

@test "dns - access.conf keeps the jail network entries whatever the public IP" {
  setup_access_conf
  get_public_ip4() { export PUBLIC_IP4=""; }

  install_access_conf

  run cat "$ACCESS_CONF"
  assert_output --partial "access-control: 0.0.0.0/0 refuse"
  assert_output --partial "access-control: 127.0.0.0/8 allow"
  assert_output --partial "access-control: ${JAIL_NET_PREFIX}.0${JAIL_NET_MASK} allow"
}

@test "dns - install_access_conf finds its own PUBLIC_IP4" {
  setup_access_conf

  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../include/network.sh"

  get_public_facing_nic() { export PUBLIC_NIC="em0"; }
  ifconfig() { echo "	inet 198.51.100.4 netmask 0xffffff00"; }

  unset PUBLIC_IP4
  install_access_conf

  run cat "$ACCESS_CONF"
  assert_output --partial "access-control: 198.51.100.4 allow"
}

@test "dns - access.conf includes the public IPv6 when one is known" {
  setup_access_conf
  get_public_ip6() { export PUBLIC_IP6="2001:db8::1"; }

  install_access_conf

  run cat "$ACCESS_CONF"
  assert_output --partial "access-control: 2001:db8::1 allow"
}

# --- outgoing address family follows the host ---

# tweak_unbound_conf rewrites the sample; give each case an untouched copy
unbound_conf_from_sample() {
  load_dns_fns
  export UNBOUND_DIR="$BATS_TEST_TMPDIR/unbound"
  mkdir -p "$UNBOUND_DIR"
  cp "$STAGE_MNT/usr/local/etc/unbound/unbound.conf.sample" "$UNBOUND_DIR/unbound.conf"
}

@test "dns - a dual stack host leaves unbound preferring IPv4" {
  unbound_conf_from_sample
  get_public_ip4() { export PUBLIC_IP4="203.0.113.7"; }
  tweak_unbound_conf

  run grep '^[[:space:]]*prefer-ip6:' "$UNBOUND_DIR/unbound.conf"
  assert_output --partial "prefer-ip6: no"
}

# an IPv6 only host has no NAT rule for the jail network, so every outgoing
# IPv4 query waits out its timeout before unbound tries the IPv6 address
@test "dns - an IPv6 only host prefers IPv6 for resolution" {
  unbound_conf_from_sample
  get_public_ip4() { export PUBLIC_IP4=""; }
  tweak_unbound_conf

  run grep '^[[:space:]]*prefer-ip6:' "$UNBOUND_DIR/unbound.conf"
  assert_output --partial "prefer-ip6: yes"
}

# do-ip4 governs answering as well as asking, and every jail queries dns at its
# private IPv4, so it must stay enabled on a host with no public IPv4
@test "dns - an IPv6 only host still answers over IPv4" {
  unbound_conf_from_sample
  get_public_ip4() { export PUBLIC_IP4=""; }
  tweak_unbound_conf

  run grep -c '^[[:space:]]*do-ip4: no' "$UNBOUND_DIR/unbound.conf"
  assert_output "0"
}

@test "dns - a jail with IPv6 binds the wildcard" {
  unbound_conf_from_sample
  get_public_ip4() { export PUBLIC_IP4="203.0.113.7"; }
  get_public_ip6() { export PUBLIC_IP6="2001:db8::1"; }
  tweak_unbound_conf

  run grep 'interface: ::0' "$UNBOUND_DIR/unbound.conf"
  assert_output --regexp '^[[:space:]]*interface: ::0'
}

@test "dns - a jail without IPv6 leaves that interface commented" {
  unbound_conf_from_sample
  get_public_ip4() { export PUBLIC_IP4="203.0.113.7"; }
  get_public_ip6() { export PUBLIC_IP6=""; }
  tweak_unbound_conf

  run grep 'interface: ::0' "$UNBOUND_DIR/unbound.conf"
  assert_output --regexp '^[[:space:]]*#'
}

@test "dns - the IPv4 interface binds whatever the jail has" {
  local _case
  for _case in "2001:db8::1" ""; do
    unbound_conf_from_sample
    get_public_ip4() { export PUBLIC_IP4="203.0.113.7"; }
    eval "get_public_ip6() { export PUBLIC_IP6=\"$_case\"; }"
    tweak_unbound_conf

    run grep '^[[:space:]]*interface: 0.0.0.0' "$UNBOUND_DIR/unbound.conf"
    assert_success
  done
}
