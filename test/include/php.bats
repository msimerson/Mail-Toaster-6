#!/usr/bin/env bats

setup() {
  load '../test_helper/load'
  load '../../include/util.sh'
  load '../../include/php.sh'

  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  mkdir -p "$STAGE_MNT/usr/local/etc/php-fpm.d"

  cat > "$STAGE_MNT/usr/local/etc/php-fpm.conf" <<'EO_FPM'
[global]
; Pid file
; Note: the default prefix is /var
; Default Value: none
pid = run/php-fpm.pid

; Error log file
; If it's set to "syslog", log is sent to syslogd instead of being written
; into a local file.
; Note: the default prefix is /var
; Default Value: log/php-fpm.log
;error_log = log/php-fpm.log
EO_FPM

  cat > "$STAGE_MNT/usr/local/etc/php-fpm.d/www.conf" <<'EO_WWW'
[www]
listen = 127.0.0.1:9000
;listen.owner = www
;listen.group = www
;listen.mode = 0660
EO_WWW
}

mt6-include() { :; }
tell_status() { :; }
stage_enable_newsyslog() { :; }

# mail-toaster.sh is not loaded here
sed_inplace() { sed -i.bak "$@"; }

@test "configure_php_fpm - logs to the jail's /data/log" {
  configure_php_fpm

  run grep "error_log" "$STAGE_MNT/usr/local/etc/php-fpm.conf"
  assert_output "error_log = /data/log/php-fpm.log"
  [ -d "$STAGE_MNT/data/log" ]
}

@test "install_php_newsyslog - rotates the log and has php-fpm reopen it" {
  install_php_newsyslog

  run grep "^/" "$STAGE_MNT/etc/newsyslog.conf.d/php-fpm.conf"
  assert_output --regexp '^/data/log/php-fpm\.log[[:space:]].*/var/run/php-fpm\.pid[[:space:]]+30$'
}
