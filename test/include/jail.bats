
setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  # Mock variables
  export JAIL_NET_PREFIX="172.16.15"
  export JAIL_NET_INTERFACE="lo1"
  export JAIL_NET_START=1
  export JAIL_ORDERED_LIST="syslog base dns mysql"
  export ZFS_JAIL_MNT="/jails"
  export BASE_MNT="/jails/base-13.2-RELEASE"
  export ZFS_DATA_MNT="/data"

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
  assert_output "172.16.15.3"
}

@test "get_jail_ip - mysql" {
  run get_jail_ip mysql
  assert_output "172.16.15.4"
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
  assert_output "4.15.16.172.in-addr.arpa"
}

@test "get_reverse_ip6" {
  export JAIL_NET6="fd7a:e5cd:1fc1:c597"
  dec_to_hex() {
    if [ "$1" -eq 4 ]; then echo "4"; fi
  }
  run get_reverse_ip6 mysql
  assert_output "4.7.9.5.c.1.c.f.1.d.c.5.e.a.7.d.f.ip6.arpa"
}

@test "add_jail_conf" {
  export JAIL_NET6="fd7a:e5cd:1fc1:c597"
  dec_to_hex() {
    if [ "$1" -eq 4 ]; then echo "4"; fi
  }

  # Mock tee to capture output
  tee() {
    cat -
  }

  # Mock grep to not find jail.conf
  grep() { return 1; }
  get_public_ip6() { export PUBLIC_IP6="2001:db8::1"; }
  store_config() {
    cat -
  }
  migrate_jail_conf_etc() { :; }

  run add_jail_conf mysql
  assert_success
  assert_output --partial "mysql	{"
  assert_output --partial "ip4.addr = lo1|172.16.15.4;"
  assert_output --partial "ip6.addr = lo1|fd7a:e5cd:1fc1:c597:4;"
}

@test "add_jail_conf_d" {
  export JAIL_NET6="fd7a:e5cd:1fc1:c597"
  dec_to_hex() { if [ "$1" -eq 4 ]; then echo "4"; fi; }
  get_public_ip6() { export PUBLIC_IP6="2001:db8::1"; }
  store_config() {
    cat -
  }
  migrate_jail_conf_etc() { :; }

  run add_jail_conf_d mysql
  assert_success
  assert_output --partial "ip6.addr = lo1|fd7a:e5cd:1fc1:c597:4;"
}

# --- base declares no mounts and runs no pf rules ---

@test "get_jail_data - base is not special" {
  export ZFS_DATA_MNT="/data"
  run get_jail_data base
  assert_output "/data/base"
}

@test "get_jail_host_etc - control files the host reads for the jail" {
  export ZFS_DATA_MNT="/data"
  run get_jail_host_etc dovecot
  assert_output "/data/etc/dovecot"
}

@test "warn_stale_jail_conf - silent when the mount line is current" {
  export ZFS_DATA_MNT="/data"
  local _conf="$BATS_TEST_TMPDIR/dovecot.conf"
  printf 'dovecot {\n\tmount.fstab = "/data/etc/dovecot/fstab";\n}\n' > "$_conf"

  run warn_stale_jail_conf dovecot "$_conf"
  assert_success
  assert_output ""
}

@test "warn_stale_jail_conf - warns when the mount line is outdated" {
  export ZFS_DATA_MNT="/data"
  local _conf="$BATS_TEST_TMPDIR/dovecot.conf"
  printf 'dovecot {\n\tmount.fstab = "/data/dovecot/host-etc/fstab";\n}\n' > "$_conf"

  run warn_stale_jail_conf dovecot "$_conf"
  assert_output --partial "out of date"
  assert_output --partial 'mount.fstab = "/data/etc/dovecot/fstab";'
}

@test "warn_stale_jail_conf - flags a base entry still declaring an fstab" {
  export ZFS_DATA_MNT="/data"
  local _conf="$BATS_TEST_TMPDIR/base.conf"
  printf 'base {\n\tmount.fstab = "/jails/base-14.4-RELEASE/data/etc/fstab";\n}\n' > "$_conf"

  run warn_stale_jail_conf base "$_conf"
  assert_output --partial "out of date"
  assert_output --partial "mount.devfs;"
}

@test "warn_stale_jail_conf - warns when the config is missing entirely" {
  export ZFS_DATA_MNT="/data"
  run warn_stale_jail_conf dovecot "$BATS_TEST_TMPDIR/absent.conf"
  assert_output --partial "out of date"
}

@test "add_jail_conf_d - resolves its own ip4.addr when called directly" {
  get_public_ip6() { export PUBLIC_IP6=""; }
  store_config() { cat -; }

  run add_jail_conf_d mysql
  assert_output --partial "ip4.addr = lo1|172.16.15.4;"
}

@test "add_jail_conf_d - asks store_config to update an unedited config" {
  get_public_ip6() { export PUBLIC_IP6=""; }
  store_config() { echo "operation=${2:-none}"; cat - > /dev/null; }

  run add_jail_conf_d mysql
  assert_output --partial "operation=update"
}

@test "add_jail_conf_d - base mounts devfs rather than an fstab" {
  get_public_ip6() { export PUBLIC_IP6=""; }
  store_config() { cat -; }

  run add_jail_conf_d base
  assert_success
  assert_output --partial "mount.devfs;"
  refute_output --partial "mount.fstab"
}

@test "add_jail_conf_d - base gets no host-run pf rules" {
  get_public_ip6() { export PUBLIC_IP6=""; }
  store_config() { cat -; }

  run add_jail_conf_d base
  assert_success
  refute_output --partial "pfrule.sh"
}

@test "add_jail_conf_d - a service jail keeps its fstab and pf rules" {
  export ZFS_DATA_MNT="/data"
  dec_to_hex() { if [ "$1" -eq 4 ]; then echo "4"; fi; }
  get_public_ip6() { export PUBLIC_IP6=""; }
  store_config() { cat -; }

  run add_jail_conf_d mysql
  assert_success
  assert_output --partial 'mount.fstab = "/data/etc/mysql/fstab";'
  assert_output --partial "pf.conf.d/pfrule.sh load"
  assert_output --partial "pf.conf.d/pfrule.sh unload"
}

@test "add_jail_conf - base mounts devfs rather than an fstab" {
  tee() { cat -; }
  grep() { return 1; }
  dec_to_hex() { echo "2"; }
  get_public_ip6() { export PUBLIC_IP6=""; }
  store_config() { cat -; }

  run add_jail_conf base
  assert_success
  assert_output --partial "mount.devfs;"
  refute_output --partial "mount.fstab"
}

# --- configure_mta_pf_rdr: port 25 follows TOASTER_MTA, 465/587 follow TOASTER_MSA ---

mta_rdr_setup() {
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  get_public_ip4() { export PUBLIC_IP4="203.0.113.7"; }
  get_public_ip6() { export PUBLIC_IP6="2001:db8::1"; }
  get_jail_ip()  { echo "172.16.15.9"; }
  get_jail_ip6() { echo "fd7a::9"; }
}

@test "configure_mta_pf_rdr - default: haraka claims 25 465 587" {
  mta_rdr_setup
  export TOASTER_MTA="haraka" TOASTER_MSA="haraka"
  configure_mta_pf_rdr haraka
  run cat "$(get_jail_host_etc haraka)/pf.conf.d/rdr.conf"
  assert_output --partial "port { 25 465 587 }"
}

@test "configure_mta_pf_rdr - MSA=postfix moves submission ports off haraka" {
  mta_rdr_setup
  export TOASTER_MTA="haraka" TOASTER_MSA="postfix"
  configure_mta_pf_rdr haraka
  configure_mta_pf_rdr postfix
  run cat "$(get_jail_host_etc haraka)/pf.conf.d/rdr.conf"
  assert_output --partial "port { 25 }"
  refute_output --partial "465"
  run cat "$(get_jail_host_etc postfix)/pf.conf.d/rdr.conf"
  assert_output --partial "port { 465 587 }"
  refute_output --partial "25"
}

@test "configure_mta_pf_rdr - MTA=postfix moves port 25 off haraka" {
  mta_rdr_setup
  export TOASTER_MTA="postfix" TOASTER_MSA="haraka"
  configure_mta_pf_rdr haraka
  configure_mta_pf_rdr postfix
  run cat "$(get_jail_host_etc haraka)/pf.conf.d/rdr.conf"
  assert_output --partial "port { 465 587 }"
  run cat "$(get_jail_host_etc postfix)/pf.conf.d/rdr.conf"
  assert_output --partial "port { 25 }"
}

@test "configure_mta_pf_rdr - removes stale rdr.conf when jail owns no ports" {
  mta_rdr_setup
  export TOASTER_MTA="postfix" TOASTER_MSA="postfix"
  mkdir -p "$(get_jail_host_etc haraka)/pf.conf.d"
  echo "stale rule" > "$(get_jail_host_etc haraka)/pf.conf.d/rdr.conf"
  run configure_mta_pf_rdr haraka
  assert_success
  [ ! -f "$(get_jail_host_etc haraka)/pf.conf.d/rdr.conf" ]
}

@test "configure_mta_pf_rdr - writes no file when jail owns no ports" {
  mta_rdr_setup
  export TOASTER_MTA="postfix" TOASTER_MSA="postfix"
  run configure_mta_pf_rdr haraka
  assert_success
  [ ! -f "$(get_jail_host_etc haraka)/pf.conf.d/rdr.conf" ]
}

@test "get_jail_data - returns predictable value" {
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  run get_jail_data dovecot
  assert_success
  assert_output "$ZFS_DATA_MNT/dovecot"
}

@test "get_jail_data - returns no special value for base" {
  run get_jail_data base
  assert_success
  assert_output "$ZFS_DATA_MNT/base"
}

@test "get_jail_host_etc - returns predictable value" {
  run get_jail_host_etc dovecot
  assert_success
  assert_output "$ZFS_DATA_MNT/etc/dovecot"
}

@test "migrate_jail_conf_etc - updates jail.conf" {
  sed_inplace() { sed -i.bak "$@"; }
  fatal_err() { echo "$@"; exit 1; }

  local _file; _file=$(mktemp)
  cat > "$_file" <<EO_JAIL_CONF
exec.start = "/bin/sh /etc/rc";
exec.stop = "/bin/sh /etc/rc.shutdown";

dovecot	{
		mount.fstab = "/data/dovecot/etc/fstab";
		exec.created += "/data/dovecot/etc/pf.conf.d/pfrule.sh load";
		exec.poststop += "/data/dovecot/etc/pf.conf.d/pfrule.sh unload";
		ip4.addr = lo1|172.16.15.72;
		ip6.addr = lo1|fd7a:e5cd:1fc1:a15e:dead:beef:cafe:0048;
	}
EO_JAIL_CONF
  run migrate_jail_conf_etc "dovecot" "$_file"
  assert_output --partial "Migrating /data/dovecot/etc to /data/etc/dovecot in $_file"
  refute_output --partial "Could not reliably migrate"
  assert_success
  run grep "/data/dovecot/etc" "$_file"
  assert_failure
  run grep "$(get_jail_host_etc dovecot)" "$_file"
  assert_success
}
