#!/usr/bin/env bats
# Functional tests for provision/postfix.sh

setup_file() {
  export POSTFIX_FNS="$BATS_FILE_TMPDIR/postfix_fns_only.sh"
  sed '/^base_snapshot_exists/,$d' \
    "$BATS_TEST_DIRNAME/../../provision/postfix.sh" > "$POSTFIX_FNS"
}

setup() {
  load '../test_helper/load'

  export MT6_TEST_ENV=1
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
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
#     Instead of specifying complex smtpd_<xxx>_restrictions here,
#     specify "smtpd_<xxx>_restrictions=$mua_<xxx>_restrictions"
#     here, and specify mua_<xxx>_restrictions in main.cf (where
#     "<xxx>" is "client", "helo", "sender", "relay", or "recipient").
#  -o smtpd_client_restrictions=
#smtps     inet  n       -       n       -       -       smtpd
#  -o syslog_name=postfix/smtps
#  -o smtpd_tls_wrappermode=yes
#  -o smtpd_sasl_auth_enable=yes
#     Instead of specifying complex smtpd_<xxx>_restrictions here,
#     specify "smtpd_<xxx>_restrictions=$mua_<xxx>_restrictions"
#     here, and specify mua_<xxx>_restrictions in main.cf (where
#     "<xxx>" is "client", "helo", "sender", "relay", or "recipient").
#  -o smtpd_client_restrictions=
pickup    unix  n       -       n       60      1       pickup
EOF

  # shellcheck source=/dev/null
  . "$POSTFIX_FNS"
}

@test "enable_postfix_submission uncomments the submission and smtps blocks" {
  enable_postfix_submission "$MASTER_CF"

  run cat "$MASTER_CF"
  assert_success
  assert_line "submission inet n       -       n       -       -       smtpd"
  assert_line "  -o syslog_name=postfix/submission"
  assert_line "  -o smtpd_tls_security_level=encrypt"
  assert_line "smtps     inet  n       -       n       -       -       smtpd"
  assert_line "  -o smtpd_tls_wrappermode=yes"
}

@test "enable_postfix_submission leaves the rest of master.cf alone" {
  enable_postfix_submission "$MASTER_CF"

  run cat "$MASTER_CF"
  assert_success
  assert_line "#smtp      inet  n       -       n       -       1       postscreen"
  assert_line "smtp      inet  n       -       n       -       -       smtpd"
  assert_line "pickup    unix  n       -       n       60      1       pickup"
  # prose in the comment block is not an -o option to uncomment
  assert_line "#     Instead of specifying complex smtpd_<xxx>_restrictions here,"
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
  mkdir -p "$STAGE_MNT/usr/local/etc/postfix"
  mv "$MASTER_CF" "$STAGE_MNT/usr/local/etc/postfix"
  configure_postfix_master_cf

  run cat "$MASTER_CF"
  assert_line "submission inet n       -       n       -       -       smtpd"
  assert_line "smtps     inet  n       -       n       -       -       smtpd"
}

@test "configure_postfix_master_cf leaves submission disabled when TOASTER_MSA=haraka" {
  export TOASTER_MSA="haraka"
  mkdir -p "$STAGE_MNT/usr/local/etc/postfix"
  mv "$MASTER_CF" "$STAGE_MNT/usr/local/etc/postfix"
  configure_postfix_master_cf

  run cat "$MASTER_CF"
  assert_line "#submission inet n       -       n       -       -       smtpd"
  assert_line "#smtps     inet  n       -       n       -       -       smtpd"
}
