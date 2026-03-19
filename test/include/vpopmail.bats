
setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  # Mock variables
  export TOASTER_MYSQL="1"
  export TOASTER_MARIADB="0"
  export TOASTER_VPOPMAIL_EXT="1"
  export TOASTER_VPOPMAIL_CLEAR="1"
  export ZFS_DATA_MNT="/data"
  export ZFS_JAIL_MNT="/jails"
  export STAGE_MNT="/stage"

  # Source the file under test
  load '../../include/vpopmail.sh'
}

# Mock helper functions from mail-toaster.sh
tell_status() { :; }
stage_pkg_install() { :; }
stage_exec() { :; }
stage_make_conf() { :; }

@test "install_vpopmail_deps - mysql enabled" {
  export TOASTER_MYSQL="1"
  export TOASTER_MARIADB="0"

  # We want to check if stage_pkg_install is called with the right arguments
  stage_pkg_install() {
    echo "pkg install $*"
  }

  run install_vpopmail_deps
  assert_success
  assert_output --partial "pkg install gmake gettext ucspi-tcp netqmail fakeroot mysql80-client"
}

@test "install_vpopmail_deps - mariadb enabled" {
  export TOASTER_MYSQL="1"
  export TOASTER_MARIADB="1"

  stage_pkg_install() {
    echo "pkg install $*"
  }

  run install_vpopmail_deps
  assert_success
  assert_output --partial "pkg install gmake gettext ucspi-tcp netqmail fakeroot mariadb104-client"
}

@test "install_vpopmail_port - default options" {
  export TOASTER_MYSQL="1"
  export TOASTER_VPOPMAIL_EXT="1"
  export TOASTER_VPOPMAIL_CLEAR="1"

  # Mock stage_make_conf to capture arguments
  stage_make_conf() {
    echo "make_conf $1 $2"
  }
  # Mock other commands to avoid failure
  grep() {
    if [[ "$*" == *"/usr/ports/mail/vpopmail/Makefile" ]]; then return 0; fi # assume already patched
    return 1;
  }
  tee() { :; }
  stage_pkg_install() { :; }
  stage_exec() { :; }

  run install_vpopmail_port
  assert_success
  assert_output --partial "make_conf mail_vpopmail_"
  assert_output --partial "mail_vpopmail_SET= MYSQL VALIAS QMAIL_EXT CLEAR_PASSWD"
  assert_output --partial "mail_vpopmail_UNSET= CDB"
}

@test "install_qmail - basic" {
  export TOASTER_HOSTNAME="mail.example.com"
  
  stage_pkg_install() {
    echo "pkg install $*"
  }
  stage_exec() {
    echo "exec $*"
  }
  stage_make_conf() {
    echo "make_conf $1 $2"
  }
  
  # Mocking directory operations and file checks
  mkdir() { :; }
  rm() { :; }
  grep() { return 1; }
  
  run install_qmail
  assert_success
  assert_output --partial "pkg install netqmail daemontools ucspi-tcp"
  assert_output --partial "exec ln -s /usr/local/vpopmail/qmail-control /var/qmail/control"
  assert_output --partial "make_conf mail_qmail_"
}
