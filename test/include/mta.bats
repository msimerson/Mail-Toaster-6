#!/usr/bin/env bats

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  export BASE; BASE=$(mktemp -d)
  mkdir -p "$BASE/etc/mail" "$BASE/usr/libexec" "$BASE/usr/local/libexec"

  export TOASTER_MSA="mail.example.com"
  export TOASTER_HOSTNAME="host.example.com"
  export TOASTER_ADMIN_EMAIL="postmaster@example.com"
  export TOASTER_BASE_MTA=""

  load '../../include/mta.sh'
}

teardown() {
  rm -rf "$BASE"
}

tell_status() { :; }
set_root_alias() { :; }
jail_is_running() { [ "$STAGE_RUNNING" = "1" ]; }
stage_pkg_install() { echo "stage_pkg_install $*" >> "$BASE/pkg.log"; }
pkg() { echo "pkg $*" >> "$BASE/pkg.log"; }

@test "configure_mta - defaults to dma when none installed" {
  install_ssmtp() { echo ssmtp >> "$BASE/chose"; }
  enable_dma() { echo dma >> "$BASE/chose"; }
  disable_sendmail() { :; }

  configure_mta "$BASE"
  run cat "$BASE/chose"
  assert_output "dma"
}

@test "configure_mta - ssmtp only when explicitly requested" {
  install_ssmtp() { echo ssmtp >> "$BASE/chose"; }
  enable_dma() { echo dma >> "$BASE/chose"; }
  disable_sendmail() { :; }

  configure_mta "$BASE" ssmtp
  run cat "$BASE/chose"
  assert_output "ssmtp"
}

@test "enable_dma - prefers base dma over installing" {
  local _base="$BASE"
  : > "$BASE/usr/libexec/dma"; chmod +x "$BASE/usr/libexec/dma"

  enable_dma > /dev/null
  assert [ ! -f "$BASE/pkg.log" ]
  run grep sendmail "$BASE/etc/mail/mailer.conf"
  assert_output --partial "/usr/libexec/dma"
}

@test "enable_dma - base dma reads config from /etc/dma" {
  local _base="$BASE"
  : > "$BASE/usr/libexec/dma"; chmod +x "$BASE/usr/libexec/dma"

  enable_dma > /dev/null
  run grep SMARTHOST "$BASE/etc/dma/dma.conf"
  assert_output "SMARTHOST mail.example.com"
}

@test "enable_dma - port dma reads config from PREFIX/etc/dma" {
  local _base="$BASE"
  : > "$BASE/usr/local/libexec/dma"; chmod +x "$BASE/usr/local/libexec/dma"

  enable_dma > /dev/null
  run grep SMARTHOST "$BASE/usr/local/etc/dma/dma.conf"
  assert_output "SMARTHOST mail.example.com"
}

@test "enable_dma - port dma wins over base dma" {
  local _base="$BASE"
  : > "$BASE/usr/libexec/dma"; chmod +x "$BASE/usr/libexec/dma"
  : > "$BASE/usr/local/libexec/dma"; chmod +x "$BASE/usr/local/libexec/dma"

  enable_dma > /dev/null
  run grep sendmail "$BASE/etc/mail/mailer.conf"
  assert_output --partial "/usr/local/libexec/dma"
}

@test "enable_dma - mailer.conf path is relative to the jail root" {
  local _base="$BASE"
  : > "$BASE/usr/local/libexec/dma"; chmod +x "$BASE/usr/local/libexec/dma"

  enable_dma > /dev/null
  run grep -c "$BASE" "$BASE/etc/mail/mailer.conf"
  assert_output "0"
}

@test "enable_dma - installs into the stage jail when it is running" {
  local _base="$BASE"
  export STAGE_RUNNING=1

  enable_dma > /dev/null
  run cat "$BASE/pkg.log"
  assert_output "stage_pkg_install dma"
}

@test "enable_dma - installs on the host when no stage jail is running" {
  local _base="$BASE"
  export STAGE_RUNNING=0

  enable_dma > /dev/null
  run cat "$BASE/pkg.log"
  assert_output "pkg install -y dma"
}
