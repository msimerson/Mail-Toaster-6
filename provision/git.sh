#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

mt6-include nginx

install_git()
{
	for _d in etc home; do
		_path="$STAGE_MNT/data/$_d"
		[ -d "$_path" ] || mkdir "$_path"
	done

	tell_status "install git"
	stage_pkg_install git nginx fcgiwrap

	tell_status "install cgit (web UI for git repos)"
	stage_pkg_install cgit py312-pygments py312-markdown
}

configure_nginx_server()
{
	_NGINX_SERVER="
	server_name git default_server;
	root /data/htdocs;

	location /.well-known/acme-challenge {
		try_files \$uri =404;
	}

	location /.well-known/pki-validation {
		try_files \$uri =404;
	}

	# Forbid access to other dotfiles
	location ~ /\.(?!well-known).* {
		return 403;
	}

	client_max_body_size 100M;

	location ~ /[^/]+\.git/(HEAD|info/refs|objects/info/[^/]+|git-(upload|receive)-pack)\$ {
		root   /data/repos;
		include fastcgi_params;
		fastcgi_param SCRIPT_FILENAME /usr/local/libexec/git-core/git-http-backend;
		fastcgi_param GIT_HTTP_EXPORT_ALL "";
		fastcgi_param GIT_PROJECT_ROOT /data/repos;
		fastcgi_param PATH_INFO \$uri;
		fastcgi_param REMOTE_USER \$remote_user;
		fastcgi_pass unix:/var/run/fcgiwrap/fcgiwrap.sock;
	}

	location / {
		root   /data/repos;
		try_files      \$uri @cgit;
	}

	location @cgit {
		include        fastcgi_params;
		fastcgi_param  SCRIPT_FILENAME   /usr/local/www/cgit/cgit.cgi;
		fastcgi_param  PATH_INFO         \$uri;
		fastcgi_param  QUERY_STRING      \$args;
		fastcgi_param  HTTP_HOST         \$server_name;
		fastcgi_pass   unix:/var/run/fcgiwrap/fcgiwrap.sock;
	}"
	export _NGINX_SERVER
	configure_nginx_server_d git
}

configure_pf()
{
	_pf_etc="$ZFS_DATA_MNT/git/etc/pf.conf.d"

	store_config "$_pf_etc/rdr.conf" <<EO_GIT_RDR
int_ip4 = "$(get_jail_ip git)"
int_ip6 = "$(get_jail_ip6 git)"

rdr inet  proto tcp from any to <ext_ip4> port { 8080 } -> \$int_ip4 80
rdr inet6 proto tcp from any to <ext_ip6> port { 8080 } -> \$int_ip6 80
EO_GIT_RDR

	get_public_ip4
	get_public_ip6

	store_config "$_pf_etc/git.table" <<EO_WEBMAIL_TABLE
$PUBLIC_IP4
$PUBLIC_IP6
$(get_jail_ip git)
$(get_jail_ip6 git)
EO_WEBMAIL_TABLE

	store_config "$_pf_etc/filter.conf" <<EO_WEBMAIL_FILTER
pass in quick proto tcp from any to <git> port { 80 8080 }
EO_WEBMAIL_FILTER
}

configure_cgit()
{
	store_config "$ZFS_JAIL_MNT/git/etc/cgitrc" <<EO_WEBMAIL_FILTER
# Enable syntax highlighting (optional, requires python-pygments)
enable-git-config=0
scan-hidden-path=1
virtual-root=/
enable-http-clone=1
enable-index-owner=0

readme=:README.md
source-filter=/usr/local/lib/cgit/filters/syntax-highlighting.py
about-filter=/usr/local/lib/cgit/filters/about-formatting.sh

# Tell cgit where to look for repositories
scan-path=/data/repos
EO_WEBMAIL_FILTER

}

configure_git()
{
	configure_nginx_server
	configure_pf

	stage_sysrc sshd_enable=YES
	stage_sysrc fcgiwrap_enable=YES
	stage_sysrc fcgiwrap_user="www"
	stage_sysrc fcgiwrap_group="www"
	stage_sysrc fcgiwrap_socket_owner="www"
	stage_sysrc fcgiwrap_socket_group="www"
	stage_sysrc nginx_enable=YES
}

start_git()
{
	stage_exec service sshd start
	stage_exec service fcgiwrap start
	stage_exec service nginx start
}

test_git()
{
	echo "testing git..."
	stage_listening 80
	echo "it worked"
}

base_snapshot_exists || exit 1
create_staged_fs git
start_staged_jail git
install_git
configure_git
start_git
test_git
promote_staged_jail git
