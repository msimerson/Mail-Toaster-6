#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include nginx

configure_nginx_server()
{
  _NGINX_SERVER='
	server_name  bsd_cache;

	location / {
		root          /data/cache/pkg;
		try_files     $uri @cache;
	}

	location @cache {
		root          /data/cache/pkg;
		proxy_store             on;
		proxy_pass              https://pkg.freebsd.org;
		proxy_cache_lock        on;
		proxy_cache_lock_timeout        20s;
		proxy_cache_revalidate  on;
		proxy_cache_valid       200 301 302 24h;
		proxy_cache_valid       404 10m;
	}
'
	export _NGINX_SERVER
	configure_nginx_server_d bsd_cache

  _NGINX_SERVER='
	server_name  freebsd-update;

	location / {
		root          /data/cache/freebsd-update;
		try_files     $uri @cache;
	}

	location @cache {
		root          /data/cache/freebsd-update;
		proxy_store             on;
		proxy_pass              https://update.freebsd.org;
		proxy_http_version      1.1;
		proxy_cache_lock        on;
		proxy_cache_lock_timeout        20s;
		proxy_cache_revalidate  on;
		proxy_cache_valid       200 301 302 24h;
		proxy_cache_valid       404 10m;
	}
'
	export _NGINX_SERVER
	configure_nginx_server_d update
}

install_bsd_cache()
{
	install_nginx || exit
}

configure_bsd_cache()
{
	configure_nginx bsd_cache
	configure_nginx_server
}

start_bsd_cache()
{
	start_nginx
}

test_bsd_cache()
{
	tell_status "testing bsd_cache httpd"
	stage_listening 80
}

base_snapshot_exists || exit
create_staged_fs bsd_cache
start_staged_jail bsd_cache
install_bsd_cache
configure_bsd_cache
start_bsd_cache
test_bsd_cache
promote_staged_jail bsd_cache
