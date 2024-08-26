#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

mt6-include nginx

configure_nginx_server()
{
	_NGINX_SERVER='
	server {
		listen       80;
		listen  [::]:80;

		server_name  pkg;

		location / {
			root          /data/cache/pkg;
			try_files     $uri @pkg_cache;
		}

		location @pkg_cache {
			root                     /data/cache/pkg;
			proxy_store              on;
			proxy_pass               http://pkg.freebsd.org;
			proxy_cache_lock         on;
			proxy_cache_lock_timeout 20s;
			proxy_cache_revalidate   on;
			proxy_cache_valid        200 301 302 12h;
			proxy_cache_valid        404 5m;
		}
	}
'
	export _NGINX_SERVER
	configure_nginx_server_d bsd_cache pkg

	_NGINX_SERVER='
	server {
		listen       80;
		listen  [::]:80;

		server_name  freebsd-update;

		location / {
			root          /data/cache/freebsd-update;
			try_files     $uri @update_cache;
		}

		location @update_cache {
			root                     /data/cache/freebsd-update;
			proxy_store              on;
			proxy_pass               http://update.freebsd.org;
			proxy_http_version       1.1;
			proxy_cache_lock         on;
			proxy_cache_lock_timeout 20s;
			proxy_cache_revalidate   on;
			proxy_cache_valid        200 301 302 12h;
			proxy_cache_valid        404 5m;
		}
	}
'
	export _NGINX_SERVER
	configure_nginx_server_d bsd_cache update

	_NGINX_SERVER='
	server {
		listen       80;
		listen  [::]:80;

		server_name  vulnxml;

		location / {
			root          /data/cache/vulnxml;
			try_files     $uri @vuln_cache;
		}

		location @vuln_cache {
			root                     /data/cache/vulnxml;
			proxy_store              on;
			proxy_pass               http://vuxml.freebsd.org;
			proxy_http_version       1.1;
			proxy_cache_lock         on;
			proxy_cache_lock_timeout 20s;
			proxy_cache_revalidate   on;
			proxy_cache_valid        200 301 302 12h;
			proxy_cache_valid        404 5m;
		}
	}
'
	export _NGINX_SERVER
	configure_nginx_server_d bsd_cache vulnxml
}

install_bsd_cache()
{
	install_nginx || exit
}

create_cachedir()
{
	local _cachedir="$ZFS_DATA_MNT/bsd_cache/cache"
	if [ -d "$_cachedir" ]; then return; fi

	tell_status "creating $_cachedir"
	mkdir "$_cachedir"
	chown 80:80 $_cachedir
	echo "done"
}

configure_bsd_cache()
{
	configure_nginx bsd_cache
	configure_nginx_server
	create_cachedir
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

update_existing_jails()
{
	tell_status "configuring all jails to use bsd_cache"
	for _j in $JAIL_ORDERED_LIST; do
		if [ "$_j" = "bsd_cache" ]; then continue; fi
		if [ ! -d "$ZFS_JAIL_MNT/$_j/etc" ]; then continue; fi

		local _repo_dir="$ZFS_JAIL_MNT/$_j/usr/local/etc/pkg/repos"
		if [ ! -d "$_repo_dir" ]; then mkdir -p "$_repo_dir"; fi

		store_config "$_repo_dir/FreeBSD.conf" "overwrite" <<EO_PKG_CONF
FreeBSD: {
	enabled: no
}
EO_PKG_CONF

		store_config "$_repo_dir/MT6.conf" "overwrite" <<EO_PKG_MT6
MT6: {
	url: "http://pkg/\${ABI}/$TOASTER_PKG_BRANCH",
	enabled: yes
}
EO_PKG_MT6

		# cache pkg audit vulnerability db
		sed -i '' \
			-e '/^#VULNXML_SITE/ s/^#//; s/vuxml.freebsd.org/vulnxml/' \
			"$ZFS_JAIL_MNT/$_j/usr/local/etc/pkg.conf"

		sed -i '' -e '/^ServerName/ s/update.FreeBSD.org/freebsd-update/' \
			"$ZFS_JAIL_MNT/$_j/etc/freebsd-update.conf"

		echo "done"
	done
}

base_snapshot_exists || exit
create_staged_fs bsd_cache
start_staged_jail bsd_cache
install_bsd_cache
configure_bsd_cache
start_bsd_cache
test_bsd_cache
promote_staged_jail bsd_cache
update_existing_jails