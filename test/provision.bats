#!/usr/bin/env bats
# Structural tests for provision scripts.
# Verifies required elements without executing FreeBSD-specific code.

setup() {
  load './test_helper/load'
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

# One grep -L over every script beats one grep per script: these run over 70
# files and the process spawns, not the matching, are what cost.
_scripts_lacking() {
  local _pattern="$1" _exempt="${2:-_is_special}" _script _failed=0

  for _script in $(grep -L "$_pattern" provision/*.sh); do
    "$_exempt" "$_script" && continue
    echo "MISSING ${_pattern}: $_script" >&3
    _failed=$((_failed + 1))
  done

  [ "$_failed" -eq 0 ]
}

_none_exempt() { return 1; }

@test "standard provision scripts export the jail variables" {
  _scripts_lacking "^export JAIL_START_EXTRA"
  _scripts_lacking "^export JAIL_CONF_EXTRA"
  _scripts_lacking "^export JAIL_FSTAB"
}

@test "provision scripts define the functions their lifecycle needs" {
  _scripts_lacking "^install_" _none_exempt
  _scripts_lacking "^start_" _no_start_required
}

@test "all provision scripts source mail-toaster.sh" {
  _scripts_lacking "mail-toaster.sh" _none_exempt
}

# ---------------------------------------------------------------------------
# Jail capability assertions: scripts needing special jail permissions
# ---------------------------------------------------------------------------

# <jail> <permission the jail cannot run without>
@test "jails needing a permission ask for it in JAIL_START_EXTRA" {
  while read -r _jail _permission; do
    [ -n "$_jail" ] || continue
    run grep "^export JAIL_START_EXTRA" "provision/$_jail.sh"
    assert_output --partial "$_permission"
  done <<'EO_PERMS'
dovecot       allow.sysvipc=1
gitlab        allow.sysvipc=1
mongodb       allow.sysvipc=1
mongodb       allow.mlock=1
elasticsearch enforce_statfs=1
EO_PERMS
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

# <jail> <dataset it mounts from another jail>
@test "jails mount the data they share in JAIL_FSTAB" {
  while read -r _jail _dataset; do
    [ -n "$_jail" ] || continue
    run grep "JAIL_FSTAB=.*$_dataset" "provision/$_jail.sh"
    assert_output --partial "$_dataset"
  done <<'EO_FSTAB'
dovecot      vpopmail
spamassassin geoip
dcc          dcc
EO_FSTAB
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

# "<file> <setting>" for every $SETTING or ${SETTING} read outside config.sh,
# which declares the settings rather than consuming them. One pass over the
# tree, because a grep per declared setting is 50 passes.
_setting_reference_pairs() {
  grep -roE '[$][{]?[A-Z_][A-Z_0-9]*' \
      provision/*.sh deprecated/*.sh include/*.sh mail-toaster.sh \
    | grep -v '^include/config\.sh:' \
    | sed -e 's/:[$]{\{0,1\}/ /' \
    | sort -u
}

@test "config.sh declares no setting that only one jail reads" {
  local _offenders
  _offenders=$(
    {
      _config_declared_settings | sed -e 's/^/DECLARED /'
      _setting_reference_pairs
    } | awk '
      $1 == "DECLARED" { declared[$2] = 1; next }
      { readers[$2] = readers[$2] " " $1; count[$2]++ }
      END {
        for (s in declared) {
          if (count[s] != 1) continue
          r = substr(readers[s], 2)
          # base.sh, host.sh and bhyve-ubuntu.sh configure the host rather than
          # a jail, so a setting only they read is still toaster-wide
          if (r == "provision/base.sh" || r == "provision/host.sh") continue
          if (r == "provision/bhyve-ubuntu.sh") continue
          if (r !~ /^(provision|deprecated)\//) continue
          printf "JAIL-PRIVATE (%s), belongs in its provision script: %s\n", r, s
        }
      }')

  if [ -n "$_offenders" ]; then
    echo "$_offenders" >&3
    return 1
  fi
}


# ---------------------------------------------------------------------------
# What each jail listens on, installs and enables
# ---------------------------------------------------------------------------

# <jail> <port its test_ function waits for>
@test "test_ functions check the service port" {
  while read -r _jail _port; do
    [ -n "$_jail" ] || continue
    run grep "stage_listening" "provision/$_jail.sh"
    assert_output --partial "$_port"
  done <<'EO_PORTS'
redis         6379
memcached     11211
influxdb      8086
nginx         80
haproxy       443
mysql         3306
dovecot       993
elasticsearch 9200
minecraft     25565
EO_PORTS
}

# <jail> <install call> <package or port it installs>
@test "install_ functions install the service" {
  while read -r _jail _installer _package; do
    [ -n "$_jail" ] || continue
    run grep "$_installer" "provision/$_jail.sh"
    assert_output --partial "$_package"
  done <<'EO_PACKAGES'
redis        stage_pkg_install  redis
memcached    stage_pkg_install  memcached
mysql        stage_pkg_install  mysql
nginx        stage_pkg_install  nginx
influxdb     stage_pkg_install  influxdb
grafana      stage_pkg_install  grafana
telegraf     stage_pkg_install  telegraf
rspamd       stage_pkg_install  rspamd
dovecot      stage_pkg_install  dovecot
spamassassin stage_port_install spamassassin
EO_PACKAGES
}

# <jail> <the rc variable its start_ function sets>
@test "start_ functions enable the service at boot" {
  while read -r _jail _enable; do
    [ -n "$_jail" ] || continue
    run grep "stage_sysrc" "provision/$_jail.sh"
    assert_output --partial "$_enable"
  done <<'EO_ENABLE'
redis     redis_enable=YES
memcached memcached_enable=YES
nginx     nginx_enable=YES
mysql     enable=YES
rspamd    rspamd_enable=YES
dovecot   dovecot_enable=YES
EO_ENABLE
}
