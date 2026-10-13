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
  LISTENING="haraka:25 dovecot:993 dovecot:995"
  JAIL_IP=""
  PROBE_FAIL=""
  DATASETS=""
  ZPOOL_HEALTH="ONLINE"
  ZPOOL_CAP="41%"
  PF_STATUS="Enabled"

  id()                { echo 0; }
  sysrc()             { echo "$JAIL_LIST"; }
  freebsd-version()   { echo "14.3-RELEASE-p2"; }
  jail_is_running()   { case " $RUNNING " in *" $1 "*) return 0 ;; esac; return 1; }

  # jail N in RUNNING has jid N and its daemon runs as pid 1000+N
  jls() {
    case "$1" in
      jid) local _n=0 _j
           for _j in $RUNNING; do _n=$((_n + 1)); echo "$_n $_j"; done ;;
      -j)  jail_is_running "$2" || return 1
           if [ -n "$JAIL_IP" ]; then echo "$JAIL_IP"; else get_jail_ip4 "$2"; fi ;;
    esac
  }
  ps() {
    echo "    1    0"
    local _n=0 _j
    for _j in $RUNNING; do _n=$((_n + 1)); echo " $((1000 + _n)) $_n"; done
  }
  sockstat() {
    echo "root     sendmail   1 4  tcp4  127.0.0.1:25          *:*"
    local _n=0 _j _l
    for _j in $RUNNING; do
      _n=$((_n + 1))
      for _l in $LISTENING; do
        if [ "${_l%%:*}" = "$_j" ]; then
          echo "root     daemon     $((1000 + _n)) 5  tcp46 *:${_l#*:}                  *:*"
        fi
      done
    done
  }
  pfctl()             { echo "Status: $PF_STATUS for 3 days 01:02:03"; }

  # each probe answers as a healthy service would, unless its jail is in PROBE_FAIL
  probe_fails() {
    local _j
    for _j in $PROBE_FAIL; do
      case "$*" in *"$(get_jail_ip4 "$_j"):"*|"$_j "*|*" $(get_jail_ip4 "$_j")") return 0 ;; esac
    done
    return 1
  }
  timeout() { shift; "$@"; }
  jexec() {
    if probe_fails "$@"; then echo "connection refused"; return 1; fi
    case "$2" in
      */redis-cli) echo "PONG" ;;
      */spamc)     echo "SPAMD/1.5 0" ;;
    esac
  }
  fetch() {
    if probe_fails "$@"; then return 1; fi
    echo "{\"pong\"}"
  }
  host() { ! probe_fails "$@"; }
  openssl() {
    if [ "$1" != "s_client" ]; then command openssl "$@"; return; fi
    echo "s_client $*" >> "$BATS_TEST_TMPDIR/s_client.calls"
    if probe_fails "$@"; then echo "connect:errno=61"; return 1; fi
    echo "CONNECTION ESTABLISHED"
  }
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
  assert_line "haraka   172.16.15.5  up     25         -        starttls ok"
  assert_line "dovecot  172.16.15.6  up     993 995    -        imaps ok"
  assert_output --partial "pf enabled"
  assert_output --partial "MT6 OK - 2 jails"
}

@test "mt6_status - each row prints before the next jail is checked" {
  status_port_listening() { echo "checking $1:$2"; }
  run mt6_status
  assert_success
  assert_line --index 1 --partial "JAIL"
  assert_line --index 2 "checking haraka:25"
  assert_line --index 3 --partial "haraka   172.16.15.5"
  assert_line --index 4 "checking dovecot:993"
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
  LISTENING="haraka:25 dovecot:993"
  run mt6_status
  assert_failure 2
  assert_output --partial "993 995!"
  assert_output --partial "CRITICAL: dovecot is not listening on port 995"
}

@test "mt6_status - an IP the admin chose is not a warning" {
  host() { echo "should not be called"; }
  JAIL_IP="172.16.16.8,66.128.51.173"
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
  JAIL_IP="172.16.16.3"
  run mt6_status
  assert_success
  assert_line "JAIL              IP           STATE  PORTS  TLS      PROBE"
  assert_line "ns3.cadillac.net  172.16.16.3  up     -      -        -"
  assert_line "haraka            172.16.16.3  up     25     -        starttls ok"
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
  LISTENING="mysql:3306"
  run mt6_status mysql
  assert_success
  assert_output --partial "mysql  172.16.15.4  up     3306"
}

@test "mt6_status - a port open on the host does not count for a jail" {
  LISTENING="dovecot:993 dovecot:995"
  run mt6_status haraka
  assert_failure 2
  assert_output --partial "CRITICAL: haraka is not listening on port 25"
}

@test "mt6_status - a port open in another jail does not count" {
  LISTENING="dovecot:25 dovecot:993 dovecot:995"
  run mt6_status haraka
  assert_failure 2
  assert_output --partial "CRITICAL: haraka is not listening on port 25"
}

@test "mt6_status - sockstat runs once, however many jails" {
  JAIL_LIST="haraka dovecot mysql dns"
  RUNNING="haraka dovecot mysql dns"
  eval "_real_$(declare -f sockstat)"
  sockstat() { echo x >> "$BATS_TEST_TMPDIR/sockstat.calls"; _real_sockstat; }
  run mt6_status
  assert_equal "$(wc -l < "$BATS_TEST_TMPDIR/sockstat.calls" | tr -d ' ')" 1
}

@test "status_load_listeners - reads the port from each address form" {
  jls() { echo "7 dns"; echo "9 jasonnoble"; }
  ps()  { echo "  500 7"; echo "84417 9"; echo "40243 9"; echo "  700 0"; }
  sockstat() {
    case " $* " in
      *" -w "*) cat <<'EO_WIDE'
unbound    unbound    500   3 udp4  172.16.15.3:53              *:*
unbound    unbound    500   4 tcp46 *:53                        *:*
www        httpd      84417 4 tcp6  [2605:ae00:329::11]:80      *:*
www        httpd      84417 6 tcp6  [2605:ae00:329::11]:443     *:*
www        httpd      84417 7 tcp4  *:443                       *:*
root       sshd       40243 6 tcp6  [2605:ae00:329::11]:22      *:*
root       sshd       700   3 tcp4  *:22                        *:*
?          ?          ?     ? udp4  *:111                       *:*
EO_WIDE
      ;;
      *) cat <<'EO_NARROW'
www        httpd      84417  4 tcp6  [2605:ae00:329::11]:8 *:*
www        httpd      84417  6 tcp6  [2605:ae00:329::11]:4 *:*
root       sshd       40243  6 tcp6  [2605:ae00:329::11]:2 *:*
EO_NARROW
      ;;
    esac
  }
  status_load_listeners
  assert_equal "$_status_listeners" "dns:53 jasonnoble:22 jasonnoble:443 jasonnoble:80 "
}

@test "status_load_listeners - no jails running is not an error" {
  jls() { return 1; }
  ps() { echo "  700 0"; }
  sockstat() { echo "root sshd 700 3 tcp4 *:22 *:*"; }
  status_load_listeners
  assert_equal "$_status_listeners" ""
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
  assert_line "dovecot  172.16.15.6  up     993 995    <7d      imaps ok"
  assert_output --partial "CRITICAL: dovecot TLS certificate <7d"
}

@test "mt6_status - a stopped jail still has its certificate checked" {
  RUNNING="haraka"
  install_cert 365 "$ZFS_DATA_MNT/dovecot/etc/tls/certs/$TOASTER_HOSTNAME.pem"
  run mt6_status dovecot
  assert_line "dovecot  -   DOWN   -          ok       -"
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

# --- ports seen on jails status has no expectations for ---

@test "mt6_status - a jail without expected ports shows what it listens on" {
  JAIL_LIST="haraka vhost0"
  RUNNING="haraka vhost0"
  LISTENING="haraka:25 vhost0:443 vhost0:80 vhost0:22"
  run mt6_status
  assert_success
  assert_line "vhost0  -            up     (22 80 443)  -        -"
  refute_output --partial "vhost0 is not listening"
}

@test "mt6_status - observed ports widen the column" {
  JAIL_LIST="haraka vhost0"
  RUNNING="haraka vhost0"
  LISTENING="haraka:25 vhost0:21 vhost0:22 vhost0:25 vhost0:80 vhost0:443 vhost0:8080"
  run mt6_status
  assert_line "JAIL    IP           STATE  PORTS                   TLS      PROBE"
  assert_line "haraka  172.16.15.5  up     25                      -        starttls ok"
}

@test "status_observed_ports - only the named jail, in numeric order" {
  _status_listeners="dovecot:993 vhost0:443 vhost0:80 vhost0:8080 vhost:25 "
  run status_observed_ports vhost0
  assert_output "(80 443 8080)"

  run status_observed_ports nothing
  assert_output ""
}

@test "status_observed_ports - leaves out syslogd's 514" {
  _status_listeners="geoip:514 vhost0:443 vhost0:514 vhost0:80 "
  run status_observed_ports vhost0
  assert_output "(80 443)"

  run status_observed_ports geoip
  assert_output ""
}

# --- probes: a short conversation with each service ---

@test "mt6_status - a failed probe is critical" {
  PROBE_FAIL="haraka"
  run mt6_status
  assert_failure 2
  assert_line --partial "haraka   172.16.15.5  up     25         -        starttls FAIL"
  assert_output --partial "CRITICAL: haraka starttls FAIL"
}

@test "mt6_status - no probe once a port is known closed" {
  LISTENING="haraka:25 dovecot:993"
  run mt6_status
  assert_line "dovecot  172.16.15.6  up     993 995!   -        -"
  run grep -c "15.6:993" "$BATS_TEST_TMPDIR/s_client.calls"
  assert_output "0"
}

@test "mt6_status - no probe for a stopped jail" {
  RUNNING="haraka"
  run mt6_status
  run grep -c "15.6" "$BATS_TEST_TMPDIR/s_client.calls"
  assert_output "0"
}

@test "status_probe - each service answers" {
  export TOASTER_MAIL_DOMAIN="example.net"
  mkdir -p "$ZFS_DATA_MNT/clamav/db"
  touch "$ZFS_DATA_MNT/clamav/db/daily.cld"

  run status_probe dns dns 172.16.15.3;                assert_success; assert_output "resolve ok"
  run status_probe dovecot dovecot 172.16.15.6;        assert_success; assert_output "imaps ok"
  run status_probe haproxy haproxy 172.16.15.12;       assert_success; assert_output "https ok"
  run status_probe haraka haraka 172.16.15.5;          assert_success; assert_output "starttls ok"
  run status_probe mysql mysql 172.16.15.4;            assert_success; assert_output "ping ok"
  run status_probe redis redis 172.16.15.16;           assert_success; assert_output "ping ok"
  run status_probe rspamd rspamd 172.16.15.13;         assert_success; assert_output "ping ok"
  run status_probe spamassassin spamassassin 172.16.15.6; assert_success; assert_output "ping ok"
  run status_probe vpopmail vpopmail 172.16.15.8;      assert_success; assert_output "postmaster ok"
  run status_probe clamav clamav 172.16.15.5;          assert_success; assert_output "sigs ok"
}

@test "status_probe - each service failing" {
  export JAIL_ORDERED_LIST="$JAIL_ORDERED_LIST clamav redis rspamd spamassassin vpopmail haproxy"
  PROBE_FAIL="dns dovecot haproxy haraka mysql redis rspamd spamassassin vpopmail clamav"
  local _j
  for _j in dns dovecot haproxy haraka mysql redis rspamd spamassassin vpopmail clamav; do
    run status_probe "$_j" "$_j" "$(get_jail_ip4 "$_j")"
    assert_failure 2
    assert_output --partial "FAIL"
  done
}

@test "status_probe - a reply without the expected text fails" {
  jexec() { echo "NOAUTH Authentication required"; }
  run status_probe redis redis 172.16.15.16
  assert_failure 2
  assert_line --index 0 "ping FAIL"
  assert_line --index 1 "NOAUTH Authentication required"
}

@test "status_probe - spamd's reply with or without PONG" {
  jexec() { echo "SPAMD/1.5 0 PONG"; }
  run status_probe spamassassin spamassassin 172.16.15.6
  assert_output "ping ok"

  jexec() { echo "SPAMD/1.5 76"; return 76; }
  run status_probe spamassassin spamassassin 172.16.15.6
  assert_failure 2
}

@test "mt6_status - a failed probe says why in its note, not its column" {
  jexec() { printf 'spamc: connect to spamd on 127.0.0.1 failed\nConnection refused\n'; return 69; }
  JAIL_LIST="spamassassin"
  RUNNING="spamassassin"
  LISTENING="spamassassin:783"
  run mt6_status
  assert_failure 2
  assert_line --partial "up     783    -        ping FAIL"
  assert_output --partial "CRITICAL: spamassassin ping FAIL: Connection refused"
}

@test "status_probe - a probe that hangs is cut off" {
  timeout() { return 124; }
  run status_probe mysql mysql 172.16.15.4
  assert_failure 2
  assert_line --index 1 "no reply within 10s"
}

@test "status_probe - a jail with no probe says nothing" {
  run status_probe vhost0 vhost0 172.16.16.14
  assert_success
  assert_output ""
}

@test "status_probe - the TLS probes never wait on stdin" {
  openssl() { [ "$1" = s_client ] && cat > /dev/null && echo "CONNECTION ESTABLISHED"; }
  run status_probe dovecot dovecot 172.16.15.6
  assert_output "imaps ok"
}

age_days() {
  perl -e '$t = time - $ARGV[0] * 86400; utime $t, $t, $ARGV[1]' "$1" "$2"
}

@test "status_probe_clamav - signature age" {
  local _db="$ZFS_DATA_MNT/clamav/db"
  mkdir -p "$_db"

  run status_probe_clamav clamav
  assert_failure 2
  assert_output "no sigs"

  touch "$_db/daily.cvd"
  age_days 5 "$_db/daily.cvd"
  run status_probe_clamav clamav
  assert_failure 1
  assert_output "sigs >3d"

  age_days 10 "$_db/daily.cvd"
  run status_probe_clamav clamav
  assert_failure 2
  assert_output "sigs >7d"

  touch "$_db/daily.cld"
  run status_probe_clamav clamav
  assert_success
  assert_output "sigs ok"
}

# --- inbound mail ports follow TOASTER_MTA and TOASTER_MSA ---

@test "status_jail_ports - the MTA and MSA jails expect the ports pf sends them" {
  TOASTER_MTA="haraka" TOASTER_MSA="haraka" run status_jail_ports haraka
  assert_output "25 465 587"

  TOASTER_MTA="postfix" TOASTER_MSA="dovecot" run status_jail_ports dovecot
  assert_output "993 995 465 587"

  TOASTER_MTA="postfix" TOASTER_MSA="dovecot" run status_jail_ports haraka
  assert_output "25"
}

@test "mt6_status - a closed submission port on the MSA jail is critical" {
  export TOASTER_MTA="haraka" TOASTER_MSA="haraka"
  LISTENING="haraka:25 haraka:465 dovecot:993 dovecot:995"
  run mt6_status
  assert_failure 2
  assert_output --partial "CRITICAL: haraka is not listening on port 587"
}

@test "mt6_status - ports beyond the expected ones are shown after them" {
  export TOASTER_MTA="haraka" TOASTER_MSA="haraka"
  LISTENING="haraka:25 haraka:465 haraka:587 haraka:80 haraka:514 dovecot:993 dovecot:995"
  run mt6_status
  assert_success
  assert_line "haraka   172.16.15.5  up     25 465 587 (80)     -        starttls ok"
  assert_line "dovecot  172.16.15.6  up     993 995             -        imaps ok"
}
