#!/usr/bin/env bats
# contrib/pfrule.sh resolves its rule directory across the layouts MT6 has used

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  PFRULE="$BATS_TEST_DIRNAME/../../contrib/pfrule.sh"
  # pfrule.sh readlink -f's its own path, so the fixture has to be the resolved
  # one too, or /var vs /private/var breaks the comparison on macOS
  mkdir -p "$BATS_TEST_TMPDIR/root"
  ROOT="$(cd "$BATS_TEST_TMPDIR/root" && pwd -P)"

  # the tests without -n execute; keep them off the host firewall
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export PFCTL_LOG="$ROOT/pfctl.log"
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

# --- the host-owned copy, rules under $MT6_ETC/<jail>/pf.conf.d ---

# the sibling fstab and rc.d must not be mistaken for the rule directory
@test "MT6_ETC - one copy serves a jail named on the command line" {
  mkdir -p "$ROOT/etc/webmail/rc.d"
  cp "$PFRULE" "$ROOT/etc/pfrule.sh"
  touch "$ROOT/etc/webmail/fstab"
  mkrules "$ROOT/etc/webmail/pf.conf.d"

  MT6_ETC="$ROOT/etc" run "$ROOT/etc/pfrule.sh" load webmail -n
  assert_success
  assert_output --partial "pfctl -a rdr/webmail -f $ROOT/etc/webmail/pf.conf.d/rdr.conf"
  refute_output --partial "$ROOT/etc/webmail/rdr.conf"
}

# jail.conf sets exec.clean, so exec.created runs with no environment
@test "MT6_ETC - a custom root survives a cleared environment" {
  mkdir -p "$ROOT/custom"
  cp "$PFRULE" "$ROOT/custom/pfrule.sh"
  mkrules "$ROOT/custom/webmail/pf.conf.d"

  run env -i PATH="$PATH" "$ROOT/custom/pfrule.sh" load webmail -n
  assert_success
  assert_output --partial "$ROOT/custom/webmail/pf.conf.d/rdr.conf"
}

@test "MT6_ETC - a per-jail copy still wins for its own jail" {
  local _p; _p=$(install_legacy dovecot)
  mkdir -p "$ROOT/etc"

  MT6_ETC="$ROOT/etc" run env -i PATH="$PATH" MT6_ETC="$ROOT/etc" "$_p" load -n
  assert_success
  assert_output --partial "/data/dovecot/etc/pf.conf.d/rdr.conf"
}

# --- PFRULE_ETC, an explicit override ---

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

@test "a second jail argument is rejected, not silently preferred" {
  local _p; _p=$(install_legacy dovecot)
  run "$_p" load dovecot haraka -n
  assert_failure
  assert_output --partial "usage:"
}

@test "a jail name with shell metacharacters is rejected" {
  local _p; _p=$(install_legacy dovecot)
  run "$_p" load 'dovecot;id' -n
  assert_failure
  assert_output --partial "invalid jail name"
}

@test "a jail name with whitespace is rejected" {
  local _p; _p=$(install_legacy dovecot)
  run "$_p" load 'two words' -n
  assert_failure
  assert_output --partial "invalid jail name"
}

@test "jail names MT6 actually uses are accepted" {
  mkrules "$ROOT/rules"
  local _p; _p=$(install_legacy dovecot)

  for _n in mail_dmarc bhyve-ubuntu php7 bsd_cache; do
    PFRULE_ETC="$ROOT/rules" run "$_p" unload "$_n" -n
    assert_success
    assert_output --partial "pfctl -a rdr/$_n -F nat"
  done
}

# --- $ETC_PATH is writable by the jail whose rules it holds ---

# no -n, so these execute; the marker is relative, a filename holds no '/'
@test "a rule filename cannot reach a shell" {
  local _dir="$ROOT/data/dovecot/etc/pf.conf.d"
  mkdir -p "$_dir"
  cp "$PFRULE" "$_dir/"
  touch "$_dir/x\$(touch pwned).table"

  cd "$ROOT"
  run "$_dir/pfrule.sh" unload
  assert_success
  [ ! -f "$ROOT/pwned" ]
  run grep -c '^-T$' "$PFCTL_LOG"
  assert_output "1"
}

@test "a rule filename with a semicolon runs no second command" {
  local _dir="$ROOT/data/dovecot/etc/pf.conf.d"
  mkdir -p "$_dir"
  cp "$PFRULE" "$_dir/"
  touch "$_dir/x;touch pwned;.table"

  cd "$ROOT"
  run "$_dir/pfrule.sh" unload
  assert_success
  [ ! -f "$ROOT/pwned" ]
}

@test "a rule filename with spaces stays one pfctl argument" {
  local _dir="$ROOT/data/dovecot/etc/pf.conf.d"
  mkdir -p "$_dir"
  cp "$PFRULE" "$_dir/"
  printf '10.0.0.1\n' > "$_dir/two words.table"

  run "$_dir/pfrule.sh" unload
  assert_success
  run grep -c '^two words$' "$PFCTL_LOG"
  assert_output "1"
}

@test "the anchor reaches pfctl as one argument" {
  local _p; _p=$(install_legacy dovecot)

  run "$_p" load
  assert_success
  run grep -c '^rdr/dovecot$' "$PFCTL_LOG"
  assert_output "1"
}

# --- PFRULE_ETC has to name a real directory ---

@test "a PFRULE_ETC that does not exist is an error, not a silent no-op" {
  local _p; _p=$(install_legacy dovecot)

  PFRULE_ETC="$ROOT/nowhere" run "$_p" load dovecot -n
  assert_failure
  assert_output --partial "PFRULE_ETC is not a directory"
}

@test "a PFRULE_ETC naming a file is an error" {
  local _p; _p=$(install_legacy dovecot)
  touch "$ROOT/afile"

  PFRULE_ETC="$ROOT/afile" run "$_p" unload dovecot -n
  assert_failure
  assert_output --partial "PFRULE_ETC is not a directory"
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
