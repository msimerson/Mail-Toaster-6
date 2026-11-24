#!/usr/bin/env bats
# Functional tests for provision/php.sh

setup() {
  load helper

  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  export ZFS_DATA_MNT="$BATS_TEST_TMPDIR/data"
  export JAIL_NET_START=1

  mkdir -p "$STAGE_MNT/usr/local/etc" "$ZFS_DATA_MNT/php"
  printf 'include=/usr/local/etc/php-fpm.d/*.conf\n' > "$STAGE_MNT/usr/local/etc/php-fpm.conf"

  provision_fns php
}

# --- the jail list ---

@test "php replaces php7 in place, so the jail addresses do not move" {
  # shellcheck disable=SC2086
  set -- $JAIL_ORDERED_LIST
  local _list=" $* "
  [[ "$_list" == *" joomla php memcached "* ]]
  [[ "$_list" != *" php7 "* ]]
  [[ "$_list" != *" sites "* ]]
}

@test "php has the address php7 had, and its neighbours keep theirs" {
  run get_jail_ip4 php
  assert_output "172.16.15.24"
  run get_jail_ip4 joomla
  assert_output "172.16.15.23"
  run get_jail_ip4 memcached
  assert_output "172.16.15.25"
  run get_jail_ip4 tachyon
  assert_output "172.16.15.71"
}

@test "the jail addresses before php do not move" {
  run get_jail_ip4 syslog
  assert_output "172.16.15.1"
  run get_jail_ip4 mysql
  assert_output "172.16.15.4"
}

# --- install ---

@test "install_php_jail installs PHP 8.5 with the requested modules" {
  install_php() { echo "PHP:$1:$2"; }
  install_nginx() { echo "NGINX"; }

  run install_php_jail
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

@test "install_php_jail asks for the xmlrpc extension port, not a pecl one" {
  install_php() { echo "PHP:$1:$2"; }
  install_nginx() { :; }

  run install_php_jail
  assert_output --regexp "PHP:85:.* xmlrpc( |$)"
  refute_output --partial "pecl-xmlrpc"
}

# --- state lives in /data ---

@test "configure_php_jail_dirs creates the vhost, pool, docroot and log dirs in /data" {
  configure_php_jail_dirs

  [ -d "$ZFS_DATA_MNT/php/etc/nginx/server.d" ]
  [ -d "$ZFS_DATA_MNT/php/etc/php-fpm.d" ]
  [ -d "$ZFS_DATA_MNT/php/www" ]
  [ -d "$ZFS_DATA_MNT/php/log" ]
}

@test "configure_php_jail_dirs keeps what a site left there" {
  mkdir -p "$ZFS_DATA_MNT/php/www/example.org"
  echo hi > "$ZFS_DATA_MNT/php/www/example.org/index.html"

  configure_php_jail_dirs

  run cat "$ZFS_DATA_MNT/php/www/example.org/index.html"
  assert_output "hi"
}

@test "configure_php_jail_pools loads the pools in /data/etc/php-fpm.d" {
  configure_php_jail_pools

  run grep -c '^include=/data/etc/php-fpm.d/\*.conf$' "$STAGE_MNT/usr/local/etc/php-fpm.conf"
  assert_output "1"
  # the stock pools still load
  run grep -c '^include=/usr/local/etc/php-fpm.d/' "$STAGE_MNT/usr/local/etc/php-fpm.conf"
  assert_output "1"
}

@test "configure_php_jail_pools adds the include only once" {
  configure_php_jail_pools
  configure_php_jail_pools

  run grep -c '^include=/data/etc/php-fpm.d/' "$STAGE_MNT/usr/local/etc/php-fpm.conf"
  assert_output "1"
}

# --- nginx ---

@test "the shared fastcgi include sets HTTPS from X-Forwarded-Proto" {
  configure_php_jail_fastcgi

  local _etc="$ZFS_DATA_MNT/php/etc/nginx"
  run cat "$_etc/server.d/00-fastcgi-https.conf"
  assert_output --partial 'map $http_x_forwarded_proto $fastcgi_https'
  assert_output --regexp 'https[[:space:]]+on;'

  run cat "$_etc/fastcgi_site.conf"
  assert_output --partial 'fastcgi_param  HTTPS            $fastcgi_https if_not_empty;'
  assert_output --partial 'include        /usr/local/etc/nginx/fastcgi_params;'
  assert_output --partial 'SCRIPT_FILENAME'
}

@test "the fastcgi map sits in server.d, which nginx includes in http context" {
  configure_php_jail_fastcgi

  [ -f "$ZFS_DATA_MNT/php/etc/nginx/server.d/00-fastcgi-https.conf" ]
  # the include itself is not a server.d/*.conf, it is used inside a location
  [ ! -e "$ZFS_DATA_MNT/php/etc/nginx/server.d/fastcgi_site.conf" ]
}

@test "the default server listens on port 80 only and answers 404" {
  configure_nginx_server_d() { echo "JAIL:$1 NAME:$2"; echo "$_NGINX_SERVER"; }

  run configure_nginx_default_server
  assert_success
  assert_output --partial "JAIL:php NAME:00-default"
  assert_output --partial "listen       80 default_server;"
  assert_output --partial "return       404;"
  refute_output --partial "443"
  refute_output --partial "ssl"
}

@test "the samples are not loaded: neither ends in .conf" {
  configure_php_jail_samples

  [ -f "$ZFS_DATA_MNT/php/etc/nginx/example.conf.sample" ]
  [ -f "$ZFS_DATA_MNT/php/etc/php-fpm.d/example.conf.sample" ]
  run grep -c 'fastcgi_site.conf' "$ZFS_DATA_MNT/php/etc/nginx/example.conf.sample"
  assert_output "1"
}

# --- logs: one pair per site ---

@test "the sample vhost logs to files of its own in /data/log" {
  configure_php_jail_samples

  run cat "$ZFS_DATA_MNT/php/etc/nginx/example.conf.sample"
  assert_output --partial "access_log  /data/log/example.org.access.log;"
  assert_output --partial "error_log   /data/log/example.org.error.log;"
}

@test "newsyslog rotates the per-site logs, as patterns" {
  mkdir -p "$STAGE_MNT/etc/newsyslog.conf.d"
  configure_php_jail_logs

  run cat "$STAGE_MNT/etc/newsyslog.conf.d/php-sites.conf"
  assert_success
  assert_output --regexp '/data/log/\*\.access\.log[[:space:]]+root:wheel[[:space:]]+644[[:space:]]+7[[:space:]]+\*[[:space:]]+@T00[[:space:]]+BCGX[[:space:]]+/var/run/nginx\.pid[[:space:]]+30'
  assert_output --regexp '/data/log/\*\.error\.log[[:space:]]+root:wheel[[:space:]]+644[[:space:]]+7[[:space:]]+\*[[:space:]]+@T00[[:space:]]+BCGX'
}

@test "the sample pool logs to files of its own in /data/log" {
  configure_php_jail_samples

  run cat "$ZFS_DATA_MNT/php/etc/php-fpm.d/example.conf.sample"
  assert_output --partial "access.log = /data/log/example.org.fpm-access.log"
  assert_output --partial "slowlog = /data/log/example.org.fpm-slow.log"
  assert_output --partial "php_admin_value[error_log] = /data/log/example.org.php-error.log"
}

@test "newsyslog rotates the PHP-FPM logs by the php-fpm pid" {
  mkdir -p "$STAGE_MNT/etc/newsyslog.conf.d"
  configure_php_jail_logs

  run cat "$STAGE_MNT/etc/newsyslog.conf.d/php-sites.conf"
  assert_output --regexp '/data/log/\*\.fpm-access\.log[[:space:]]+root:wheel[[:space:]]+644[[:space:]]+7[[:space:]]+\*[[:space:]]+@T00[[:space:]]+BCGX[[:space:]]+/var/run/php-fpm\.pid[[:space:]]+30'
  assert_output --regexp '/data/log/\*\.fpm-slow\.log[[:space:]].*/var/run/php-fpm\.pid'
}

# newsyslog recreates a rotated file as the owner its line names: a pattern
# would hand every site's PHP error log to one user, locking out a pool that
# runs as another
@test "no pattern owns the PHP error logs, each site has a line of its own" {
  mkdir -p "$STAGE_MNT/etc/newsyslog.conf.d"
  configure_php_jail_logs

  run cat "$STAGE_MNT/etc/newsyslog.conf.d/php-sites.conf"
  refute_output --partial "php-error"
  assert_output --partial "<include> /data/etc/newsyslog.conf.d/*.conf"
}

@test "the newsyslog sample names the pool's uid:gid and no pattern flag" {
  mkdir -p "$STAGE_MNT/etc/newsyslog.conf.d"
  configure_php_jail_logs

  run cat "$ZFS_DATA_MNT/php/etc/newsyslog.conf.d/example.conf.sample"
  assert_output --regexp '/data/log/example\.org\.php-error\.log[[:space:]]+80:80[[:space:]]+644[[:space:]]+7[[:space:]]+\*[[:space:]]+@T00[[:space:]]+BCX[[:space:]]+/var/run/php-fpm\.pid[[:space:]]+30'
  refute_output --regexp 'BCGX'
}

@test "configure_php_jail_dirs creates the dir the newsyslog include reads" {
  configure_php_jail_dirs
  [ -d "$ZFS_DATA_MNT/php/etc/newsyslog.conf.d" ]
}

# a pattern that caught another daemon's file would signal the wrong pid
@test "no log pattern matches another kind of site log" {
  local _site="example.org" _p _f _pat _file
  local _patterns="*.access.log:nginx *.error.log:nginx *.fpm-access.log:fpm *.fpm-slow.log:fpm"
  local _files="$_site.access.log:nginx $_site.error.log:nginx $_site.fpm-access.log:fpm $_site.fpm-slow.log:fpm $_site.php-error.log:none access_log:none error_log:none php-fpm.log:none"

  for _p in $_patterns; do
    _pat=${_p%%:*}
    for _f in $_files; do
      _file=${_f%%:*}
      # shellcheck disable=SC2254
      case "$_file" in
        $_pat) [ "${_f##*:}" = "${_p##*:}" ] || { echo "$_pat matches $_file"; return 1; } ;;
      esac
    done
  done
}

@test "configure_php_jail configures php and nginx for the php jail and writes the shared include" {
  configure_php() { echo "configure_php:$1"; }
  configure_nginx() { echo "configure_nginx:$1"; }
  configure_nginx_server_d() { :; }

  run configure_php_jail
  assert_success
  assert_output --partial "configure_php:php"
  assert_output --partial "configure_nginx:php"
  [ -f "$ZFS_DATA_MNT/php/etc/nginx/fastcgi_site.conf" ]
}

# --- scope ---

@test "php.sh leaves TLS, databases and other jails alone" {
  run grep -n "443\|ssl\|haproxy\|assure_jail\|mysql_create\|pf" "$PROVISION_DIR/php.sh"
  # only the comments that say haproxy handles TLS
  refute_output --regexp "assure_jail|mysql_create|443|listen[^;]*ssl"
}

# --- test_php_jail ---

@test "test_php_jail checks the nginx and PHP-FPM configuration" {
  stage_exec() { echo "EXEC:$*"; }

  run test_php_jail
  assert_success
  assert_output --partial "EXEC:nginx -t -c /data/etc/nginx/nginx.conf"
  assert_output --partial "EXEC:php-fpm -t"
  assert_output --partial "it worked"
}

@test "test_php_jail fails when the nginx config is invalid" {
  stage_exec() { case "$*" in "nginx -t"*) return 1 ;; esac; }

  run test_php_jail
  assert_failure
  refute_output --partial "it worked"
}

# --- the documentation ---

@test "docs/php-sites.md covers adding a site, with the paths the provisioner creates" {
  local _doc="$BATS_TEST_DIRNAME/../../docs/php-sites.md"
  [ -f "$_doc" ]

  run cat "$_doc"
  assert_output --partial "www.example.com"
  assert_output --partial "/data/php/etc/nginx/server.d/"
  assert_output --partial "/data/php/etc/php-fpm.d/"
  assert_output --partial "/data/php/www/"
  assert_output --partial "fastcgi_site.conf"
  assert_output --partial "use_backend"
  assert_output --partial "php-fpm -t"
  assert_output --partial "nginx -t -c /data/etc/nginx/nginx.conf"
}

@test "the documented site config uses the log names that newsyslog rotates" {
  local _doc="$BATS_TEST_DIRNAME/../../docs/php-sites.md"
  run cat "$_doc"
  assert_output --partial "/data/log/www.example.com.access.log"
  assert_output --partial "/data/log/www.example.com.error.log"
  assert_output --partial "/data/log/www.example.com.fpm-access.log"
  assert_output --partial "/data/log/www.example.com.fpm-slow.log"
  assert_output --partial "/data/log/www.example.com.php-error.log"
}

@test "the guide gives the PHP error log to the pool's user and a newsyslog line of its own" {
  local _doc="$BATS_TEST_DIRNAME/../../docs/php-sites.md"
  run cat "$_doc"
  assert_output --partial "chown 80:80 /data/php/log/www.example.com.php-error.log"
  assert_output --partial "/data/php/etc/newsyslog.conf.d/www.example.com.conf"
  assert_output --regexp '/data/log/www\.example\.com\.php-error\.log[[:space:]]+80:80'
  assert_output --partial "1029"
}
