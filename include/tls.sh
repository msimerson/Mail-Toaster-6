#!/bin/sh

HOST_TLS_CRT=/etc/ssl/certs/server.crt
HOST_TLS_KEY=/etc/ssl/private/server.key

install_tls_pair()
{
	local _crt="$1" _key="$2" _f
	if [ -f "$_crt" ] && [ -f "$_key" ]; then
		tell_status "TLS certificate $_crt already installed"
		return
	fi

	# half a pair is unusable; set it aside
	for _f in "$_crt" "$_key"; do
		if [ -f "$_f" ]; then
			tell_status "preserving unpaired $_f as $_f.orphan"
			mv "$_f" "$_f.orphan"
		fi
	done

	tell_status "installing TLS certificate $_crt"
	install -m 0644 "${3:-$HOST_TLS_CRT}" "$_crt"
	install -m 0600 "${4:-$HOST_TLS_KEY}" "$_key"
}

# certs are issued for TOASTER_HOSTNAME (host.sh, letsencrypt.sh)
install_jail_tls_pair()
{
	local _etc _tlsdir
	_etc="$(get_jail_data "$1")/etc"
	_tlsdir="$_etc/tls"

	if [ ! -d "$_tlsdir" ] && [ -d "$_etc/ssl" ]; then
		tell_status "Renaming /data/etc/ssl to /data/etc/tls"
		mv "$_etc/ssl" "$_tlsdir"
	fi

	install -d -m 0755 "$_tlsdir/certs"
	install -d -m 0700 "$_tlsdir/private"

	local _crt="$_tlsdir/certs/${TOASTER_HOSTNAME}.pem"
	local _key="$_tlsdir/private/${TOASTER_HOSTNAME}.pem"
	local _old_crt="$_tlsdir/certs/${TOASTER_MAIL_DOMAIN}.pem"
	local _old_key="$_tlsdir/private/${TOASTER_MAIL_DOMAIN}.pem"

	if [ -f "$_old_crt" ] && [ -f "$_old_key" ]; then
		# copy, not mv: the running jail's config still names these until it is replaced
		install_tls_pair "$_crt" "$_key" "$_old_crt" "$_old_key"
	else
		install_tls_pair "$_crt" "$_key"
	fi
}

install_tls_pem()
{
	[ ! -f "$1" ] || return 0

	tell_status "installing TLS key and certificate to $1"
	install -d "$(dirname "$1")"
	( umask 077; cat "$HOST_TLS_KEY" "$HOST_TLS_CRT" > "$1" )
}
