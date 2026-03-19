
setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  # Mock variables
  export TOASTER_EDITOR="vim"
  export STAGE_MNT="/stage"

  # Source the file under test
  load '../../include/shell.sh'
}

# Mock helper functions from mail-toaster.sh
tell_status() { :; }
stage_pkg_install() { :; }
stage_exec() { :; }

@test "install_bash - basic" {
  stage_pkg_install() { echo "pkg install $*"; }
  stage_exec() { echo "exec $*"; }
  configure_bash() { echo "configure_bash $*"; }
  
  # Mock file checks
  test() {
    if [[ "$2" == *"/usr/local/etc/profile" ]]; then return 1; fi
    if [[ "$2" == *"/root/.bash_profile" ]]; then return 1; fi
    # fall back to real test for other things
    command test "$@"
  }

  run install_bash "/stage"
  assert_success
  assert_output --partial "pkg install bash"
  assert_output --partial "exec chpass -s /usr/local/bin/bash"
  assert_output --partial "configure_bash /stage"
}

@test "configure_bourne_shell - basic" {
  # Mock grep to not find PS1
  grep() { return 1; }
  
  # Mock cat to avoid writing to real files
  # In bats, we can use a temporary directory
  local _tmp=$(mktemp -d)
  mkdir -p "$_tmp/etc/profile.d"
  mkdir -p "$_tmp/root"
  touch "$_tmp/root/.profile"
  
  run configure_bourne_shell "$_tmp"
  assert_success
  
  # Check if the file was created with correct content
  [ -f "$_tmp/etc/profile.d/toaster.sh" ]
  run cat "$_tmp/etc/profile.d/toaster.sh"
  assert_output --partial "export EDITOR=\"vim\""
  assert_output --partial "PS1="
  
  rm -rf "$_tmp"
}
