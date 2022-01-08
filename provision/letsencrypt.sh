#!/bin/sh

. mail-toaster.sh || exit

install_letsencrypt()
{
	tell_status "installing ACME.sh & Let's Encrypt"
	pkg install -y curl socat
	fetch -o - https://get.acme.sh | sh
}

install_deploy_haproxy()
{
	tee "$_deploy/haproxy" <<'EO_LE_HAPROXY'
#!/bin/sh

has_differences() {

	if [ ! -f "$2" ]; then
		_debug "non-existent, deploying: $2"
		return 0
	fi

	if diff -q "$1" "$2"; then
		_debug "file contents identical, skip deploy of $2"
		return 1
	fi

	_debug "file has changes, deploying"
	return 0
}

install_file() {
	_debug "cp $1 $2"
	cp "$1" "$2" || return 1

	if [ ! -s "$2" ]; then
		_err "install to $2 failed"
		return 1
	fi

	_debug "installed as $2"
	return 0
}

#returns 0 means success, otherwise error.

#domain keyfile certfile cafile fullchain
haproxy_deploy() {
	_cdomain="$1"
	_ckey="$2"
	_ccert="$3"
	_cca="$4"
	_cfullchain="$5"

	if [ ! -f $_ccert ]; then
		_err "missing certificate"
		return 2
	fi

	if [ ! -d /data/haproxy/ssl.d ]; then
		_debug "no /data/haproxy/ssl.d dir"
		return 0
	fi

	local _tmp="/tmp/${_cdomain}.pem"
	cat $_ckey $_cfullchain > $_tmp
	if [ ! -s "$_tmp" ]; then
		_err "Unable to create $_tmp"
		return 1
	fi

	_debug "$_tmp created"
	local _installed="/data/haproxy/ssl.d/$_cdomain.pem"
	has_differences "$_tmp" "$_installed" || return 0
	install_file "$_tmp" "$_installed" || return 1
	install_file "$_cca" "${_installed}.issuer"

	rm "$_tmp"
	_debug "restarting haproxy"
	jexec haproxy service haproxy restart
	return 0
}
EO_LE_HAPROXY
}

install_deploy_dovecot()
{
	tee "$_deploy/dovecot" <<'EO_LE_DOVECOT'
#!/bin/sh

assure_file() {

	if [ ! -s "$1" ]; then
		_err "File doesn't exist: $1"
		return 1
	fi

	_debug "file exists: $1"
	return 0
}

has_differences() {

	if [ ! -f "$2" ]; then
		_debug "non-existent, deploying: $2"
		return 0
	fi

	if diff -q "$1" "$2"; then
		_debug "file contents identical, skip deploy of $2"
		return 1
	fi

	_debug "file has changes, deploying"
	return 0
}

install_file() {
	cp "$1" "$2" || return 1

	if [ ! -s "$2" ]; then
		_err "install to $2 failed"
		return 1
	fi

	_debug "installed as $2"
	return 0
}

#domain keyfile certfile cafile fullchain
dovecot_deploy() {
	_cdomain="$1"
	_ckey="$2"
	_ccert="$3"
	_cca="$4"
	_cfullchain="$5"

	assure_file "$_ccert" || return 2

	_ssl_dir="/data/dovecot/etc/ssl"
	if [ ! -d "$_ssl_dir" ]; then
		_debug "no TLS/SSL dir: $_ssl_dir"
		return 0
	fi

	assure_file "$_cfullchain" || return 1;

	local _crt_installed="$_ssl_dir/certs/${_cdomain}.pem"
	local _key_installed="$_ssl_dir/private/${_cdomain}.pem"

	has_differences "$_cfullchain" "$_crt_installed" || return 0
	install_file "$_cfullchain" "$_crt_installed" || return 1
	install_file "$_ckey"    "$_key_installed" || return 1

	_debug "restarting dovecot"
	jexec dovecot service dovecot restart
	return 0
}
EO_LE_DOVECOT
}

install_deploy_haraka()
{
	tee "$_deploy/haraka" <<'EO_LE_HARAKA'
#!/bin/sh

assure_file() {

	if [ ! -s "$1" ]; then
		_err "File doesn't exist: $1"
		return 1
	fi

	_debug "file exists: $1"
	return 0
}

has_differences() {

	if [ ! -f "$2" ]; then
		_debug "non-existent, deploying: $2"
		return 0
	fi

	if diff -q "$1" "$2"; then
		_debug "file contents identical, skip deploy of $2"
		return 1
	fi

	_debug "file has changes, deploying"
	return 0
}

install_file() {
	cp "$1" "$2" || return 1

	if [ ! -s "$2" ]; then
		_err "install to $2 failed"
		return 1
	fi

	_debug "installed as $2"
	return 0
}

#returns 0 means success, otherwise error.

#domain keyfile certfile cafile fullchain
haraka_deploy() {
	_cdomain="$1"
	_ckey="$2"
	_ccert="$3"
	_cca="$4"
	_cfullchain="$5"

	assure_file "$_ccert" || return 2
	_h_conf="/data/haraka/config"

	if [ ! -d "$_h_conf" ]; then
		_debug "missing config dir: $_h_conf"
		return 0
	fi

	if [ -d "$_h_conf/tls" ]; then
		local _tmp="/tmp/${_cdomain}.pem"
		cat $_ckey $_cfullchain > $_tmp
		assure_file "$_tmp" || return 1

		local _installed="$_h_conf/tls/${_cdomain}.pem"
		has_differences "$_tmp" "$_installed" || return 0
		install_file "$_tmp" "$_installed" || return 1
		rm $_tmp
	else
		local _installed="$_h_conf/tls_cert.pem"
		has_differences "$_cfullchain" "$_installed" || return 0
		install_file "$_cfullchain" "$_installed" || return 1
		install_file "$_ckey" "$_h_conf/tls_key.pem" || return 1
	fi

	_debug "restarting haraka"
	service jail restart haraka
	return 0
}
EO_LE_HARAKA
}

install_deploy_mysql()
{
	tee "$_deploy/mysql" <<'EO_LE_MYSQL'
#!/bin/sh

assure_file() {

	if [ ! -s "$1" ]; then
		_err "File doesn't exist: $1"
		return 1
	fi

	_debug "file exists: $1"
	return 0
}

has_differences() {

	if [ ! -f "$2" ]; then
		_debug "non-existent, deploying: $2"
		return 0
	fi

	if diff -q "$1" "$2"; then
		_debug "file contents identical, skip deploy of $2"
		return 1
	fi

	_debug "file has changes, deploying"
	return 0
}

install_file() {
	cp "$1" "$2" || return 1

	if [ ! -s "$2" ]; then
		_err "install to $2 failed"
		return 1
	fi

	chown 88:88 "$2"

	_debug "installed as $2"
	return 0
}

#returns 0 means success, otherwise error.

#domain keyfile certfile cafile fullchain
mysql_deploy() {
	_cdomain="$1"
	_ckey="$2"
	_ccert="$3"
	_cca="$4"
	_cfullchain="$5"

	assure_file "$_ccert" || return 2

	_my_conf="/data/mysql"
	if [ ! -d "$_my_conf" ]; then
		_debug "missing mysql dir: $_my_conf"
		return 0
	fi

	_tls_dir="$_my_conf/tls"

	if [ ! -d "$_tls_dir" ]; then
		_debug "creating $_tls_dir"
		mkdir "$_tls_dir" || return 2
	fi

	# use file names from docs:
	#   https://dev.mysql.com/doc/refman/5.6/en/using-encrypted-connections.html
	has_differences "$_ccert"   "$_tls_dir/server-cert.pem"     || return 0

	install_file "$_ccert"      "$_tls_dir/server-cert.pem"     || return 1
	install_file "$_ckey"       "$_tls_dir/server-key.pem"      || return 1
	install_file "$_cfullchain" "$_tls_dir/ca.pem" || return 1

	_debug "restarting mysql"
	jexec mysql service mysql-server restart
	return 0
}
EO_LE_MYSQL
}

install_deploy_mailtoaster()
{
	tee "$_deploy/mailtoaster" <<'EO_LE_MT'
#!/usr/local/bin/bash

#domain keyfile certfile cafile fullchain
mailtoaster_deploy() {
	_cdomain="$1"
	_ckey="$2"
	_ccert="$3"
	_cca="$4"
	_cfullchain="$5"

	for _target in haraka haproxy dovecot
	do
		echo "deploying $_target"
		. "/root/.acme.sh/deploy/$_target"
		${_target}_deploy $* || return 2
	done

	return 0
}
EO_LE_MT
}

install_deploy_scripts()
{
	tell_status "installing deployment scripts"
	export _deploy="/root/.acme.sh/deploy"

	install_deploy_haproxy
	install_deploy_dovecot
	install_deploy_haraka
	install_deploy_mailtoaster
	install_deploy_mysql
}

update_haproxy_ssld()
{
	local _haconf="$ZFS_DATA_MNT/haproxy/etc/haproxy.conf"
	if ! grep -q 'ssl crt /etc' "$_haconf"; then
		# already updated
		return
	fi

	tell_status "switching haproxy TLS cert dir to /data/ssl.d"
	sed -i.bak \
		-e 's!ssl crt /etc.*!ssl crt /data/ssl.d!' \
		"$_haconf"
}

configure_letsencrypt()
{
	install_deploy_scripts

	tell_status "configuring acme.sh"

	local _HTTPDIR="$ZFS_DATA_MNT/webmail"
	local _acme="/root/.acme.sh/acme.sh"

	$_acme --set-default-ca --server letsencrypt

	if $_acme --issue --force -d "$TOASTER_HOSTNAME" -w "$_HTTPDIR"; then
		update_haproxy_ssld
		$_acme --deploy -d "$TOASTER_HOSTNAME" --deploy-hook mailtoaster
	else
		tell_status "TLS Certificate Issue failed"
		exit 1
	fi
}

test_letsencrypt()
{
	if [ ! -f "/root/.acme.sh/acme.sh" ]; then
		echo "not installed!"
		exit
	fi

	echo "it worked"
}

install_letsencrypt
configure_letsencrypt
test_letsencrypt
