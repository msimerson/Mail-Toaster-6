#!/usr/bin/env bats
# Structural tests for provision scripts.
# Verifies required elements without executing FreeBSD-specific code.

setup() {
  load './test_helper/bats-support/load'
  load './test_helper/bats-assert/load'
}

# ---------------------------------------------------------------------------
# Scripts that are NOT standard jail provisioners (excluded from bulk checks).
# base.sh    - creates the base ZFS snapshot, not a service jail
# bhyve-ubuntu.sh - provisions a bhyve VM, not a FreeBSD jail
# ---------------------------------------------------------------------------
_is_special() {
  case "$1" in
    provision/base.sh|provision/bhyve-ubuntu.sh) return 0 ;;
  esac
  return 1
}

# Scripts that don't provision persistent services (no start_ function needed)
_no_start_required() {
  case "$1" in
    provision/base.sh|provision/bhyve-ubuntu.sh|\
    provision/certbot.sh|provision/host.sh|provision/letsencrypt.sh) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# Bulk structural checks
# ---------------------------------------------------------------------------

@test "standard provision scripts export JAIL_START_EXTRA" {
  local failed=0
  for script in provision/*.sh; do
    _is_special "$script" && continue
    if ! grep -q "^export JAIL_START_EXTRA" "$script"; then
      echo "MISSING JAIL_START_EXTRA: $script" >&3
      failed=$((failed + 1))
    fi
  done
  [ "$failed" -eq 0 ]
}

@test "standard provision scripts export JAIL_CONF_EXTRA" {
  local failed=0
  for script in provision/*.sh; do
    _is_special "$script" && continue
    if ! grep -q "^export JAIL_CONF_EXTRA" "$script"; then
      echo "MISSING JAIL_CONF_EXTRA: $script" >&3
      failed=$((failed + 1))
    fi
  done
  [ "$failed" -eq 0 ]
}

@test "standard provision scripts export JAIL_FSTAB" {
  local failed=0
  for script in provision/*.sh; do
    _is_special "$script" && continue
    if ! grep -q "^export JAIL_FSTAB" "$script"; then
      echo "MISSING JAIL_FSTAB: $script" >&3
      failed=$((failed + 1))
    fi
  done
  [ "$failed" -eq 0 ]
}

@test "all provision scripts define an install_ function" {
  local failed=0
  for script in provision/*.sh; do
    if ! grep -q "^install_" "$script"; then
      echo "MISSING install_*: $script" >&3
      failed=$((failed + 1))
    fi
  done
  [ "$failed" -eq 0 ]
}

@test "service provision scripts define a start_ function" {
  local failed=0
  for script in provision/*.sh; do
    _no_start_required "$script" && continue
    if ! grep -q "^start_" "$script"; then
      echo "MISSING start_*: $script" >&3
      failed=$((failed + 1))
    fi
  done
  [ "$failed" -eq 0 ]
}

@test "all provision scripts source mail-toaster.sh" {
  local failed=0
  for script in provision/*.sh; do
    if ! grep -q "mail-toaster.sh" "$script"; then
      echo "MISSING mail-toaster.sh source: $script" >&3
      failed=$((failed + 1))
    fi
  done
  [ "$failed" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Jail capability assertions: scripts needing special jail permissions
# ---------------------------------------------------------------------------

@test "dovecot exports allow.sysvipc in JAIL_START_EXTRA" {
  run grep "^export JAIL_START_EXTRA" provision/dovecot.sh
  assert_output --partial "allow.sysvipc=1"
}

@test "gitlab exports allow.sysvipc in JAIL_START_EXTRA" {
  run grep "^export JAIL_START_EXTRA" provision/gitlab.sh
  assert_output --partial "allow.sysvipc=1"
}

@test "mongodb exports allow.sysvipc in JAIL_START_EXTRA" {
  run grep "^export JAIL_START_EXTRA" provision/mongodb.sh
  assert_output --partial "allow.sysvipc=1"
}

@test "mongodb exports allow.mlock in JAIL_START_EXTRA" {
  run grep "^export JAIL_START_EXTRA" provision/mongodb.sh
  assert_output --partial "allow.mlock=1"
}

@test "elasticsearch exports enforce_statfs in JAIL_START_EXTRA" {
  run grep "^export JAIL_START_EXTRA" provision/elasticsearch.sh
  assert_output --partial "enforce_statfs=1"
}

@test "linux jails let rc.d/linux mount /compat/linux" {
  run grep -A2 "stage_sysrc linux_mounts_enable" include/linux.sh
  assert_output --partial "linux_mounts_enable=YES"

  for _s in provision/centos.sh provision/ubuntu.sh provision/stalwart.sh; do
    run grep "compat/linux/\(dev\|proc\|sys\)" "$_s"
    refute_output --partial "ZFS_JAIL_MNT"
  done
}

@test "jails needing bpf create the ruleset themselves" {
  for _s in provision/haraka.sh provision/dhcp.sh; do
    run grep -n "assure_devfs_bpf_ruleset" "$_s"
    assert_success
    run sh -c "grep -n 'assure_devfs_bpf_ruleset\|start_staged_jail' $_s | tail -2 | head -1"
    assert_output --partial "assure_devfs_bpf_ruleset"
  done
}

@test "jails needing extra devices set JAIL_DEVFS_RULESET" {
  for _s in provision/haraka.sh provision/dhcp.sh; do
    run grep "^export JAIL_DEVFS_RULESET" "$_s"
    assert_success
  done
}

@test "no provision script smuggles devfs_ruleset through JAIL_*_EXTRA" {
  run grep -l "JAIL_START_EXTRA=.*devfs_ruleset\|JAIL_CONF_EXTRA=.*devfs_ruleset" provision/*.sh
  assert_output ""
}

# ---------------------------------------------------------------------------
# JAIL_FSTAB mount assertions
# ---------------------------------------------------------------------------

@test "dovecot mounts vpopmail home in JAIL_FSTAB" {
  run grep "JAIL_FSTAB=.*vpopmail" provision/dovecot.sh
  assert_output --partial "vpopmail"
}

@test "spamassassin mounts geoip in JAIL_FSTAB" {
  run grep "JAIL_FSTAB=.*geoip" provision/spamassassin.sh
  assert_output --partial "geoip"
}

@test "spamassassin builds RELAY_COUNTRY unconditionally" {
  run grep "^	local _SA_OPTS=" provision/spamassassin.sh
  assert_success
  assert_output --partial "RELAY_COUNTRY"
}

# ---------------------------------------------------------------------------
# A setting only one jail reads belongs in that jail's provision script, where
# its default reaches installs whose conf.d file predates it. The generated
# mail-toaster.conf is for settings that apply toaster-wide.
# ---------------------------------------------------------------------------

_config_declared_settings() {
  {
    awk '/store_config "\$1"/,/^EO_MT_CONF$/' include/config.sh \
      | sed -n 's/^export \([A-Z_][A-Z_0-9]*\)=.*/\1/p'
    awk '/^mt6_defaults\(\)/,/^}/' include/config.sh \
      | sed -n 's/^[[:space:]]*export \([A-Z_][A-Z_0-9]*\)=.*/\1/p'
  } | sort -u
}

@test "config.sh declares no setting that only one jail reads" {
  local failed=0 _setting _readers _count
  for _setting in $(_config_declared_settings); do
    # config.sh declares the setting, it does not consume it
    _readers=$(grep -rlE "[\$][{]?${_setting}([^A-Z_0-9]|$)" \
                 provision/*.sh deprecated/*.sh include/*.sh mail-toaster.sh \
               | grep -v '^include/config\.sh$') || true
    _count=$(printf '%s' "$_readers" | grep -c . || true)
    [ "$_count" -eq 1 ] || continue

    # base.sh, host.sh and bhyve-ubuntu.sh configure the host rather than a
    # jail, so a setting only they read is still toaster-wide. They still count
    # as readers above, or a setting they share with one jail looks jail-private.
    case "$_readers" in
      provision/base.sh|provision/host.sh|provision/bhyve-ubuntu.sh) continue ;;
      provision/*|deprecated/*) ;;
      *) continue ;;
    esac

    echo "JAIL-PRIVATE ($_readers), belongs in its provision script: $_setting" >&3
    failed=$((failed + 1))
  done
  [ "$failed" -eq 0 ]
}


@test "dcc mounts dcc db in JAIL_FSTAB" {
  run grep "JAIL_FSTAB=.*dcc" provision/dcc.sh
  assert_output --partial "dcc"
}

# ---------------------------------------------------------------------------
# Port assertions: verify test_ functions check the right port
# ---------------------------------------------------------------------------

@test "redis tests port 6379" {
  run grep "stage_listening" provision/redis.sh
  assert_output --partial "6379"
}

@test "memcached tests port 11211" {
  run grep "stage_listening" provision/memcached.sh
  assert_output --partial "11211"
}

@test "influxdb tests port 8086" {
  run grep "stage_listening" provision/influxdb.sh
  assert_output --partial "8086"
}

@test "nginx provision tests port 80" {
  run grep "stage_listening" provision/nginx.sh
  assert_output --partial "80"
}

@test "haproxy tests port 443" {
  run grep "stage_listening" provision/haproxy.sh
  assert_output --partial "443"
}

@test "mysql tests port 3306" {
  run grep "stage_listening" provision/mysql.sh
  assert_output --partial "3306"
}

@test "dovecot tests port 993 (IMAPS)" {
  run grep "stage_listening" provision/dovecot.sh
  assert_output --partial "993"
}

@test "elasticsearch tests port 9200" {
  run grep "stage_listening" provision/elasticsearch.sh
  assert_output --partial "9200"
}

@test "minecraft tests port 25565" {
  run grep "stage_listening" provision/minecraft.sh
  assert_output --partial "25565"
}

# ---------------------------------------------------------------------------
# Package / installation assertions
# ---------------------------------------------------------------------------

@test "redis installs redis package" {
  run grep "stage_pkg_install" provision/redis.sh
  assert_output --partial "redis"
}

@test "memcached installs memcached package" {
  run grep "stage_pkg_install" provision/memcached.sh
  assert_output --partial "memcached"
}

@test "mysql installs mysql or mariadb server" {
  run grep "stage_pkg_install" provision/mysql.sh
  assert_output --partial "mysql"
}

@test "nginx provision installs nginx package" {
  run grep "stage_pkg_install" provision/nginx.sh
  assert_output --partial "nginx"
}

@test "influxdb installs influxdb" {
  run grep "stage_pkg_install" provision/influxdb.sh
  assert_output --partial "influxdb"
}

@test "grafana installs grafana" {
  run grep "stage_pkg_install" provision/grafana.sh
  assert_output --partial "grafana"
}

@test "telegraf installs telegraf" {
  run grep "stage_pkg_install" provision/telegraf.sh
  assert_output --partial "telegraf"
}

@test "rspamd installs rspamd" {
  run grep "stage_pkg_install" provision/rspamd.sh
  assert_output --partial "rspamd"
}

@test "spamassassin installs via port mail/spamassassin" {
  run grep "stage_port_install" provision/spamassassin.sh
  assert_output --partial "spamassassin"
}

@test "dovecot installs dovecot package" {
  run grep "stage_pkg_install" provision/dovecot.sh
  assert_output --partial "dovecot"
}

# ---------------------------------------------------------------------------
# Service enable assertions
# ---------------------------------------------------------------------------

@test "redis start enables redis service" {
  run grep "stage_sysrc" provision/redis.sh
  assert_output --partial "redis_enable=YES"
}

@test "memcached start enables memcached service" {
  run grep "stage_sysrc" provision/memcached.sh
  assert_output --partial "memcached_enable=YES"
}

@test "nginx start enables nginx service" {
  run grep "stage_sysrc" provision/nginx.sh
  assert_output --partial "nginx_enable=YES"
}

@test "mysql start enables mysql or mariadb service" {
  run grep "stage_sysrc" provision/mysql.sh
  assert_output --partial "enable=YES"
}

@test "rspamd start enables rspamd service" {
  run grep "stage_sysrc" provision/rspamd.sh
  assert_output --partial "rspamd_enable=YES"
}

@test "dovecot start enables dovecot service" {
  run grep "stage_sysrc" provision/dovecot.sh
  assert_output --partial "dovecot_enable=YES"
}
