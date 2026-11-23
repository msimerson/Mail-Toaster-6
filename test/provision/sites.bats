#!/usr/bin/env bats
# Functional tests for provision/sites.sh

setup() {
  load helper

  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  export JAIL_NET_START=1

  mkdir -p "$STAGE_MNT/usr/local/etc" "$ZFS_DATA_MNT/sites"
  printf 'include=/usr/local/etc/php-fpm.d/*.conf\n' > "$STAGE_MNT/usr/local/etc/php-fpm.conf"

  provision_fns sites
}

# --- the jail list ---

@test "sites is the last jail, after tachyon" {
  # shellcheck disable=SC2086
  set -- $JAIL_ORDERED_LIST
  [ "${*: -2:1}" = "tachyon" ]
  [ "${*: -1}" = "sites" ]
}

@test "sites gets the next address after tachyon" {
  run get_jail_ip4 sites
  assert_output "172.16.15.72"
  run get_jail_ip4 tachyon
  assert_output "172.16.15.71"
}

@test "the jail addresses before sites do not move" {
  run get_jail_ip4 syslog
  assert_output "172.16.15.1"
  run get_jail_ip4 mysql
  assert_output "172.16.15.4"
  run get_jail_ip4 git
  assert_output "172.16.15.70"
}

# --- install ---

@test "install_sites installs PHP 8.5 with the requested modules" {
  install_php() { echo "PHP:$1:$2"; }
  install_nginx() { echo "NGINX"; }

  run install_sites
  assert_success
  assert_output --partial "NGINX"
  assert_output --partial "PHP:85:"

  local _m
  for _m in bcmath bz2 composer ctype curl dom exif fileinfo filter ftp gd gettext \
      iconv intl mbstring mysqli pdo pdo_mysql pdo_sqlite pecl-APCu phar posix \
      session simplexml soap sockets sqlite3 sysvmsg sysvsem tidy tokenizer xml \
      xmlreader xmlwriter xsl zip zlib; do
    assert_output --regexp "PHP:85:.* $_m( |$)|PHP:85:$_m( |$)"
  done
}

@test "install_sites asks for the xmlrpc extension port, not a pecl one" {
  install_php() { echo "PHP:$1:$2"; }
  install_nginx() { :; }

  run install_sites
  assert_output --regexp "PHP:85:.* xmlrpc( |$)"
  refute_output --partial "pecl-xmlrpc"
}

# --- state lives in /data ---

@test "configure_sites_dirs creates the vhost, pool, docroot and log dirs in /data" {
  configure_sites_dirs

  [ -d "$ZFS_DATA_MNT/sites/etc/nginx/server.d" ]
  [ -d "$ZFS_DATA_MNT/sites/etc/php-fpm.d" ]
  [ -d "$ZFS_DATA_MNT/sites/www" ]
  [ -d "$ZFS_DATA_MNT/sites/log" ]
}

@test "configure_sites_dirs keeps what a site left there" {
  mkdir -p "$ZFS_DATA_MNT/sites/www/example.org"
  echo hi > "$ZFS_DATA_MNT/sites/www/example.org/index.html"

  configure_sites_dirs

  run cat "$ZFS_DATA_MNT/sites/www/example.org/index.html"
  assert_output "hi"
}

@test "configure_sites_php_fpm loads the pools in /data/etc/php-fpm.d" {
  configure_sites_php_fpm

  run grep -c '^include=/data/etc/php-fpm.d/\*.conf$' "$STAGE_MNT/usr/local/etc/php-fpm.conf"
  assert_output "1"
  # the stock pools still load
  run grep -c '^include=/usr/local/etc/php-fpm.d/' "$STAGE_MNT/usr/local/etc/php-fpm.conf"
  assert_output "1"
}

@test "configure_sites_php_fpm adds the include only once" {
  configure_sites_php_fpm
  configure_sites_php_fpm

  run grep -c '^include=/data/etc/php-fpm.d/' "$STAGE_MNT/usr/local/etc/php-fpm.conf"
  assert_output "1"
}

# --- nginx ---

@test "the shared fastcgi include sets HTTPS from X-Forwarded-Proto" {
  configure_sites_fastcgi

  local _etc="$ZFS_DATA_MNT/sites/etc/nginx"
  run cat "$_etc/server.d/00-fastcgi-https.conf"
  assert_output --partial 'map $http_x_forwarded_proto $fastcgi_https'
  assert_output --regexp 'https[[:space:]]+on;'

  run cat "$_etc/fastcgi_site.conf"
  assert_output --partial 'fastcgi_param  HTTPS            $fastcgi_https if_not_empty;'
  assert_output --partial 'include        /usr/local/etc/nginx/fastcgi_params;'
  assert_output --partial 'SCRIPT_FILENAME'
}

@test "the fastcgi map sits in server.d, which nginx includes in http context" {
  configure_sites_fastcgi

  [ -f "$ZFS_DATA_MNT/sites/etc/nginx/server.d/00-fastcgi-https.conf" ]
  # the include itself is not a server.d/*.conf, it is used inside a location
  [ ! -e "$ZFS_DATA_MNT/sites/etc/nginx/server.d/fastcgi_site.conf" ]
}

@test "the default server listens on port 80 only and answers 404" {
  configure_nginx_server_d() { echo "JAIL:$1 NAME:$2"; echo "$_NGINX_SERVER"; }

  run configure_nginx_default_server
  assert_success
  assert_output --partial "JAIL:sites NAME:00-default"
  assert_output --partial "listen       80 default_server;"
  assert_output --partial "return       404;"
  refute_output --partial "443"
  refute_output --partial "ssl"
}

@test "the samples are not loaded: neither ends in .conf" {
  configure_sites_samples

  [ -f "$ZFS_DATA_MNT/sites/etc/nginx/example.conf.sample" ]
  [ -f "$ZFS_DATA_MNT/sites/etc/php-fpm.d/example.conf.sample" ]
  run grep -c 'fastcgi_site.conf' "$ZFS_DATA_MNT/sites/etc/nginx/example.conf.sample"
  assert_output "1"
}

@test "configure_sites configures php and nginx for the sites jail and writes the shared include" {
  configure_php() { echo "configure_php:$1"; }
  configure_nginx() { echo "configure_nginx:$1"; }
  configure_nginx_server_d() { :; }

  run configure_sites
  assert_success
  assert_output --partial "configure_php:sites"
  assert_output --partial "configure_nginx:sites"
  [ -f "$ZFS_DATA_MNT/sites/etc/nginx/fastcgi_site.conf" ]
}

# --- scope ---

@test "sites.sh leaves TLS, databases and other jails alone" {
  run grep -n "443\|ssl\|haproxy\|assure_jail\|mysql_create\|pf" "$PROVISION_DIR/sites.sh"
  # only the comments that say haproxy handles TLS
  refute_output --regexp "assure_jail|mysql_create|443|listen[^;]*ssl"
}

# --- test_sites ---

@test "test_sites checks the nginx and PHP-FPM configuration" {
  stage_exec() { echo "EXEC:$*"; }

  run test_sites
  assert_success
  assert_output --partial "EXEC:nginx -t -c /data/etc/nginx/nginx.conf"
  assert_output --partial "EXEC:php-fpm -t"
  assert_output --partial "it worked"
}

@test "test_sites fails when the nginx config is invalid" {
  stage_exec() { case "$*" in "nginx -t"*) return 1 ;; esac; }

  run test_sites
  assert_failure
  refute_output --partial "it worked"
}
