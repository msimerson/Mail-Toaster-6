#!/usr/bin/env bats
# contrib/pfrule.sh resolves its rule directory across the layouts MT6 has
# used. Every test runs with -n so pfctl is printed, never executed.

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  PFRULE="$BATS_TEST_DIRNAME/../../contrib/pfrule.sh"
  # pfrule.sh readlink -f's its own path, so the fixture has to be the resolved
  # one too, or /var vs /private/var breaks the comparison on macOS
  mkdir -p "$BATS_TEST_TMPDIR/root"
  ROOT="$(cd "$BATS_TEST_TMPDIR/root" && pwd -P)"
}

mkrules() {
  mkdir -p "$1"
  printf 'rdr pass inet proto tcp to port 25\n' > "$1/rdr.conf"
  printf '10.0.0.1\n' > "$1/known.table"
}

# <data>/<jail>/etc/pf.conf.d/pfrule.sh, the layout before the host-etc move
install_legacy() {
  local _dir="$ROOT/data/$1/etc/pf.conf.d"
  mkrules "$_dir"
  cp "$PFRULE" "$_dir/"
  echo "$_dir/pfrule.sh"
}

# --- legacy invocation, no jail argument ---

@test "legacy - derives the jail name from its own path" {
  local _p; _p=$(install_legacy dovecot)
  run "$_p" load -n
  assert_success
  assert_output --partial "pfctl -a rdr/dovecot -f"
}

@test "legacy - loads tables before anchors" {
  local _p; _p=$(install_legacy dovecot)
  run "$_p" load -n
  assert_line --index 0 --partial "pfctl -t known -T replace"
  assert_line --index 1 --partial "pfctl -a rdr/dovecot"
}

@test "legacy - unload flushes the anchor and the tables" {
  local _p; _p=$(install_legacy dovecot)
  run "$_p" unload -n
  assert_success
  assert_output --partial "pfctl -a rdr/dovecot -F nat"
  assert_output --partial "pfctl -t known -T flush"
}

@test "legacy - a per-jail copy still answers to its own jail name" {
  local _p; _p=$(install_legacy dovecot)
  run "$_p" load dovecot -n
  assert_success
  assert_output --partial "pfctl -a rdr/dovecot -f"
}

@test "legacy - a per-jail copy refuses another jail's name" {
  local _p; _p=$(install_legacy dovecot)
  run "$_p" load haraka -n
  assert_failure
  assert_output --partial "no rule directory for jail 'haraka'"
}

# --- PFRULE_ETC, the hook a future layout hangs off ---

@test "PFRULE_ETC overrides the directory derived from \$0" {
  local _p; _p=$(install_legacy dovecot)
  mkrules "$ROOT/elsewhere"

  PFRULE_ETC="$ROOT/elsewhere" run "$_p" load dovecot -n
  assert_success
  assert_output --partial "$ROOT/elsewhere/rdr.conf"
  refute_output --partial "/data/dovecot/"
}

@test "PFRULE_ETC lets the anchor be named for a jail this copy does not own" {
  local _p; _p=$(install_legacy dovecot)
  mkrules "$ROOT/elsewhere"

  PFRULE_ETC="$ROOT/elsewhere" run "$_p" unload mail_dmarc -n
  assert_success
  assert_output --partial "pfctl -a rdr/mail_dmarc -F nat"
}

# --- argument handling ---

@test "argument order - -n may precede the jail name" {
  local _p; _p=$(install_legacy dovecot)

  run "$_p" load -n dovecot
  assert_success
  assert_output --partial "pfctl -a rdr/dovecot"
}

@test "an unknown operation exits non-zero with usage" {
  local _p; _p=$(install_legacy dovecot)
  run "$_p" bogus
  assert_failure
  assert_output --partial "usage:"
}

@test "no arguments exits non-zero with usage" {
  local _p; _p=$(install_legacy dovecot)
  run "$_p"
  assert_failure
  assert_output --partial "usage:"
}

@test "an unknown flag exits non-zero with usage" {
  local _p; _p=$(install_legacy dovecot)
  run "$_p" load dovecot -x
  assert_failure
  assert_output --partial "usage:"
}

# --- anchors present and absent ---

@test "only the anchors with a .conf are touched" {
  local _p; _p=$(install_legacy dovecot)
  run "$_p" load -n
  assert_success
  assert_output --partial "rdr/dovecot"
  refute_output --partial "binat/dovecot"
  refute_output --partial "filter/dovecot"
}

@test "a rule directory with no files is a no-op, not an error" {
  local _dir="$ROOT/data/quiet/etc/pf.conf.d"
  mkdir -p "$_dir"
  cp "$PFRULE" "$_dir/"

  run "$_dir/pfrule.sh" load -n
  assert_success
  refute_output --partial "pfctl"
}

# --- cleanup() renames relative to the rule dir, not the cwd ---

@test "cleanup - allow.conf becomes filter.conf in the rule directory" {
  local _p; _p=$(install_legacy dovecot)
  local _dir="$ROOT/data/dovecot/etc/pf.conf.d"
  printf 'pass in\n' > "$_dir/allow.conf"

  run "$_p" load -n
  assert_success
  [ ! -f "$_dir/allow.conf" ]
  [ -f "$_dir/filter.conf" ]
}

@test "cleanup - allow.conf becomes allow.bak when filter.conf exists" {
  local _p; _p=$(install_legacy dovecot)
  local _dir="$ROOT/data/dovecot/etc/pf.conf.d"
  printf 'pass in\n'  > "$_dir/allow.conf"
  printf 'block in\n' > "$_dir/filter.conf"

  run "$_p" load -n
  assert_success
  [ -f "$_dir/allow.bak" ]
  run cat "$_dir/filter.conf"
  assert_output "block in"
}

@test "cleanup - does not touch the working directory" {
  local _p; _p=$(install_legacy dovecot)
  printf 'pass in\n' > "$ROOT/allow.conf"

  cd "$ROOT"
  run "$_p" load -n
  assert_success
  [ -f "$ROOT/allow.conf" ]
  [ ! -f "$ROOT/filter.conf" ]
}
