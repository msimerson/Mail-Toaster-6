
setup() {
  load '../test_helper/load'

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

  vpopmail_port_fixups() { :; }
  run install_vpopmail_port
  assert_success
  assert_output --partial "make_conf mail_vpopmail_"
  assert_output --partial "mail_vpopmail_SET= MYSQL VALIAS QMAIL_EXT CLEAR_PASSWD"
  assert_output --partial "mail_vpopmail_UNSET= CDB"
}

# Uses/mysql.mk misses a MariaDB client and builds against MySQL instead
@test "install_vpopmail_port - mariadb names the mysql version for the port" {
  export TOASTER_MYSQL="1"
  export TOASTER_MARIADB="1"
  stage_make_conf() { echo "make_conf $1 $2"; }
  grep() {
    if [[ "$*" == *"/usr/ports/mail/vpopmail/Makefile" ]]; then return 0; fi
    return 1;
  }
  tee() { :; }
  stage_pkg_install() { :; }
  stage_exec() { :; }

  vpopmail_port_fixups() { :; }
  run install_vpopmail_port
  assert_success
  assert_output --partial "make_conf DEFAULT_VERSIONS+=mysql=12.3m DEFAULT_VERSIONS+=mysql=12.3m"
}

@test "install_vpopmail_port - mysql keeps the ports default version" {
  export TOASTER_MYSQL="1"
  export TOASTER_MARIADB="0"
  stage_make_conf() { echo "make_conf $1 $2"; }
  grep() {
    if [[ "$*" == *"/usr/ports/mail/vpopmail/Makefile" ]]; then return 0; fi
    return 1;
  }
  tee() { :; }
  stage_pkg_install() { :; }
  stage_exec() { :; }

  vpopmail_port_fixups() { :; }
  run install_vpopmail_port
  assert_success
  refute_output --partial "DEFAULT_VERSIONS"
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

# --- vpopmail_port_fixups: dir_control counter underflow ---

# bigdir.c:53 of vpopmail 5.4.33 decrements an unsigned long that is then
# written with %lu into an INT column
_port_work_dir() {
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  _work="$STAGE_MNT/tmp/portbuild/usr/ports/mail/vpopmail/work/vpopmail-5.4.33"
  mkdir -p "$_work"
  : > "$_work/vmysql.h"
  printf 'int dec_dir_control(void)\n{\n\topen_big_dir();\n\t--vdir.cur_users;\n\tclose_big_dir();\n\treturn(0);\n}\n' \
    > "$_work/bigdir.c"

  sed_inplace() {
    case "$(uname)" in
      Linux*) sed -i "$@" ;;
      *)      sed -i '' "$@" ;;
    esac
  }
}

@test "vpopmail_port_fixups - guards the dir_control decrement" {
  _port_work_dir
  run vpopmail_port_fixups
  assert_success
  run cat "$_work/bigdir.c"
  assert_output --partial "if (vdir.cur_users > 0) --vdir.cur_users;"
  assert_output --partial "open_big_dir();"
  assert_output --partial "close_big_dir();"
}

@test "vpopmail_port_fixups - guards the decrement once when run twice" {
  _port_work_dir
  vpopmail_port_fixups
  vpopmail_port_fixups
  run grep -c "cur_users" "$_work/bigdir.c"
  assert_output "1"
}

@test "vpopmail_port_fixups - fails when the decrement is not found" {
  _port_work_dir
  printf 'int dec_dir_control(void)\n{\n\treturn(0);\n}\n' > "$_work/bigdir.c"
  run vpopmail_port_fixups
  assert_failure
  assert_output --partial "bigdir.c dir_control fixup did not apply"
}

# the point of the guard: 0 stays 0 instead of wrapping to 2^64-1
@test "vpopmail_port_fixups - a counter at 0 stays at 0" {
  command -v cc >/dev/null || skip "no C compiler"
  _port_work_dir
  vpopmail_port_fixups

  {
    printf '#include <stdio.h>\n'
    printf 'typedef struct { long unsigned cur_users; } vdir_type;\n'
    printf 'vdir_type vdir;\n'
    printf 'void open_big_dir(void) {}\nvoid close_big_dir(void) {}\n'
    printf '#include "bigdir.c"\n'
    printf 'int main(void) {\n'
    printf '  vdir.cur_users = 0; dec_dir_control(); printf("%%lu\\n", vdir.cur_users);\n'
    printf '  vdir.cur_users = 5; dec_dir_control(); printf("%%lu\\n", vdir.cur_users);\n'
    printf '  return 0;\n}\n'
  } > "$_work/harness.c"

  run cc -I"$_work" -o "$_work/harness" "$_work/harness.c"
  assert_success
  run "$_work/harness"
  assert_success
  assert_line --index 0 "0"
  assert_line --index 1 "4"
}
