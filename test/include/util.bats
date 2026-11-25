#!/usr/bin/env bats

setup() {
  load '../test_helper/load'
  load '../../include/util.sh'
}

@test "mt6_version - outputs 8-digit date" {
  run mt6_version
  assert_success
  assert_output --regexp '^[0-9]{8}$'
}

@test "tell_status - outputs message" {
  run tell_status "hello"
  assert_success
  assert_output --partial "hello"
}

@test "freebsd_major - root dir chroots and extracts major version" {
  chroot() { echo "14.2-RELEASE-p1"; }
  run freebsd_major /stage
  assert_success
  assert_output "14"
}

@test "dec_to_hex - 255" {
  run dec_to_hex 255
  assert_output "00ff"
}

@test "dec_to_hex - 0" {
  run dec_to_hex 0
  assert_output "0000"
}

@test "dec_to_hex - 65535" {
  run dec_to_hex 65535
  assert_output "ffff"
}

@test "dec_to_hex - 16" {
  run dec_to_hex 16
  assert_output "0010"
}

@test "store_config - new file" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/new_file"

  echo "hello" | store_config "$tmpfile"

  run cat "$tmpfile"
  assert_output "hello"

  rm -rf "$tmpdir"
}

@test "store_config - preserve existing" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/new_file"
  echo "original" > "$tmpfile"

  echo "new" | store_config "$tmpfile"

  run cat "$tmpfile"
  assert_output "original"

  rm -rf "$tmpdir"
}

@test "store_config - overwrite existing" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/new_file"
  echo "original" > "$tmpfile"

  echo "new" | store_config "$tmpfile" "overwrite"

  run cat "$tmpfile"
  assert_output "new"

  rm -rf "$tmpdir"
}

@test "store_config - append to existing" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/new_file"
  echo "first" > "$tmpfile"

  echo "second" | store_config "$tmpfile" "append"

  run cat "$tmpfile"
  assert_output "$(printf 'first\nsecond')"

  rm -rf "$tmpdir"
}

@test "store_config - shadow copy is not world readable" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/secret.conf"

  echo "password=hunter2" | store_config "$tmpfile"

  run _file_mode "$tmpfile.mt6"
  assert_output "600"

  rm -rf "$tmpdir"
}

@test "store_config - shadow is tightened on every operation" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/secret.conf"

  echo "first" | store_config "$tmpfile"
  echo "second" | store_config "$tmpfile" "append"
  run _file_mode "$tmpfile.mt6"
  assert_output "600"

  echo "third" | store_config "$tmpfile" "overwrite"
  run _file_mode "$tmpfile.mt6"
  assert_output "600"

  rm -rf "$tmpdir"
}

# The shadow is the source of the cp that installs $1, so a shadow left at 600
# by an earlier run must not drag the installed config down with it.
@test "store_config - a tightened shadow does not tighten a reinstalled file" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  umask 022
  echo "one" | store_config "$tmpfile"
  local _first; _first=$(_file_mode "$tmpfile")

  rm -f "$tmpfile"          # shadow survives at 600
  echo "two" | store_config "$tmpfile"

  run _file_mode "$tmpfile"
  assert_output "$_first"

  rm -rf "$tmpdir"
}

@test "store_config - update replaces a file matching the previous shadow" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "v1" | store_config "$tmpfile"          # installs v1, shadow = v1
  echo "v2" | store_config "$tmpfile" "update" # untouched since, so take v2

  run cat "$tmpfile"
  assert_output "v2"

  rm -rf "$tmpdir"
}

@test "store_config - update backs up what it replaces" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "v1" | store_config "$tmpfile"
  echo "v2" | store_config "$tmpfile" "update"

  run cat "$tmpfile".2*
  assert_output "v1"

  rm -rf "$tmpdir"
}

@test "store_config - overwrite backs nothing up" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "v1" | store_config "$tmpfile"
  echo "hand edited" > "$tmpfile"
  echo "v2" | store_config "$tmpfile" "overwrite"

  run ls "$tmpdir"
  refute_output --partial "app.conf.2"

  rm -rf "$tmpdir"
}

@test "store_config - a first install has nothing to back up" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "v1" | store_config "$tmpfile"

  run ls "$tmpdir"
  refute_output --partial "app.conf.2"

  rm -rf "$tmpdir"
}

@test "store_config - the day's first backup survives later runs" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "v1" | store_config "$tmpfile"
  echo "v2" | store_config "$tmpfile" "update"
  echo "v3" | store_config "$tmpfile" "update"

  run cat "$tmpfile".2*
  assert_output "v1"

  rm -rf "$tmpdir"
}

@test "store_config - preserving a file backs nothing up" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "v1" | store_config "$tmpfile"
  echo "hand edited" > "$tmpfile"
  echo "v2" | store_config "$tmpfile" "update"

  run ls "$tmpdir"
  refute_output --partial "app.conf.2"

  rm -rf "$tmpdir"
}

@test "store_config - update preserves a file the admin edited" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "v1" | store_config "$tmpfile"
  echo "hand edited" > "$tmpfile"
  echo "v2" | store_config "$tmpfile" "update"

  run cat "$tmpfile"
  assert_output "hand edited"

  rm -rf "$tmpdir"
}

# An edit that is later reverted is not a customization worth keeping.
@test "store_config - update resumes after an edit is reverted" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "v1" | store_config "$tmpfile"
  echo "hand edited" > "$tmpfile"
  echo "v2" | store_config "$tmpfile" "update"   # preserved
  run cat "$tmpfile"
  assert_output "hand edited"

  echo "v2" > "$tmpfile"                          # admin reverts to our version
  echo "v3" | store_config "$tmpfile" "update"
  run cat "$tmpfile"
  assert_output "v3"

  rm -rf "$tmpdir"
}

# A pre-existing file with no shadow predates us; we have no idea if it is ours.
@test "store_config - update preserves a file with no shadow" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "someone elses" > "$tmpfile"
  echo "v1" | store_config "$tmpfile" "update"

  run cat "$tmpfile"
  assert_output "someone elses"

  rm -rf "$tmpdir"
}

@test "store_config - update installs when the file is absent" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "v1" | store_config "$tmpfile" "update"

  run cat "$tmpfile"
  assert_output "v1"

  rm -rf "$tmpdir"
}

@test "store_config - update keeps the mode the admin set" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "v1" | store_config "$tmpfile"
  chmod 640 "$tmpfile"
  echo "v2" | store_config "$tmpfile" "update"

  run _file_mode "$tmpfile"
  assert_output "640"

  rm -rf "$tmpdir"
}

@test "store_config - append never updates in place" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/app.conf"

  echo "first" | store_config "$tmpfile"
  echo "second" | store_config "$tmpfile" "append"

  run cat "$tmpfile"
  assert_line --index 0 "first"
  assert_line --index 1 "second"

  rm -rf "$tmpdir"
}

@test "store_config - creates parent directories" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/nested/dir/file"

  echo "content" | store_config "$tmpfile"

  [ -f "$tmpfile" ]

  rm -rf "$tmpdir"
}

# --- preserve_config_dir ---

_cfg_dirs() {
  export ZFS_JAIL_MNT="$BATS_TEST_TMPDIR/jails"
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  _live="$ZFS_JAIL_MNT/svc/etc/svc/local.d"
  _stage="$STAGE_MNT/etc/svc/local.d"
  mkdir -p "$_live" "$_stage"
}

_mt6_wrote() { printf '%s\n' "$2" > "$1"; printf '%s\n' "$2" > "$1.mt6"; }

@test "preserve_config_dir - carries a file the admin edited" {
  _cfg_dirs
  _mt6_wrote "$_live/a.conf" "default"
  echo "tuned" > "$_live/a.conf"

  preserve_config_dir svc /etc/svc/local.d

  run cat "$_stage/a.conf"
  assert_output "tuned"
}

@test "preserve_config_dir - does not carry an untouched default" {
  _cfg_dirs
  _mt6_wrote "$_live/a.conf" "default"

  preserve_config_dir svc /etc/svc/local.d

  [ ! -e "$_stage/a.conf" ]
}

@test "preserve_config_dir - carries a file the admin added" {
  _cfg_dirs
  echo "mine" > "$_live/multimap.conf"

  preserve_config_dir svc /etc/svc/local.d

  run cat "$_stage/multimap.conf"
  assert_output "mine"
}

@test "preserve_config_dir - keeps the stage's file when the package ships one" {
  _cfg_dirs
  echo "old package" > "$_live/shipped.conf"
  echo "new package" > "$_stage/shipped.conf"

  preserve_config_dir svc /etc/svc/local.d

  run cat "$_stage/shipped.conf"
  assert_output "new package"
}

@test "preserve_config_dir - never carries a shadow" {
  _cfg_dirs
  _mt6_wrote "$_live/a.conf" "default"
  echo "tuned" > "$_live/a.conf"

  preserve_config_dir svc /etc/svc/local.d

  [ ! -e "$_stage/a.conf.mt6" ]
}

@test "preserve_config_dir - follows subdirectories and keeps the mode" {
  _cfg_dirs
  mkdir -p "$_live/maps.d"
  echo "x" > "$_live/maps.d/allow.map"
  chmod 640 "$_live/maps.d/allow.map"

  preserve_config_dir svc /etc/svc/local.d

  run cat "$_stage/maps.d/allow.map"
  assert_output "x"
  run _file_mode "$_stage/maps.d/allow.map"
  assert_output "640"
}

@test "preserve_config_dir - handles a name with a space" {
  _cfg_dirs
  echo "x" > "$_live/two words.conf"

  preserve_config_dir svc /etc/svc/local.d

  run cat "$_stage/two words.conf"
  assert_output "x"
}

@test "preserve_config_dir - falls back to the previous jail" {
  _cfg_dirs
  mkdir -p "$ZFS_JAIL_MNT/svc.last/etc/svc/local.d"
  echo "from last" > "$ZFS_JAIL_MNT/svc.last/etc/svc/local.d/b.conf"
  rm -r "$ZFS_JAIL_MNT/svc"

  preserve_config_dir svc /etc/svc/local.d

  run cat "$_stage/b.conf"
  assert_output "from last"
}

@test "preserve_config_dir - is a no-op without a running jail" {
  export ZFS_JAIL_MNT="$BATS_TEST_TMPDIR/jails"
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  mkdir -p "$STAGE_MNT"

  run preserve_config_dir svc /etc/svc/local.d
  assert_success
  [ ! -e "$STAGE_MNT/etc" ]
}

@test "preserve_config_dir - what it carries survives store_config, a default is regenerated" {
  _cfg_dirs
  _mt6_wrote "$_live/edited.conf" "default"
  echo "tuned" > "$_live/edited.conf"
  _mt6_wrote "$_live/pristine.conf" "old default"

  preserve_config_dir svc /etc/svc/local.d
  echo "new default" | store_config "$_stage/edited.conf"
  echo "new default" | store_config "$_stage/pristine.conf"

  run cat "$_stage/edited.conf"
  assert_output "tuned"
  run cat "$_stage/pristine.conf"
  assert_output "new default"
}

@test "store_exec - creates executable file" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/script.sh"

  echo "#!/bin/sh" | store_exec "$tmpfile"

  [ -x "$tmpfile" ]

  rm -rf "$tmpdir"
}

@test "store_exec - file has 755 permissions" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/script.sh"

  echo "#!/bin/sh" | store_exec "$tmpfile"

  run find "$tmpdir" -name "script.sh" -perm 755
  assert_output "$tmpfile"

  rm -rf "$tmpdir"
}

@test "store_exec - file contains expected content" {
  local tmpdir; tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/script.sh"

  printf '#!/bin/sh\necho hello\n' | store_exec "$tmpfile"

  run cat "$tmpfile"
  assert_output "$(printf '#!/bin/sh\necho hello')"

  rm -rf "$tmpdir"
}

@test "get_random_pass - default length 14" {
  run get_random_pass
  assert_success
  [ "${#output}" -eq 14 ]
}

@test "get_random_pass - custom length" {
  run get_random_pass 20
  assert_success
  [ "${#output}" -eq 20 ]
}

@test "get_random_pass - safe mode is alphanumeric only" {
  run get_random_pass 32 safe
  assert_success
  assert_output --regexp '^[A-Za-z0-9]+$'
}

@test "get_random_pass - safe mode length" {
  run get_random_pass 16 safe
  assert_success
  [ "${#output}" -eq 16 ]
}

@test "get_random_pass - strong mode length" {
  run get_random_pass 16 strong
  assert_success
  [ "${#output}" -eq 16 ]
}

@test "reverse_list - three items" {
  run reverse_list one two three
  assert_output "three two one "
}

@test "reverse_list - single item" {
  run reverse_list one
  assert_output "one "
}

@test "reverse_list - two items" {
  run reverse_list a b
  assert_output "b a "
}

pkg_cache_root() {
  local _root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$_root/usr/local/etc/pkg/repos" "$_root/etc"
  echo "#VULNXML_SITE: https://vuxml.freebsd.org/freebsd/vuln.xml.xz" \
    > "$_root/usr/local/etc/pkg.conf"
  echo "ServerName update.FreeBSD.org" > "$_root/etc/freebsd-update.conf"
  echo "$_root"
}

@test "pkg_use_bsd_cache - disables FreeBSD-ports repo in a FreeBSD.conf base.sh already wrote" {
  chroot() { echo "15.1-RELEASE"; }
  sed_inplace() { sed -i.bak "$@"; }
  local _root; _root=$(pkg_cache_root)

  echo 'FreeBSD-ports: { url: "pkg+http://pkg.FreeBSD.org/${ABI}/latest" }' \
    > "$_root/usr/local/etc/pkg/repos/FreeBSD.conf"

  pkg_use_bsd_cache "$_root"

  run cat "$_root/usr/local/etc/pkg/repos/FreeBSD.conf"
  assert_output --partial "FreeBSD-ports: { enabled: no }"
  refute_output --partial "pkg.FreeBSD.org"
  assert_output --partial "FreeBSD-ports-kmods: { enabled: no }"
}

@test "pkg_use_bsd_cache - disables FreeBSD-ports-kmods repo in a FreeBSD.conf base.sh already wrote" {
  chroot() { echo "15.1-RELEASE"; }
  sed_inplace() { sed -i.bak "$@"; }
  local _root; _root=$(pkg_cache_root)

  echo 'FreeBSD-ports: { url: "pkg+http://pkg.FreeBSD.org/${ABI}/latest" }' \
    > "$_root/usr/local/etc/pkg/repos/FreeBSD.conf"

  pkg_use_bsd_cache "$_root"

  run cat "$_root/usr/local/etc/pkg/repos/FreeBSD.conf"
  assert_output --partial "FreeBSD-ports-kmods: { enabled: no }"
}

@test "pkg_use_bsd_cache - names the pre-15 repo FreeBSD" {
  chroot() { echo "14.3-RELEASE-p2"; }
  sed_inplace() { sed -i.bak "$@"; }
  local _root; _root=$(pkg_cache_root)

  pkg_use_bsd_cache "$_root"

  run cat "$_root/usr/local/etc/pkg/repos/FreeBSD.conf"
  assert_output --partial "FreeBSD: {"
  refute_output --partial "FreeBSD-ports"
}

@test "pkg_use_bsd_cache - points MT6 at the cache" {
  chroot() { echo "15.1-RELEASE"; }
  sed_inplace() { sed -i.bak "$@"; }
  local _root; _root=$(pkg_cache_root)
  TOASTER_PKG_BRANCH=latest

  pkg_use_bsd_cache "$_root"

  run cat "$_root/usr/local/etc/pkg/repos/MT6.conf"
  assert_output --partial 'url: "http://pkg/${ABI}/latest"'
  assert_output --partial "enabled: yes"
}

@test "pkg_use_bsd_cache - redirects vulnxml and freebsd-update" {
  chroot() { echo "15.1-RELEASE"; }
  sed_inplace() { sed -i.bak "$@"; }
  local _root; _root=$(pkg_cache_root)

  pkg_use_bsd_cache "$_root"

  run cat "$_root/usr/local/etc/pkg.conf"
  assert_output --partial "VULNXML_SITE"
  assert_output --partial "vulnxml/freebsd"
  refute_output --partial "vuxml.freebsd.org"

  run cat "$_root/etc/freebsd-update.conf"
  assert_output "ServerName freebsd-update"
}

@test "configure_pkg_extra - updates MT6_extra.conf when TOASTER_PKG_EXTRA is set" {
  local _root; _root=$(pkg_cache_root)
  export TOASTER_PKG_EXTRA='my-repo { url: "http://example.com", priority: 10 }'

  echo 'WHATEVER' > "$_root/usr/local/etc/pkg/repos/MT6_extra.conf"

  configure_pkg_extra "$_root"

  run cat "$_root/usr/local/etc/pkg/repos/MT6_extra.conf"
  assert_output --partial "my-repo"
  refute_output --partial "WHATEVER"
}

@test "configure_pkg_extra - clears MT6_extra.conf when TOASTER_PKG_EXTRA is empty" {
  local _root; _root=$(pkg_cache_root)
  export TOASTER_PKG_EXTRA=''

  echo 'WHATEVER' > "$_root/usr/local/etc/pkg/repos/MT6_extra.conf"
  echo 'WHATEVER' > "$_root/usr/local/etc/pkg/repos/MT6_extra.conf.mt6"

  configure_pkg_extra "$_root"

  run ls "$_root/usr/local/etc/pkg/repos"
  refute_output --partial "MT6_extra"
}

@test "configure_pkg_extra - pkg reads it after the repo files MT6 writes" {
  local _root; _root=$(pkg_cache_root)
  local _repos="$_root/usr/local/etc/pkg/repos"
  export TOASTER_PKG_EXTRA='MT6: { enabled: no }'
  touch "$_repos/FreeBSD.conf" "$_repos/FreeBSD-base.conf" "$_repos/MT6.conf"

  configure_pkg_extra "$_root"

  run sh -c "cd '$_repos' && LC_ALL=C ls *.conf | tail -n1"
  assert_output "MT6_extra.conf"
}
