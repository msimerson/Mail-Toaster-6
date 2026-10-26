# Shared setup for the provision/*.sh tests: load it in setup_file and setup.
#
# A provision script sources mail-toaster.sh by PATH, so stubs/ goes first.
# It runs its execution block at source time, so most tests source only the
# function definitions above that block.

load '../test_helper/load'

export MT6_TEST_ENV=1
case ":$PATH:" in
  *":$BATS_TEST_DIRNAME/stubs:"*) ;;
  *) export PATH="$BATS_TEST_DIRNAME/stubs:$PATH" ;;
esac

PROVISION_DIR="$BATS_TEST_DIRNAME/../../provision"

# $2 is the first top-level command of the execution block, matched as a whole
# word so `preinstall_checks` stops at the call, not at `preinstall_checks()`
provision_fns() {
  local _fns="$BATS_FILE_TMPDIR/$1_fns_only.sh"
  if [ ! -f "$_fns" ]; then
    awk -v end="${2:-base_snapshot_exists}" \
      '$0 == end || index($0, end " ") == 1 { exit } { print }' \
      "$PROVISION_DIR/$1.sh" > "$_fns"
  fi
  # shellcheck source=/dev/null
  . "$_fns"
}

# the whole script, execution block included, run against the stubs
provision_run() {
  # shellcheck source=/dev/null
  . "$PROVISION_DIR/$1.sh"
}
