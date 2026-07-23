#!/usr/bin/env bats
# Functional tests for provision/postfix.sh

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export MT6_TEST_ENV=1
  export STAGE_MNT; STAGE_MNT=$(mktemp -d /tmp/mt6pfXXXXXX)
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  export ZFS_DATA_MNT="$STAGE_MNT/data"

  MASTER_CF="$ZFS_DATA_MNT/postfix/etc/master.cf"
  mkdir -p "$(dirname "$MASTER_CF")"
  cat > "$MASTER_CF" <<'EOF'
smtp      inet  n       -       n       -       -       smtpd
#smtp      inet  n       -       n       -       1       postscreen
#submission inet n       -       n       -       -       smtpd
#  -o syslog_name=postfix/submission
#  -o smtpd_tls_security_level=encrypt
#  -o smtpd_sasl_auth_enable=yes
#smtps     inet  n       -       n       -       -       smtpd
#  -o syslog_name=postfix/smtps
#  -o smtpd_tls_wrappermode=yes
#  -o smtpd_sasl_auth_enable=yes
pickup    unix  n       -       n       60      1       pickup
EOF

  # source the function definitions only; the execution block at the bottom
  # provisions a jail
  sed '/^base_snapshot_exists/,$d' "$BATS_TEST_DIRNAME/../../provision/postfix.sh" \
    > "$STAGE_MNT/postfix-functions.sh"
  # shellcheck source=/dev/null
  . "$STAGE_MNT/postfix-functions.sh"
}

teardown() {
  rm -rf "$STAGE_MNT"
}

@test "enable_postfix_submission uncomments the submission service block" {
  enable_postfix_submission "$MASTER_CF"

  run cat "$MASTER_CF"
  assert_success
  assert_line "submission inet n       -       n       -       -       smtpd"
  assert_line "  -o syslog_name=postfix/submission"
  assert_line "  -o smtpd_tls_security_level=encrypt"
}

@test "enable_postfix_submission uncomments the smtps service block" {
  enable_postfix_submission "$MASTER_CF"

  run cat "$MASTER_CF"
  assert_success
  assert_line "smtps     inet  n       -       n       -       -       smtpd"
  assert_line "  -o smtpd_tls_wrappermode=yes"
}

@test "enable_postfix_submission leaves unrelated commented services alone" {
  enable_postfix_submission "$MASTER_CF"

  run cat "$MASTER_CF"
  assert_success
  assert_line "#smtp      inet  n       -       n       -       1       postscreen"
  assert_line "smtp      inet  n       -       n       -       -       smtpd"
  assert_line "pickup    unix  n       -       n       60      1       pickup"
}

@test "enable_postfix_submission is idempotent" {
  enable_postfix_submission "$MASTER_CF"
  local _first; _first=$(cat "$MASTER_CF")
  enable_postfix_submission "$MASTER_CF"
  local _second; _second=$(cat "$MASTER_CF")
  [ "$_first" = "$_second" ]
}

@test "configure_postfix_master_cf enables submission when TOASTER_MSA=postfix" {
  export TOASTER_MSA="postfix"
  configure_postfix_master_cf

  run cat "$MASTER_CF"
  assert_line "submission inet n       -       n       -       -       smtpd"
  assert_line "smtps     inet  n       -       n       -       -       smtpd"
}

@test "configure_postfix_master_cf leaves submission disabled when TOASTER_MSA=haraka" {
  export TOASTER_MSA="haraka"
  configure_postfix_master_cf

  run cat "$MASTER_CF"
  assert_line "#submission inet n       -       n       -       -       smtpd"
  assert_line "#smtps     inet  n       -       n       -       -       smtpd"
}
