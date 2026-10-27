#!/usr/bin/env bats
# Functional tests for provision/nagios.sh

setup() {
  load helper
  provision_fns nagios
}

# nagios4 pulls in PHP as a dependency, so install_php never runs to add this
@test "nagios - its php-fpm log is rotated" {
  install_php_newsyslog() { echo "PHP_NEWSYSLOG"; }
  run install_nagios
  assert_success
  assert_output --partial "PHP_NEWSYSLOG"
}
