#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
# shellcheck disable=2016
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/letsencrypt \$path/data nullfs rw 0 0\";"

install_letsencrypt()
{
	tell_status "installing Let's Encrypt"
	stage_pkg_install curl
	local _installer="$STAGE_MNT/acme.sh"
	fetch -o $_installer https://raw.githubusercontent.com/Neilpang/acme.sh/master/acme.sh
	sed -i.bak -e '/^DEFAULT_INSTALL_HOME=/ s/=.*$/="\/data"/' $_installer
	stage_exec sh /data/acme.sh --install
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
	if [ -s "$_installed" ]; then
		rm $_tmp_crt
		_debug "restarting dovecot"
		jexec dovecot service dovecot restart
		return 0
	fi

	_err "install to $_installed failed"
	return 1
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

	if [ -s "$_installed" ]; then
		rm $_tmp
		_debug "restarting haraka"
		service jail restart haraka
		return 0
	fi

	_err "install to $_installed failed"
	return 1
}
EO_LE_HARAKA
}

install_deploy_scripts()
{
	export _deploy="$ZFS_DATA_MNT/letsencrypt/deploy"
	if [ ! -d $_deploy ]; then
		mkdir $_deploy || exit
	fi

	install_deploy_haproxy
	install_deploy_dovecot
	install_deploy_haraka
}

configure_letsencrypt()
{
	tell_status "configuring Let's Encrypt"

	install_deploy_scripts

	sed -i.bak \
		-e '/^DEFAULT_INSTALL_HOME=/ s/=.*$/="\/data\/letsencrypt"/' \
		"$ZFS_DATA_MNT/letsencrypt/acme.sh"

	local _HTTPDIR="$ZFS_DATA_MNT/webmail/htdocs"
	local _acme="$ZFS_DATA_MNT/letsencrypt/acme.sh"
	$_acme --issue --force -d $TOASTER_HOSTNAME -w $_HTTPDIR
	$_acme --deploy -d $TOASTER_HOSTNAME -w $_HTTPDIR --deploy-hook haproxy
	$_acme --deploy -d $TOASTER_HOSTNAME -w $_HTTPDIR --deploy-hook dovecot
	$_acme --deploy -d $TOASTER_HOSTNAME -w $_HTTPDIR --deploy-hook haraka
}

start_letsencrypt()
{
	tell_status "starting Let's Encrypt"

	if [ ! -d "/usr/local/etc/periodic/daily" ]; then
		mkdir "/usr/local/etc/periodic/daily" || exit
	fi

	local _script="/usr/local/etc/periodic/daily/mt6-letsencrypt"
	if [ -f $_script ]; then
		tell_status "periodic installed"
		return
	fi

	tell_status "installing periodic job to keep certs updated"
	tee $_script <<EO_LE_PERIODIC
#!/bin/sh

_acme="$ZFS_DATA_MNT/letsencrypt/acme.sh"
\$_acme --issue -d $TOASTER_HOSTNAME -w $_HTTPDIR || exit 0
\$_acme --deploy -d $TOASTER_HOSTNAME -w $_HTTPDIR --deploy-hook haproxy
\$_acme --deploy -d $TOASTER_HOSTNAME -w $_HTTPDIR --deploy-hook dovecot
\$_acme --deploy -d $TOASTER_HOSTNAME -w $_HTTPDIR --deploy-hook haraka

EO_LE_PERIODIC

	chmod 755 $_script
}

test_letsencrypt()
{
	if [ ! -f "$ZFS_DATA_MNT/letsencrypt/acme.sh" ]; then
		echo "not installed!"
		exit
	fi

	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs letsencrypt
start_staged_jail
install_letsencrypt
configure_letsencrypt
start_letsencrypt
test_letsencrypt
promote_staged_jail letsencrypt
