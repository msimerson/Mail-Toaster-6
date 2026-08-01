
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
  assert_output --regexp "pkg install gmake gettext ucspi-tcp netqmail fakeroot mysql[0-9]+-client"
}

@test "install_vpopmail_deps - mariadb enabled" {
  export TOASTER_MYSQL="1"
  export TOASTER_MARIADB="1"

  stage_pkg_install() {
    echo "pkg install $*"
  }

  run install_vpopmail_deps
  assert_success
  assert_output --regexp "pkg install gmake gettext ucspi-tcp netqmail fakeroot mariadb[0-9]+-client"
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

@test "install_vpopmail_source" {
  export TOASTER_MYSQL="1"
  export TOASTER_VPOPMAIL_EXT="1"
  export TOASTER_VPOPMAIL_CLEAR="1"

  stage_pkg_install() { echo "pkg install $*"; }
  stage_exec() { echo "exec $*"; }

  # Mock git and directory operations
  git() { echo "git $*"; }
  mkdir() { :; }

  run install_vpopmail_source
  assert_success
  assert_output --partial "pkg install automake"
  assert_output --partial "git clone https://github.com/brunonymous/vpopmail.git"
  assert_output --partial "exec sh -c cd /data/src/vpopmail; CFLAGS=\"-fcommon\" ./configure --disable-users-big-dir --enable-logging=y --enable-md5-passwords --disable-sha512-passwords --enable-auth-module=mysql --enable-valias --enable-sql-aliasdomains --enable-qmail-ext --enable-clear-passwd"
}
