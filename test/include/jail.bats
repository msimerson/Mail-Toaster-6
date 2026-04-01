
setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  # Mock variables
  export JAIL_NET_PREFIX="172.16.15"
  export JAIL_NET_INTERFACE="lo1"
  export JAIL_NET_START=3
  export JAIL_ORDERED_LIST="syslog dns mysql"
  export ZFS_JAIL_MNT="/jails"
  export BASE_MNT="/jails/base-13.2-RELEASE"

  # Source the file under test
  load '../../include/jail.sh'
  load '../../include/util.sh'
  load '../../include/network.sh'
}

@test "safe_jailname - replaces dots" {
  run safe_jailname "my.jail"
  assert_output "my_jail"
}

@test "safe_jailname - replaces dashes" {
  run safe_jailname "my-jail"
  assert_output "my_jail"
}

@test "get_jail_ip - syslog" {
  run get_jail_ip syslog
  assert_output "172.16.15.1"
}

@test "get_jail_ip - dns" {
  run get_jail_ip dns
  assert_output "172.16.15.2"
}

@test "get_jail_ip - mysql" {
  run get_jail_ip mysql
  assert_output "172.16.15.3"
}

@test "jail_is_running - yes" {
  jls() {
    echo "myjail"
  }
  run jail_is_running myjail
  assert_success
}

@test "jail_is_running - no" {
  jls() { return 1; }
  run jail_is_running myjail
  assert_failure
}

@test "jail_conf_header - dns" {
  run jail_conf_header dns
  assert_output --partial "path = \"/jails/dns\";"
  assert_output --partial "interface = lo1;"
}

@test "jail_conf_header - base" {
  run jail_conf_header base
  assert_output --partial "path = \"/jails/base-13.2-RELEASE\";"
}

@test "get_reverse_ip" {
  run get_reverse_ip mysql
  assert_output "3.15.16.172.in-addr.arpa"
}

@test "get_reverse_ip6" {
  export JAIL_NET6="fd7a:e5cd:1fc1:c597"
  dec_to_hex() {
    if [ "$1" -eq 3 ]; then echo "3"; fi
  }
  run get_reverse_ip6 mysql
  assert_output "3.7.9.5.c.1.c.f.1.d.c.5.e.a.7.d.f.ip6.arpa"
}

@test "add_jail_conf" {
  export JAIL_NET6="fd7a:e5cd:1fc1:c597"
  dec_to_hex() {
    if [ "$1" -eq 3 ]; then echo "3"; fi
  }

  # Mock tee to capture output
  tee() {
    cat -
  }

  # Mock grep to not find jail.conf
  grep() { return 1; }
  get_public_ip() { export PUBLIC_IP6="2001:db8::1"; }
  store_config() {
    cat -
  }

  run add_jail_conf mysql
  assert_success
  assert_output --partial "mysql	{"
  assert_output --partial "ip4.addr = lo1|172.16.15.3;"
  assert_output --partial "ip6.addr = lo1|fd7a:e5cd:1fc1:c597:3;"
}

@test "add_jail_conf_d" {
  export JAIL_NET6="fd7a:e5cd:1fc1:c597"
  dec_to_hex() { if [ "$1" -eq 3 ]; then echo "3"; fi; }
  get_public_ip() { export PUBLIC_IP6="2001:db8::1"; }
  store_config() {
    cat -
  }

  run add_jail_conf_d mysql
  assert_success
  assert_output --partial "ip6.addr = lo1|fd7a:e5cd:1fc1:c597:3;"
}


