#!/usr/bin/env bats
# Functional tests for provision/vpopmail.sh

setup() {
  load helper
  provision_fns vpopmail tell_settings
}

# its nginx logs live on /data, which outlives every rebuild
@test "vpopmail - its nginx logs are rotated" {
  install_nginx_newsyslog() { echo "NGINX_NEWSYSLOG"; }
  run install_nginx_vpopmail
  assert_success
  assert_output --partial "NGINX_NEWSYSLOG"
}
