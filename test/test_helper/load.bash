# bats-support and bats-assert in one load.
#
# Their own load.bash resolves each src file with $(dirname ...). Bats traps
# DEBUG, which makes every subshell costly, and 15 of them per test is most of
# a test's runtime. Parameter expansion resolves the same paths for free.

_BATS_TEST_HELPER="${BASH_SOURCE[0]%/*}"

# BATS_SAVED_PATH pins the PATH bats-support saw, so a test's own stubs cannot
# redirect the utilities the assertions run
BATS_SAVED_PATH="${BATS_SAVED_PATH-$PATH}"

source "$_BATS_TEST_HELPER/bats-support/src/output.bash"
source "$_BATS_TEST_HELPER/bats-support/src/error.bash"
source "$_BATS_TEST_HELPER/bats-support/src/lang.bash"

source "$_BATS_TEST_HELPER/bats-assert/src/assert.bash"
source "$_BATS_TEST_HELPER/bats-assert/src/refute.bash"
source "$_BATS_TEST_HELPER/bats-assert/src/assert_equal.bash"
source "$_BATS_TEST_HELPER/bats-assert/src/assert_not_equal.bash"
source "$_BATS_TEST_HELPER/bats-assert/src/assert_success.bash"
source "$_BATS_TEST_HELPER/bats-assert/src/assert_failure.bash"
source "$_BATS_TEST_HELPER/bats-assert/src/assert_output.bash"
source "$_BATS_TEST_HELPER/bats-assert/src/refute_output.bash"
source "$_BATS_TEST_HELPER/bats-assert/src/assert_line.bash"
source "$_BATS_TEST_HELPER/bats-assert/src/refute_line.bash"
source "$_BATS_TEST_HELPER/bats-assert/src/assert_regex.bash"
source "$_BATS_TEST_HELPER/bats-assert/src/refute_regex.bash"

unset _BATS_TEST_HELPER
