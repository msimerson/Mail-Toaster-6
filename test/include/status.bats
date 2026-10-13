#!/usr/bin/env bats

setup_file() {
  local _d="$BATS_FILE_TMPDIR/certs"
  mkdir -p "$_d"
  for _days in 365 10 3; do
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
      -keyout "$_d/$_days.key" -out "$_d/$_days.pem" -days "$_days" \
      -subj "/CN=mail.example.net" 2>/dev/null
  done
  echo "not a certificate" > "$_d/garbage.pem"
}

setup() {
  load '../test_helper/load'

  export JAIL_NET_PREFIX="172.16.15"
  export JAIL_NET_START=1
  export JAIL_ORDERED_LIST="syslog base dns mysql haraka dovecot"
  export ZFS_VOL="zroot"
  export ZFS_JAIL_VOL="zroot/jails"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  export TOASTER_HOSTNAME="mail.example.net"

  load '../../include/util.sh'
  load '../../include/jail.sh'
  load '../../include/network.sh'
  load '../../include/status.sh'

  CERTS="$BATS_FILE_TMPDIR/certs"
  JAIL_LIST="haraka dovecot"
  RUNNING="haraka dovecot"
  LISTENING="25 993 995"
  DATASETS=""
  ZPOOL_HEALTH="ONLINE"
  ZPOOL_CAP="41%"
  PF_STATUS="Enabled"

  id()                { echo 0; }
  sysrc()             { echo "$JAIL_LIST"; }
  freebsd-version()   { echo "14.3-RELEASE-p2"; }
  jail_is_running()   { case " $RUNNING " in *" $1 "*) return 0 ;; esac; return 1; }
  jls()               { [ "$3" = "ip4.addr" ] && get_jail_ip4 "$2"; }
  port_is_listening() { case " $LISTENING " in *" $1 "*) return 0 ;; esac; return 1; }
  pfctl()             { echo "Status: $PF_STATUS for 3 days 01:02:03"; }
  zfs()               { for _d in $DATASETS; do echo "$ZFS_JAIL_VOL/$_d"; done; }
  zpool() {
    case "$*" in
      *health*)   echo "$ZPOOL_HEALTH" ;;
      *capacity*) echo "$ZPOOL_CAP" ;;
    esac
  }
}

install_cert() {
  mkdir -p "$(dirname "$2")"
  cp "$CERTS/$1.pem" "$2"
}

@test "mt6_status - a healthy toaster is OK" {
  run mt6_status
  assert_success
  assert_output --partial "haraka   172.16.15.5  up     25       -"
  assert_output --partial "dovecot  172.16.15.6  up     993 995  -"
  assert_output --partial "pf enabled"
  assert_output --partial "MT6 OK - 2 jails"
}

@test "mt6_status - a jail that is not running is critical" {
  RUNNING="haraka"
  run mt6_status
  assert_failure 2
  assert_output --partial "dovecot  -            DOWN   -"
  assert_output --partial "CRITICAL: dovecot is not running"
  assert_output --partial "MT6 CRITICAL - 1 critical, 0 warning"
}

@test "mt6_status - a port nobody listens on is critical" {
  LISTENING="25 993"
  run mt6_status
  assert_failure 2
  assert_output --partial "993 995!"
  assert_output --partial "CRITICAL: dovecot is not listening on port 995"
}

@test "mt6_status - an IP the admin chose is not a warning" {
  host() { echo "should not be called"; }
  jls() { echo "172.16.16.8,66.128.51.173"; }
  JAIL_LIST="wordpress vhost0"
  RUNNING="wordpress vhost0"
  run mt6_status
  assert_success
  assert_output --partial "wordpress  172.16.16.8,66.128.51.173  up"
  refute_output --partial "should not be called"
}

@test "mt6_status - columns widen to fit long jail names" {
  JAIL_LIST="ns3.cadillac.net haraka"
  RUNNING="ns3_cadillac_net haraka"
  jls() { echo "172.16.16.3"; }
  run mt6_status
  assert_success
  assert_line "JAIL              IP           STATE  PORTS  TLS"
  assert_line "ns3.cadillac.net  172.16.16.3  up     -      -"
  assert_line "haraka            172.16.16.3  up     25     -"
}

@test "mt6_status - named jails limit the report" {
  run mt6_status haraka
  assert_success
  assert_output --partial "haraka "
  refute_output --partial "dovecot"
  assert_output --partial "MT6 OK - 1 jails"
}

@test "mt6_status - a named jail outside jail_list is still checked" {
  RUNNING="haraka dovecot mysql"
  LISTENING="3306"
  run mt6_status mysql
  assert_success
  assert_output --partial "mysql  172.16.15.4  up     3306"
}

@test "mt6_status - needs root" {
  id() { echo 1001; }
  run mt6_status
  assert_failure 3
  assert_output "status: run as root"
}

@test "mt6_status - nothing enabled is unknown" {
  JAIL_LIST=""
  run mt6_status
  assert_failure 3
  assert_output --partial "no jails in jail_list"
}

@test "mt6_status - a degraded zpool is critical" {
  ZPOOL_HEALTH="DEGRADED"
  run mt6_status
  assert_failure 2
  assert_output --partial "CRITICAL: zpool zroot is DEGRADED"
}

@test "mt6_status - a missing zpool is critical" {
  zpool() { return 1; }
  run mt6_status
  assert_failure 2
  assert_output --partial "CRITICAL: zpool zroot not found"
}

@test "mt6_status - a filling zpool warns, then goes critical" {
  ZPOOL_CAP="85%"
  run mt6_status
  assert_failure 1
  assert_output --partial "WARNING: zpool zroot is 85% full"

  ZPOOL_CAP="93%"
  run mt6_status
  assert_failure 2
  assert_output --partial "CRITICAL: zpool zroot is 93% full"
}

@test "mt6_status - pf disabled is critical" {
  PF_STATUS="Disabled"
  run mt6_status
  assert_failure 2
  assert_output --partial "pf DISABLED"
  assert_output --partial "CRITICAL: pf is not enabled"
}

@test "mt6_status - a leftover stage or ready dataset warns" {
  DATASETS="haraka stage dovecot.ready"
  run mt6_status
  assert_failure 1
  assert_output --partial "WARNING: stage exists"
  assert_output --partial "WARNING: dovecot.ready exists, its promotion failed"
}

@test "mt6_status - a .last dataset is informational" {
  DATASETS="haraka haraka.last dovecot dovecot.last"
  run mt6_status
  assert_success
  assert_output --partial "INFO: rollback available: haraka.last dovecot.last"
  refute_output --partial "not in jail_list"
}

@test "mt6_status - a .last for a jail no longer in jail_list is named apart" {
  DATASETS="haraka haraka.last snappymail.last ns3.cadillac.net.last"
  JAIL_LIST="haraka dovecot ns3.cadillac.net"
  RUNNING="haraka dovecot ns3_cadillac_net"
  run mt6_status
  assert_success
  assert_output --partial "INFO: rollback available: haraka.last ns3.cadillac.net.last"
  assert_output --partial "INFO: rollback for jails not in jail_list: snappymail.last"
}

@test "mt6_status - .last datasets are judged against jail_list, not the jails named" {
  DATASETS="haraka.last dovecot.last"
  run mt6_status haraka
  assert_success
  refute_output --partial "not in jail_list"
}

@test "mt6_status - an expiring jail certificate is reported" {
  install_cert 3 "$ZFS_DATA_MNT/dovecot/etc/tls/certs/$TOASTER_HOSTNAME.pem"
  run mt6_status
  assert_failure 2
  assert_line "dovecot  172.16.15.6  up     993 995  <7d"
  assert_output --partial "CRITICAL: dovecot TLS certificate <7d"
}

@test "mt6_status - a stopped jail still has its certificate checked" {
  RUNNING="haraka"
  install_cert 365 "$ZFS_DATA_MNT/dovecot/etc/tls/certs/$TOASTER_HOSTNAME.pem"
  run mt6_status dovecot
  assert_line "dovecot  -   DOWN   -      ok"
}

@test "status_tls_expiry - thresholds" {
  run status_tls_expiry "$CERTS/365.pem"
  assert_success
  assert_output "ok"

  run status_tls_expiry "$CERTS/10.pem"
  assert_failure 1
  assert_output "<14d"

  run status_tls_expiry "$CERTS/3.pem"
  assert_failure 2
  assert_output "<7d"

  run status_tls_expiry "$CERTS/garbage.pem"
  assert_failure 2
  assert_output "invalid"
}

@test "status_tls_expiry - an expired certificate" {
  openssl() { case "$*" in *checkend*) return 1 ;; esac; }
  run status_tls_expiry "$CERTS/365.pem"
  assert_failure 2
  assert_output "expired"
}

@test "status_jail_cert - finds each provisioner's certificate location" {
  install_cert 365 "$ZFS_DATA_MNT/postfix/etc/tls/certs/$TOASTER_HOSTNAME.pem"
  install_cert 365 "$ZFS_DATA_MNT/haproxy/etc/tls.d/$TOASTER_HOSTNAME.pem"
  install_cert 365 "$ZFS_DATA_MNT/haraka/config/tls/$TOASTER_HOSTNAME.pem"
  install_cert 365 "$ZFS_DATA_MNT/oldharaka/config/tls_cert.pem"

  run status_jail_cert postfix
  assert_output "$ZFS_DATA_MNT/postfix/etc/tls/certs/$TOASTER_HOSTNAME.pem"
  run status_jail_cert haproxy
  assert_output "$ZFS_DATA_MNT/haproxy/etc/tls.d/$TOASTER_HOSTNAME.pem"
  run status_jail_cert haraka
  assert_output "$ZFS_DATA_MNT/haraka/config/tls/$TOASTER_HOSTNAME.pem"
  run status_jail_cert oldharaka
  assert_output "$ZFS_DATA_MNT/oldharaka/config/tls_cert.pem"
  run status_jail_cert mysql
  assert_output ""
}

@test "status_jail_ports - webmail adds 443 when nginx terminates TLS" {
  TOASTER_WEBMAIL_PROXY="haproxy" run status_jail_ports webmail
  assert_output "80"
  TOASTER_WEBMAIL_PROXY="nginx" run status_jail_ports webmail
  assert_output "80 443"
}

# a provisioner's test_<jail>() and status must agree on what the jail listens on
@test "status_jail_ports - covers every port a provisioner tests" {
  local _f _jail _port _missing=""
  for _f in "$BATS_TEST_DIRNAME"/../../provision/*.sh; do
    _jail=$(basename "$_f" .sh)
    for _port in $(sed -n 's/^	stage_listening \([0-9][0-9]*\).*/\1/p' "$_f"); do
      case " $(status_jail_ports "$_jail") " in
        *" $_port "*) ;;
        *) _missing="$_missing $_jail:$_port" ;;
      esac
    done
  done
  [ -z "$_missing" ] || fail "status_jail_ports lacks:$_missing"
}
