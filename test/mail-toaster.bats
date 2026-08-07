# https://bats-core.readthedocs.io/en/stable/writing-tests.html

setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  export MT6_TEST_ENV=1
  load ../mail-toaster.sh
  # Manually load includes that mt6_init would have loaded
  load ../include/util.sh
  load ../include/config.sh
  load ../include/zfs.sh
  load ../include/jail.sh
  load ../include/network.sh
  # Initialize defaults that mt6_init would have set
  mt6_defaults
}

@test "safe_jailname replaces . with _" {
  run safe_jailname bad.chars
  assert_success
  assert_output "bad_chars"
}

@test "reverse_list" {
  run reverse_list tic tac toe
  #echo "# $output" >&3
  assert_success
  assert_output --partial "toe tac tic"
}

@test "tell_settings - prints the settings for a prefix" {
  export CLAMAV_UNOFFICIAL="1"
  run tell_settings "CLAMAV"
  assert_success
  assert_output --partial "Configured CLAMAV settings:"
  assert_output --partial "CLAMAV_UNOFFICIAL=1"
}

# Admins are asked to paste provisioning output into issue reports.
@test "tell_settings - redacts credentials" {
  export TSEC_MONGODB_DSN="mongodb://ubnt:sup3rs3cret@mongodb:27017/unifi"
  export TSEC_LICENSE_KEY="abc123XYZ"
  run tell_settings "TSEC"
  assert_success
  refute_output --partial "sup3rs3cret"
  refute_output --partial "abc123XYZ"
  assert_output --partial "TSEC_MONGODB_DSN=[redacted]"
  assert_output --partial "TSEC_LICENSE_KEY=[redacted]"
}

@test "tell_settings - an unset credential stays visibly empty" {
  export TSEC_LICENSE_KEY=""
  run tell_settings "TSEC"
  assert_success
  assert_output --partial "TSEC_LICENSE_KEY="
  refute_output --partial "TSEC_LICENSE_KEY=[redacted]"
}

@test "tell_settings - a name ending in _FILE is not a credential" {
  export TSEC_KEY_FILE="/etc/ssl/key.pem"
  run tell_settings "TSEC"
  assert_success
  assert_output --partial "TSEC_KEY_FILE=/etc/ssl/key.pem"
}

# grep exits 1 on no match, which would end a provision script's set -e.
@test "tell_settings - succeeds when the prefix has no settings" {
  run tell_settings "NOSUCHPREFIX"
  assert_success
}

@test "tell_status" {
  skip
  run tell_status "BATS testing"
  assert_success
}

@test "proclaim_success" {
  run proclaim_success "test"
  assert_success
  assert_output --partial "Success! A new 'test' jail is provisioned"
}

@test "get_random_pass 20" {
  run get_random_pass 20
  #echo "# $output" >&3
  assert_success
  assert_equal ${#output} 20
}

@test "get_random_pass (defaults)" {
  run get_random_pass
  #echo "# $output" >&3
  assert_success
  assert_equal ${#output} 14
}

@test "get_random_pass 14 strong" {
  run get_random_pass 14 strong
  #echo "# $output" >&3
  assert_success
  #assert_equal ${#output} 14
}

@test "get_random_pass 14 safe" {
  run get_random_pass 14 safe
  #echo "# $output" >&3
  assert_success
  #assert_equal ${#output} 14
}

@test "get_jail_ip mysql" {
  run get_jail_ip mysql
  assert_success
  assert_output "172.16.15.4"
}

@test "get_jail_ip haraka" {
  run get_jail_ip haraka
  assert_success
  assert_output "172.16.15.9"
}

@test "fstab_add_mount" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export MT6_ETC="$tmpdir/etc"
  local fstab; fstab="$(get_jail_host_etc myjail)/fstab"
  mkdir -p "$(dirname "$fstab")"
  touch "$fstab" "${fstab}.stage"

  # Mock tell_status
  tell_status() { :; }

  run fstab_add_mount myjail /src /dest
  assert_success

  run grep "/src" "$fstab"
  assert_success
  assert_output --partial "/dest"

  run grep "/src" "${fstab}.stage"
  assert_success

  rm -rf "$tmpdir"
}

@test "stage_sysrc" {
  export STAGE_MNT=$(mktemp -d)
  # Mock sysrc
  sysrc() {
    echo "sysrc called with $*"
  }

  run stage_sysrc myvar=value
  assert_success
  assert_output --partial "sysrc -R $STAGE_MNT myvar=value"

  rm -rf "$STAGE_MNT"
}

@test "stage_make_conf - new setting" {
  export STAGE_MNT=$(mktemp -d)
  mkdir -p "$STAGE_MNT/etc"
  local make_conf="$STAGE_MNT/etc/make.conf"
  touch "$make_conf"

  tell_status() { :; }

  run stage_make_conf MY_VAR "MY_VAR=val"
  assert_success

  run cat "$make_conf"
  assert_output "MY_VAR=val"

  rm -rf "$STAGE_MNT"
}

@test "stage_make_conf - existing setting" {
  export STAGE_MNT=$(mktemp -d)
  mkdir -p "$STAGE_MNT/etc"
  local make_conf="$STAGE_MNT/etc/make.conf"
  echo "MY_VAR=old" > "$make_conf"

  run stage_make_conf MY_VAR "MY_VAR=new"
  assert_success
  assert_output --partial "preserving make.conf settings"

  run cat "$make_conf"
  assert_output "MY_VAR=old"

  rm -rf "$STAGE_MNT"
}

@test "stage_resolv_conf" {
  export STAGE_MNT=$(mktemp -d)
  mkdir -p "$STAGE_MNT/etc"

  # Mock jail_is_running and get_jail_ip
  jail_is_running() { return 0; }
  get_jail_ip() { echo "1.2.3.4"; }
  get_jail_ip6() { echo "fe80::1"; }
  tell_status() { :; }

  run stage_resolv_conf
  assert_success

  run cat "$STAGE_MNT/etc/resolv.conf"
  assert_output --partial "nameserver 1.2.3.4"
  assert_output --partial "nameserver fe80::1"

  rm -rf "$STAGE_MNT"
}

@test "get_jail_ip dns" {
  run get_jail_ip dns
  assert_success
  assert_output "172.16.15.3"
}

@test "get_jail_ip syslog" {
  run get_jail_ip syslog
  assert_success
  assert_output "172.16.15.1"
}

@test "check_last_hour - returns failure when no timestamp exists" {
  local tmp; tmp=$(mktemp -d)
  TMPDIR="$tmp" run check_last_hour
  assert_failure
  rm -rf "$tmp"
}

@test "check_last_hour - returns success when timestamp is recent" {
  local tmp; tmp=$(mktemp -d)
  date +%s > "$tmp/.mt6_fetch"
  TMPDIR="$tmp" run check_last_hour
  assert_success
  rm -rf "$tmp"
}

@test "fatal_err outputs FATAL message and exits non-zero" {
  run fatal_err "something went wrong"
  assert_failure
  assert_output --partial "FATAL: something went wrong"
}

@test "fstab_add_mount - skips entry already present" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export MT6_ETC="$tmpdir/etc"
  local fstab; fstab="$(get_jail_host_etc myjail)/fstab"
  mkdir -p "$(dirname "$fstab")"
  printf '/src\t/dest\tnullfs\trw\t0\t0\n' > "$fstab"
  printf '/src\t/dest\tnullfs\trw\t0\t0\n' > "${fstab}.stage"

  tell_status() { :; }

  run fstab_add_mount myjail /src /dest
  assert_success

  run grep -c "^/src" "$fstab"
  assert_output "1"

  rm -rf "$tmpdir"
}

@test "stage_listening - succeeds when port is immediately listening" {
  port_is_listening() { return 0; }
  run stage_listening 3306
  assert_success
  assert_output --partial "OK"
}

@test "stage_listening - fails after exhausting retries" {
  port_is_listening() { return 1; }
  run stage_listening 9999 2 0
  assert_failure
}

@test "install_fstab creates fstab with data nullfs mount" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export ZFS_JAIL_MNT="$tmpdir/jails"
  export STAGE_MNT="$tmpdir/jails/stage"
  export JAIL_FSTAB=""
  export TOASTER_USE_TMPFS=0
  export MT6_ETC="$tmpdir/etc"
  mkdir -p "$(get_jail_host_etc myjail)" "$(get_jail_host_etc stage)"

  tell_status() { :; }

  run install_fstab myjail
  assert_success

  run grep "nullfs" "$(get_jail_host_etc myjail)/fstab"
  assert_success
  assert_output --partial "$tmpdir/jails/myjail/data"

  rm -rf "$tmpdir"
}

@test "install_fstab creates no host devfs mount" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export ZFS_JAIL_MNT="$tmpdir/jails"
  export STAGE_MNT="$tmpdir/jails/stage"
  export JAIL_FSTAB=""
  export TOASTER_USE_TMPFS=0
  export MT6_ETC="$tmpdir/etc"
  mkdir -p "$(get_jail_host_etc myjail)" "$(get_jail_host_etc stage)"

  tell_status() { :; }

  run install_fstab myjail
  assert_success

  run grep "devfs" "$tmpdir/myjail/etc/fstab"
  assert_failure

  rm -rf "$tmpdir"
}

setup_tmpfs_fstab() {
  export ZFS_DATA_MNT="$1"
  export ZFS_JAIL_MNT="$1/jails"
  export STAGE_MNT="$1/jails/stage"
  export JAIL_FSTAB=""
  export TOASTER_USE_TMPFS=1
  export MT6_ETC="$1/etc"
  mkdir -p "$(get_jail_host_etc myjail)" "$(get_jail_host_etc stage)"

  tell_status() { :; }
}

@test "install_fstab mounts the runtime /tmp noexec" {
  local tmpdir; tmpdir=$(mktemp -d)
  setup_tmpfs_fstab "$tmpdir"

  install_fstab myjail

  run grep "$tmpdir/jails/myjail/tmp" "$(get_jail_host_etc myjail)/fstab"
  assert_success
  assert_output --partial "rw,mode=01777,noexec,nosuid"

  rm -rf "$tmpdir"
}

@test "install_fstab mounts the stage /tmp exec, so ports can build there" {
  local tmpdir; tmpdir=$(mktemp -d)
  setup_tmpfs_fstab "$tmpdir"

  install_fstab myjail

  run grep "$tmpdir/jails/stage/tmp" "$(get_jail_host_etc myjail)/fstab.stage"
  assert_success
  refute_output --partial "noexec"
  assert_output --partial "rw,mode=01777,nosuid"

  rm -rf "$tmpdir"
}

@test "install_fstab keeps the stage /var/run noexec" {
  local tmpdir; tmpdir=$(mktemp -d)
  setup_tmpfs_fstab "$tmpdir"

  install_fstab myjail

  run grep "$tmpdir/jails/stage/var/run" "$(get_jail_host_etc myjail)/fstab.stage"
  assert_success
  assert_output --partial "rw,mode=01755,noexec,nosuid"

  rm -rf "$tmpdir"
}

@test "install_fstab copies the exec /tmp into the stage shutdown fstab" {
  local tmpdir; tmpdir=$(mktemp -d)
  setup_tmpfs_fstab "$tmpdir"

  install_fstab myjail

  run grep "$tmpdir/jails/stage/tmp" "$(get_jail_host_etc stage)/fstab"
  assert_success
  refute_output --partial "noexec"

  rm -rf "$tmpdir"
}

@test "install_fstab appends JAIL_FSTAB when set" {
  local tmpdir; tmpdir=$(mktemp -d)
  export ZFS_DATA_MNT="$tmpdir"
  export ZFS_JAIL_MNT="$tmpdir/jails"
  export STAGE_MNT="$tmpdir/jails/stage"
  export JAIL_FSTAB="/extra/src /extra/dest nullfs rw 0 0"
  export TOASTER_USE_TMPFS=0
  export MT6_ETC="$tmpdir/etc"
  mkdir -p "$(get_jail_host_etc myjail)" "$(get_jail_host_etc stage)"

  tell_status() { :; }

  install_fstab myjail

  run grep "/extra/src" "$(get_jail_host_etc myjail)/fstab"
  assert_success

  rm -rf "$tmpdir"
}

@test "stage_fbsd_pkgbase derives base_release_<minor> and invokes pkg" {
  local tmpdir; tmpdir=$(mktemp -d)
  export FBSD_REL_VER="15.0-RELEASE"
  export TOASTER_BASE_PKG_BRANCH=""

  # capture pkg args instead of touching the network
  pkg() { echo "$*" > "$tmpdir/pkg.args"; }

  run stage_fbsd_pkgbase base "$tmpdir/dest"
  assert_success

  run cat "$tmpdir/dest/usr/local/etc/pkg/repos/FreeBSD-base.conf"
  assert_success
  assert_output --partial 'pkg+https://pkg.freebsd.org/${ABI}/base_release_0"'
  refute_output --partial 'base_release_0-RELEASE'
  # base_release_* is signed with the pkgbase-<major> fingerprints
  assert_output --partial 'fingerprints: "/usr/share/keys/pkgbase-'

  run cat "$tmpdir/pkg.args"
  assert_output --partial "--rootdir $tmpdir/dest"
  assert_output --partial "FreeBSD-base"
  assert_output --partial "FreeBSD-set-devel"

  rm -rf "$tmpdir"
}

@test "stage_fbsd_pkgbase honors TOASTER_BASE_PKG_BRANCH override" {
  local tmpdir; tmpdir=$(mktemp -d)
  export FBSD_REL_VER="15.0-RELEASE"
  export TOASTER_BASE_PKG_BRANCH="base_latest"

  pkg() { :; }

  run stage_fbsd_pkgbase base "$tmpdir/dest"
  assert_success

  run cat "$tmpdir/dest/usr/local/etc/pkg/repos/FreeBSD-base.conf"
  assert_output --partial 'base_latest'
  refute_output --partial 'base_release'
  # base_latest uses the standard pkg fingerprints
  assert_output --partial 'fingerprints: "/usr/share/keys/pkg"'

  rm -rf "$tmpdir"
}

# stage_unmount test fixtures: 'mount' and 'umount' are stubbed so the pipeline
# can be exercised off FreeBSD. unmounted_paths echoes only what got unmounted,
# in the order stage_unmount tried it.
fake_mount() {
  mount() {
    cat <<EOF
$ZFS_JAIL_VOL/stage on $STAGE_MNT (zfs, local, nfsv4acls)
devfs on $STAGE_MNT/dev (devfs)
$ZFS_DATA_MNT/ports on $STAGE_MNT/usr/ports (nullfs, local)
$ZFS_DATA_MNT/distfiles on $STAGE_MNT/usr/ports/distfiles (nullfs, local)
tmpfs on $STAGE_MNT/tmp (tmpfs, local)
$ZFS_DATA_MNT/other on ${STAGE_MNT}-other/data (nullfs, local)
$ZFS_DATA_MNT/dovecot on $ZFS_JAIL_MNT/dovecot/stagefiles (nullfs, local)
EOF
  }
  umount() { :; }
}

unmounted_paths() {
  stage_unmount | awk '/^umount /{ print $2 }'
}

@test "stage_unmount unmounts nested mounts before their parents" {
  fake_mount
  run unmounted_paths
  assert_success
  assert_line --index 0 "$STAGE_MNT/usr/ports/distfiles"
  assert_line --index 1 "$STAGE_MNT/usr/ports"
}

@test "stage_unmount unmounts each mountpoint once" {
  fake_mount
  run unmounted_paths
  assert_success
  assert_equal "${#lines[@]}" 4
}

@test "stage_unmount unmounts the stage devfs" {
  fake_mount
  run unmounted_paths
  assert_success
  assert_line "$STAGE_MNT/dev"
}

@test "stage_unmount leaves the stage root mounted" {
  fake_mount
  run unmounted_paths
  assert_success
  refute_line "$STAGE_MNT"
}

@test "stage_unmount ignores mounts outside the stage" {
  fake_mount
  run unmounted_paths
  assert_success
  # 'stage' as a substring elsewhere in the mount line is not a stage mount
  refute_line "${STAGE_MNT}-other/data"
  refute_line "$ZFS_JAIL_MNT/dovecot/stagefiles"
}

@test "stage_unmount refuses to run with STAGE_MNT unset" {
  fake_mount
  STAGE_MNT=
  run stage_unmount
  assert_failure
  assert_output --partial "STAGE_MNT is unset"
  refute_output --partial "umount /"
}

@test "assure_ports_tree accepts a populated tree" {
  local _ports; _ports=$(mktemp -d)
  touch "$_ports/Makefile"
  run assure_ports_tree "$_ports"
  assert_success
}

@test "assure_ports_tree rejects an unpopulated tree" {
  local _ports; _ports=$(mktemp -d)
  run assure_ports_tree "$_ports"
  assert_failure
  assert_output --partial "$_ports"
}

@test "assure_ports_tree names both ways to populate the tree" {
  local _ports; _ports=$(mktemp -d)
  run assure_ports_tree "$_ports"
  assert_output --partial "gitup ports"
  assert_output --partial "git clone https://github.com/freebsd/freebsd-ports.git"
}

@test "start_staged_jail - the stage jail gets the jail's own ruleset" {
  export ZFS_JAIL_MNT="$BATS_TEST_TMPDIR/jails" MT6_ETC="$BATS_TEST_TMPDIR/etc"
  export STAGE_MNT="$ZFS_JAIL_MNT/stage" JAIL_NET_INTERFACE=lo1
  export JAIL_DEVFS_RULESET=7 JAIL_START_EXTRA=""
  tell_status() { :; }
  jail() { echo "$@"; }
  enable_bsd_cache() { :; }
  pkg() { :; }

  run start_staged_jail haraka
  assert_success
  assert_output --partial "devfs_ruleset=7"
  assert_equal "$(echo "$output" | grep -c devfs_ruleset)" "1"
}

# --- moving control files out of the jail's data volume, on rebuild ---

host_etc_setup() {
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  export MT6_ETC="$BATS_TEST_TMPDIR/etc"
  OLD="$ZFS_DATA_MNT/dovecot/etc"
  mkdir -p "$OLD/pf.conf.d"
  echo "rdr rule" > "$OLD/pf.conf.d/rdr.conf"
  echo "old copy" > "$OLD/pf.conf.d/pfrule.sh"
  touch "$OLD/fstab" "$OLD/fstab.stage"
  tell_status() { :; }
}

@test "adopt_jail_host_etc - copies the rules, leaves the original in place" {
  host_etc_setup
  echo "shadow"    > "$OLD/pf.conf.d/rdr.conf.mt6"
  echo "10.0.0.0/8"> "$OLD/pf.conf.d/blocklist.table"
  echo "tshadow"   > "$OLD/pf.conf.d/blocklist.table.mt6"
  echo "stray"     > "$OLD/pf.conf.d/notes.txt"

  adopt_jail_host_etc dovecot
  local _new="$(get_jail_host_etc dovecot)/pf.conf.d"

  run cat "$_new/rdr.conf";           assert_output "rdr rule"
  run cat "$_new/rdr.conf.mt6";       assert_output "shadow"
  run cat "$_new/blocklist.table";    assert_output "10.0.0.0/8"
  run cat "$_new/blocklist.table.mt6";assert_output "tshadow"

  # install_pfrule provides the shared copy; notes.txt is not a rule
  [ ! -e "$_new/pfrule.sh" ]
  [ ! -e "$_new/notes.txt" ]

  [ -f "$OLD/pf.conf.d/rdr.conf" ]
}

@test "adopt_jail_host_etc - keeps a .mt6 shadow at 0600" {
  host_etc_setup
  echo "secret" > "$OLD/pf.conf.d/rdr.conf.mt6"
  chmod 600 "$OLD/pf.conf.d/rdr.conf.mt6"

  adopt_jail_host_etc dovecot

  local _pfd="$(get_jail_host_etc dovecot)/pf.conf.d"
  run find "$_pfd" -name "rdr.conf.mt6" -perm 600
  assert_output "$_pfd/rdr.conf.mt6"
  run find "$_pfd" -name "rdr.conf" -perm 644
  assert_output "$_pfd/rdr.conf"
}

@test "adopt_jail_host_etc - a symlink is never adopted" {
  host_etc_setup
  echo "jail controlled" > "$ZFS_DATA_MNT/dovecot/evil"
  ln -s "$ZFS_DATA_MNT/dovecot/evil" "$OLD/pf.conf.d/filter.conf"
  ln -s "$ZFS_DATA_MNT/dovecot/evil" "$OLD/pf.conf.d/sneaky.table"

  adopt_jail_host_etc dovecot
  local _new="$(get_jail_host_etc dovecot)/pf.conf.d"

  [ ! -e "$_new/filter.conf" ]
  [ ! -e "$_new/sneaky.table" ]
  [ -f "$_new/rdr.conf" ] && [ ! -L "$_new/rdr.conf" ]
}

@test "adopt_jail_host_etc - a symlinked pf.conf.d is not adopted" {
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  export MT6_ETC="$BATS_TEST_TMPDIR/etc"
  tell_status() { :; }
  mkdir -p "$ZFS_DATA_MNT/dovecot/etc" "$ZFS_DATA_MNT/dovecot/elsewhere"
  echo "jail controlled" > "$ZFS_DATA_MNT/dovecot/elsewhere/rdr.conf"
  ln -s "$ZFS_DATA_MNT/dovecot/elsewhere" "$ZFS_DATA_MNT/dovecot/etc/pf.conf.d"

  adopt_jail_host_etc dovecot

  [ ! -e "$(get_jail_host_etc dovecot)/pf.conf.d" ]
}

@test "adopt_jail_host_etc - is a no-op once the host copy exists" {
  host_etc_setup
  mkdir -p "$(get_jail_host_etc dovecot)/pf.conf.d"
  echo "edited on the host" > "$(get_jail_host_etc dovecot)/pf.conf.d/rdr.conf"

  adopt_jail_host_etc dovecot
  run cat "$(get_jail_host_etc dovecot)/pf.conf.d/rdr.conf"
  assert_output "edited on the host"
}

@test "adopt_jail_host_etc - nothing to adopt is not an error" {
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  export MT6_ETC="$BATS_TEST_TMPDIR/etc"
  tell_status() { :; }

  run adopt_jail_host_etc fresh
  assert_success

  host_etc_setup
  rm -f "$OLD"/pf.conf.d/*.table
  run adopt_jail_host_etc dovecot
  assert_success
}

@test "adopt_jail_host_etc - publishes the directory only once complete" {
  host_etc_setup
  local _new="$(get_jail_host_etc dovecot)/pf.conf.d"
  mkdir -p "$_new.adopting"
  echo "junk" > "$_new.adopting/leftover.conf"

  adopt_jail_host_etc dovecot

  [ -f "$_new/rdr.conf" ]
  [ ! -e "$_new/leftover.conf" ]
  [ ! -e "$_new.adopting" ]
}

@test "retire_jail_host_etc - removes the old fstab and pf.conf.d" {
  host_etc_setup
  retire_jail_host_etc dovecot

  [ ! -e "$OLD/fstab" ]
  [ ! -e "$OLD/fstab.stage" ]
  [ ! -e "$OLD/pf.conf.d" ]
}

@test "retire_jail_host_etc - keeps what an edited jail.conf still names" {
  host_etc_setup
  tell_status() { echo "$1"; }
  local _confd="$BATS_TEST_TMPDIR/jail.conf.d"
  mkdir -p "$_confd"
  printf 'dovecot {\n\tmount.fstab = "%s/fstab";\n}\n' "$OLD" > "$_confd/dovecot.conf"

  # shellcheck disable=SC2317
  grep() { command grep "$@" "$_confd/dovecot.conf" 2>/dev/null; }

  run retire_jail_host_etc dovecot
  assert_success
  assert_output --partial "keeping $OLD"
  assert_output --partial "dovecot.conf"
  [ -f "$OLD/fstab" ]
  [ -d "$OLD/pf.conf.d" ]
}

# --- promote_staged_jail retires the old location only after a clean boot ---

promote_setup() {
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  export MT6_ETC="$BATS_TEST_TMPDIR/etc"
  CALLS="$BATS_TEST_TMPDIR/calls"
  : > "$CALLS"

  tell_status() { :; }
  seed_pkg_audit()        { :; }
  stop_jail()             { :; }
  stage_clear_caches()    { :; }
  stage_unmount()         { :; }
  ipcrm()                 { :; }
  rename_staged_to_ready(){ :; }
  rename_active_to_last() { :; }
  rename_ready_to_active(){ :; }
  enable_jail()           { :; }
  proclaim_success()      { :; }
  add_jail_conf()          { echo "add_jail_conf" >> "$CALLS"; }
  retire_jail_host_etc()   { echo "retire" >> "$CALLS"; }
  service()                { echo "start" >> "$CALLS"; return "${SERVICE_RC:-0}"; }
}

@test "promote_staged_jail - retires only after the jail starts" {
  promote_setup
  promote_staged_jail dovecot

  run cat "$CALLS"
  assert_line --index 0 "add_jail_conf"
  assert_line --index 1 "start"
  assert_line --index 2 "retire"
}

@test "promote_staged_jail - a failed start retires nothing" {
  promote_setup
  export SERVICE_RC=1

  run promote_staged_jail dovecot
  assert_failure

  run cat "$CALLS"
  refute_output --partial "retire"
}

