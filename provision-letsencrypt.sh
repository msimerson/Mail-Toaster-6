#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

install_letsencrypt()
{
	tell_status "installing Let's Encrypt"
	pkg install -y curl
	fetch -o - https://get.acme.sh | sh
}

# shellcheck disable=SC2120
install_deploy_haproxy()
{
	# shellcheck disable=SC2154
	tee "$_deploy/haproxy" <<'EO_LE_HAPROXY'
#!/bin/sh

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
		exit 2
	fi

	if [ ! -d /data/haproxy/ssl.d ]; then
		_debug "no /data/haproxy/ssl.d dir"
		return 0
	fi

	local _tmp="/tmp/${_cdomain}.pem"
	cat $_ckey $_ccert $_cfullchain > $_tmp
	if [ ! -s "$_tmp" ]; then
		_err "Unable to create $_tmp"
		return 1
	fi

	_debug "$_tmp created"
	local _installed="/data/haproxy/ssl.d/$_cdomain.pem"
	if diff -q $_tmp $_installed; then
		_debug "cert is the same, skip deploy"
		return 0
	fi

	_debug "cp $_tmp $_installed"
	cp $_tmp $_installed || return 1
	if [ ! -s "$_installed" ]; then
		_err "install to $_installed failed"
		return 1
	fi

	rm $_tmp
	_debug "restarting haproxy"
	jexec haproxy service haproxy restart
	return 0
}
EO_LE_HAPROXY
}

# shellcheck disable=SC2120
install_deploy_dovecot()
{
	# shellcheck disable=SC2154
	tee "$_deploy/dovecot" <<'EO_LE_DOVECOT'
#!/bin/sh

#domain keyfile certfile cafile fullchain
dovecot_deploy() {
	_cdomain="$1"
	_ckey="$2"
	_ccert="$3"
	_cca="$4"
	_cfullchain="$5"

	if [ ! -f $_ccert ]; then
		_err "missing certificate"
		exit 2
	fi

	if [ ! -d /data/dovecot/etc/ssl ]; then
		_debug "no /data/dovecot/etc/ssl dir"
		return 0
	fi

	local _tmp_crt="/tmp/dovecot-cert-${_cdomain}.pem"
	cat $_ccert $_cfullchain > $_tmp_crt
	if [ ! -s "$_tmp_crt" ]; then
		_err "Unable to create $_tmp_crt"
		return 1
	fi

	_debug "$_tmp_crt created"
	local _installed="/data/dovecot/etc/ssl/certs/dovecot.pem"
	if diff -q $_tmp_crt $_installed; then
		_debug "cert is the same, skip deploy"
		return 0
	fi

	cp $_tmp_crt $_installed || return 1
	cp $_ckey /data/dovecot/etc/ssl/private/dovecot.pem || return 1
	if [ ! -s "$_installed" ]; then
		_err "install to $_installed failed"
		return 1
	fi

	rm $_tmp_crt
	_debug "restarting dovecot"
	jexec dovecot service dovecot restart
	return 0
}
EO_LE_DOVECOT
}

# shellcheck disable=SC2120
install_deploy_haraka()
{
	# shellcheck disable=SC2154
	tee "$_deploy/haraka" <<'EO_LE_HARAKA'
#!/bin/sh

#returns 0 means success, otherwise error.

#domain keyfile certfile cafile fullchain
haraka_deploy() {
	_cdomain="$1"
	_ckey="$2"
	_ccert="$3"
	_cca="$4"
	_cfullchain="$5"

	if [ ! -f $_ccert ]; then
		_err "missing certificate"
		exit 2
	fi

	if [ ! -d /data/haraka/config ]; then
		_debug "no /data/haraka/config dir"
		return 0
	fi

	local _tmp="/tmp/${_cdomain}.pem"
	cat $_ckey $_ccert $_cfullchain > $_tmp
	if [ ! -s "$_tmp" ]; then
		_err "Unable to create $_tmp"
		return 1
	fi

	_debug "$_tmp created"
	local _installed="/data/haraka/config/tls_cert.pem"
	if diff -q $_tmp $_installed; then
		_debug "cert is the same, skip deploy"
		return 0
	fi

	cp $_tmp $_installed || return 1
	cp $_ckey /data/haraka/config/tls_key.pem || return 1

	if [ ! -s "$_installed" ]; then
		_err "install to $_installed failed"
		return 1
	fi

	rm $_tmp
	_debug "restarting haraka"
	service jail restart haraka
	return 0
}
EO_LE_HARAKA
}

# shellcheck disable=SC2120
install_deploy_mailtoaster()
{
	# shellcheck disable=SC2154
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
}

update_haproxy_ssld()
{
	local _haconf="$ZFS_DATA_MNT/haproxy/etc/haproxy.conf"
	if ! grep -q 'ssl crt /etc' "$_haconf"; then
		# already updated
		return
	fi

	tell_status "switching haproxy TLS cert dir to /data/ssl.d"
	sed -i .bak \
		-e 's!ssl crt /etc.*!ssl crt /data/ssl.d!' \
		"$_haconf"
}

configure_letsencrypt()
{
	install_deploy_scripts

	tell_status "configuring Let's Encrypt"

	local _HTTPDIR="$ZFS_DATA_MNT/webmail/htdocs"
	local _acme="/root/.acme.sh/acme.sh"
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
