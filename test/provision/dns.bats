#!/usr/bin/env bats
# Functional tests for provision/dns.sh
#
# Performance design:
# - setup_file() runs ONCE: sources the full dns.sh (executing configure_unbound)
#   and saves the resulting file tree + stripped function definitions to
#   BATS_FILE_TMPDIR.
# - setup() runs per-test (fast): copies the cached templates and sources only
#   the function definitions (no execution block, no expensive subshells).
#
# Root cause of slowness: bats installs DEBUG traps that make every subshell
# spawn expensive. configure_unbound calls get_mt6_data which spawns many
# subshells via $(get_jail_ip ...) for each jail. Running it 43 times would
# take ~25s; running it once takes ~1s.

setup_file() {
  local _stage="$BATS_FILE_TMPDIR/stage"
  local _data="$BATS_FILE_TMPDIR/data"
  local _fns="$BATS_FILE_TMPDIR/dns_fns_only.sh"

  # Strip the execution block (everything from base_snapshot_exists onward)
  # so setup() can source function definitions without re-running configure_unbound.
  awk '/^base_snapshot_exists/{exit} {print}' \
    "$BATS_TEST_DIRNAME/../../provision/dns.sh" > "$_fns"

  # Build the file templates by running configure_unbound exactly once.
  export MT6_TEST_ENV=1
  export STAGE_MNT="$_stage"
  export ZFS_DATA_MNT="$_data"
  # Single-entry list: only jails referenced by name in dns.sh matter.
  export JAIL_ORDERED_LIST="dns"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  mkdir -p "$_stage/usr/local/etc/unbound" "$_stage/usr/local/sbin" \
           "$_stage/etc" "$_data/dns"

  # Minimal unbound.conf.sample with all patterns tweak_unbound_conf targets.
  cat > "$_stage/usr/local/etc/unbound/unbound.conf.sample" <<'EOF'
server:
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
    > "$_stage/usr/local/sbin/unbound-control-setup"

  get_reverse_ip()  { echo "1.15.16.172.in-addr.arpa"; }
  get_reverse_ip6() { echo "1.0.0.0.fd7a.ip6.arpa"; }

  # Source full dns.sh once: runs configure_unbound to produce the templates.
  # shellcheck source=/dev/null
  . "$BATS_TEST_DIRNAME/../../provision/dns.sh"
}

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export JAIL_ORDERED_LIST="dns"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  # Fresh per-test directories, restored from the cached templates (fast cp).
  export STAGE_MNT; STAGE_MNT=$(mktemp -d)
  export ZFS_DATA_MNT; ZFS_DATA_MNT=$(mktemp -d)
  cp -r "$BATS_FILE_TMPDIR/stage/." "$STAGE_MNT/"
  cp -r "$BATS_FILE_TMPDIR/data/." "$ZFS_DATA_MNT/"

  # Stub reverse-IP helpers (not provided by stubs/mail-toaster.sh).
  get_reverse_ip()  { echo "1.15.16.172.in-addr.arpa"; }
  get_reverse_ip6() { echo "1.0.0.0.fd7a.ip6.arpa"; }

  # Source function definitions only (no execution block = no configure_unbound).
  # shellcheck source=/dev/null
  . "$BATS_FILE_TMPDIR/dns_fns_only.sh"
}

teardown() {
  rm -rf "$STAGE_MNT" "$ZFS_DATA_MNT"
}

# --- JAIL variable exports ---

@test "dns - JAIL_START_EXTRA is empty" {
  assert_equal "$JAIL_START_EXTRA" ""
}

@test "dns - JAIL_CONF_EXTRA contains allow.raw_sockets" {
  echo "$JAIL_CONF_EXTRA" | grep -q 'allow.raw_sockets'
}

@test "dns - JAIL_CONF_EXTRA contains exec.poststart" {
  echo "$JAIL_CONF_EXTRA" | grep -q 'exec.poststart'
}

@test "dns - JAIL_CONF_EXTRA contains exec.prestop" {
  echo "$JAIL_CONF_EXTRA" | grep -q 'exec.prestop'
}

@test "dns - JAIL_FSTAB is empty" {
  assert_equal "$JAIL_FSTAB" ""
}

# --- Function existence ---

@test "dns - defines install_unbound" {
  run type install_unbound
  assert_success
}

@test "dns - defines configure_unbound" {
  run type configure_unbound
  assert_success
}

@test "dns - defines start_unbound" {
  run type start_unbound
  assert_success
}

@test "dns - defines test_unbound" {
  run type test_unbound
  assert_success
}

@test "dns - defines get_mt6_data" {
  run type get_mt6_data
  assert_success
}

@test "dns - defines switch_host_resolver" {
  run type switch_host_resolver
  assert_success
}

# --- install_unbound behaviour ---

@test "dns - install uses unbound package" {
  stage_pkg_install() { echo "PKG:$*"; }
  run install_unbound
  assert_success
  assert_output --partial "PKG:unbound"
}

# --- get_mt6_data behaviour ---

@test "dns - get_mt6_data includes local-zone for mail domain" {
  run get_mt6_data
  assert_output --partial "local-zone: $TOASTER_MAIL_DOMAIN"
}

@test "dns - get_mt6_data includes stage A record" {
  run get_mt6_data
  assert_output --partial '"stage'
  assert_output --partial 'A '
}

@test "dns - get_mt6_data includes SPF TXT record" {
  run get_mt6_data
  assert_output --partial 'v=spf1'
  assert_output --partial 'ip4:'
}

@test "dns - get_mt6_data adds MX record when hostname differs from mail domain" {
  # Default stub values: TOASTER_HOSTNAME=mail.example.com, TOASTER_MAIL_DOMAIN=example.com
  run get_mt6_data
  assert_output --partial "MX 0"
}

@test "dns - get_mt6_data omits MX record when hostname equals mail domain" {
  local _saved="$TOASTER_HOSTNAME"
  export TOASTER_HOSTNAME="$TOASTER_MAIL_DOMAIN"
  run get_mt6_data
  export TOASTER_HOSTNAME="$_saved"
  refute_output --partial "MX 0"
}

@test "dns - get_mt6_data includes PUBLIC_IP6 in SPF when set" {
  local _saved="$PUBLIC_IP6"
  export PUBLIC_IP6="2001:db8::1"
  run get_mt6_data
  export PUBLIC_IP6="$_saved"
  assert_output --partial "ip6:2001:db8::1"
}

@test "dns - get_mt6_data omits PUBLIC_IP6 from SPF when unset" {
  local _saved="$PUBLIC_IP6"
  export PUBLIC_IP6=""
  run get_mt6_data
  export PUBLIC_IP6="$_saved"
  refute_output --partial "ip6:2001:db8"
}

# --- tweak_unbound_conf outcomes (verified on the post-setup unbound.conf) ---

@test "dns - configure sets interface to 0.0.0.0" {
  run grep "interface: 0.0.0.0" "$STAGE_MNT/usr/local/etc/unbound/unbound.conf"
  assert_success
}

@test "dns - configure sets interface to ::0" {
  run grep "interface: ::0" "$STAGE_MNT/usr/local/etc/unbound/unbound.conf"
  assert_success
}

@test "dns - configure enables use-syslog" {
  run grep "use-syslog:" "$STAGE_MNT/usr/local/etc/unbound/unbound.conf"
  assert_success
  refute_output --partial "# use-syslog"
}

@test "dns - configure sets chroot to empty string" {
  run grep 'chroot:' "$STAGE_MNT/usr/local/etc/unbound/unbound.conf"
  assert_output --partial 'chroot: ""'
}

@test "dns - configure hides identity" {
  run grep "hide-identity:" "$STAGE_MNT/usr/local/etc/unbound/unbound.conf"
  assert_output --partial "yes"
}

@test "dns - configure hides version" {
  run grep "hide-version:" "$STAGE_MNT/usr/local/etc/unbound/unbound.conf"
  assert_output --partial "yes"
}

@test "dns - configure adds forward.conf include" {
  run grep 'include: "/data/forward.conf"' "$STAGE_MNT/usr/local/etc/unbound/unbound.conf"
  assert_success
}

# --- enable_control outcomes (post-setup file/directory checks) ---

@test "dns - enable_control creates control directory" {
  [ -d "$ZFS_DATA_MNT/dns/control" ]
}

@test "dns - enable_control creates control.conf" {
  [ -f "$ZFS_DATA_MNT/dns/control.conf" ]
}

@test "dns - enable_control sets control-enable: yes" {
  run grep "control-enable: yes" "$ZFS_DATA_MNT/dns/control.conf"
  assert_success
}

@test "dns - enable_control sets control-interface to 0.0.0.0" {
  run grep "control-interface: 0.0.0.0" "$ZFS_DATA_MNT/dns/control.conf"
  assert_success
}

@test "dns - enable_control rewrites DESTDIR to /data/control in setup script" {
  run grep "^DESTDIR=/data/control" "$STAGE_MNT/usr/local/sbin/unbound-control-setup"
  assert_success
}

# --- start_unbound behaviour ---

@test "dns - start enables unbound via sysrc" {
  stage_sysrc() { echo "SYSRC:$*"; }
  stage_exec()  { :; }
  run start_unbound
  assert_success
  assert_output --partial "SYSRC:unbound_enable=YES"
}

@test "dns - start calls service unbound start" {
  stage_sysrc() { :; }
  stage_exec()  { echo "EXEC:$*"; }
  run start_unbound
  assert_success
  assert_output --partial "EXEC:service unbound start"
}

# --- test_unbound behaviour ---

@test "dns - test checks unbound is running" {
  stage_test_running() { echo "RUNNING:$*"; }
  stage_exec() { :; }
  run test_unbound
  assert_success
  assert_output --partial "RUNNING:unbound"
}

@test "dns - test calls host dns lookup via stage_exec" {
  stage_test_running() { :; }
  stage_exec() { echo "EXEC:$*"; }
  run test_unbound
  assert_success
  assert_output --partial "EXEC:host dns"
}

@test "dns - test writes nameserver to resolv.conf" {
  stage_test_running() { :; }
  stage_exec() { :; }
  test_unbound
  run grep "^nameserver" "$STAGE_MNT/etc/resolv.conf"
  assert_success
}

@test "dns - test sets resolv.conf to production dns IP on completion" {
  stage_test_running() { :; }
  stage_exec() { :; }
  test_unbound
  run cat "$STAGE_MNT/etc/resolv.conf"
  assert_output --partial "$(get_jail_ip dns)"
}

# --- switch_host_resolver behaviour ---

@test "dns - switch_host_resolver creates poststart script" {
  store_exec() { echo "EXEC:$1"; cat - > /dev/null; }
  run switch_host_resolver
  assert_output --partial "EXEC:$ZFS_DATA_MNT/dns/etc/rc.d/poststart.sh"
}

@test "dns - switch_host_resolver creates prestop script" {
  store_exec() { echo "EXEC:$1"; cat - > /dev/null; }
  run switch_host_resolver
  assert_output --partial "EXEC:$ZFS_DATA_MNT/dns/etc/rc.d/prestop.sh"
}
