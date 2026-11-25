#!/usr/bin/env bats
# include/qmail.sh: the daemontools run scripts, and the daemons they leave behind

setup() {
  load '../test_helper/load'

  export SUPDIR="$BATS_TEST_TMPDIR/supervise"
  # qmail.sh sets -eu and a fixed SUP, so run a copy aimed at the sandbox
  sed "s|^SUP=.*|SUP=\"$SUPDIR\"|" "$BATS_TEST_DIRNAME/../../include/qmail.sh" \
    > "$BATS_TEST_TMPDIR/qmail.sh"
}

commands() { grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$'; }

@test "the deliverabled run script ends in a plain exec, no pipe" {
  run sh -c ". '$BATS_TEST_TMPDIR/qmail.sh'; install_service_qmail_deliverabled"
  assert_success

  local _run="$SUPDIR/deliverabled/run"
  run grep -c '|' "$_run"
  assert_output "0"

  run commands "$_run"
  [ "$(head -n 1 "$_run")" = "#!/bin/sh" ]
  assert_line --regexp '^exec \$BIN/softlimit .* \$BIN/qmail-deliverabled -f 2>&1$'
  [ "$(commands "$_run" | tail -n 1)" = 'exec $BIN/softlimit -m $MAXRAM $BIN/qmail-deliverabled -f 2>&1' ]
}

@test "the vpopmaild run script ends in a plain exec, no pipe" {
  run sh -c ". '$BATS_TEST_TMPDIR/qmail.sh'; install_service_vpopmaild"
  assert_success

  local _run="$SUPDIR/vpopmaild/run"
  run grep -c '|' "$_run"
  assert_output "0"
  [ "$(commands "$_run" | tail -n 1)" = 'exec /usr/local/bin/tcpserver -HRD 0.0.0.0 89 /usr/local/vpopmail/bin/vpopmaild 2>&1' ]
}

@test "install_service_log_run with a tag logs to syslog under it" {
  run sh -c ". '$BATS_TEST_TMPDIR/qmail.sh'; mkdir -p '$SUPDIR/deliverabled/log'; install_service_log_run deliverabled qmd"
  assert_success

  run commands "$SUPDIR/deliverabled/log/run"
  assert_line "exec /usr/local/bin/setuidgid qmaill /usr/bin/logger -t qmd"
  refute_output --partial multilog
  [ -x "$SUPDIR/deliverabled/log/run" ]
}

@test "install_service_log_run without a tag still uses multilog" {
  run sh -c ". '$BATS_TEST_TMPDIR/qmail.sh'; mkdir -p '$SUPDIR/qmail-send/log'; install_service_log_run qmail-send"
  assert_success

  run commands "$SUPDIR/qmail-send/log/run"
  assert_line "exec /usr/local/bin/setuidgid qmaill /usr/local/bin/multilog ./main"
}

@test "install_supervision gives deliverabled and vpopmaild syslog log services" {
  run grep -E '^\s+install_service_log_run (deliverabled qmd|vpopmaild vpopmaild)$' \
    "$BATS_TEST_DIRNAME/../../include/qmail.sh"
  assert_success
  assert_line --partial "deliverabled qmd"
  assert_line --partial "vpopmaild vpopmaild"
}

# a fixed process table, in the format of ps -ax -o pid=,ppid=,command=
fake_ps() {
  cat <<'EO_PS'
    1     0 /sbin/init
  210     1 /usr/local/bin/svscan /var/service
  330   210 supervise deliverabled
  412     1 /usr/local/bin/perl /usr/local/bin/qmail-deliverabled -f
  520   330 /usr/local/bin/perl /usr/local/bin/qmail-deliverabled -f
  530     1 /usr/local/bin/tcpserver -HRD 0.0.0.0 89 /usr/local/vpopmail/bin/vpopmaild
  540   210 /usr/local/bin/tcpserver -HRD 0.0.0.0 89 /usr/local/vpopmail/bin/vpopmaild
  777     1 /usr/sbin/cron
EO_PS
}

@test "qmail_orphans finds only daemons whose parent is init" {
  run sh -c ". '$BATS_TEST_TMPDIR/qmail.sh'; $(declare -f fake_ps); ps() { fake_ps; }; qmail_orphans qmail-deliverabled"
  assert_success
  assert_output "412"

  run sh -c ". '$BATS_TEST_TMPDIR/qmail.sh'; $(declare -f fake_ps); ps() { fake_ps; }; qmail_orphans 'tcpserver.*vpopmaild'"
  assert_output "530"
}

@test "kill_orphaned_daemon kills the orphan and leaves the supervised one" {
  run sh -c ". '$BATS_TEST_TMPDIR/qmail.sh'; $(declare -f fake_ps); ps() { fake_ps; }; kill() { echo \"kill \$*\"; }; kill_orphaned_daemon qmail-deliverabled"
  assert_success
  assert_line "kill 412"
  refute_output --partial "520"
}

@test "kill_orphaned_daemon with no orphan does nothing, and does not fail" {
  run sh -c ". '$BATS_TEST_TMPDIR/qmail.sh'; ps() { echo '    1     0 /sbin/init'; }; kill() { echo KILLED; }; kill_orphaned_daemon qmail-deliverabled"
  assert_success
  assert_output ""
}
