#!/bin/sh

# certs are issued for TOASTER_HOSTNAME (host.sh, letsencrypt.sh)
install_jail_tls_pair()
{
	local _etc _tlsdir _f
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
	if [ -f "$_crt" ] && [ -f "$_key" ]; then
		tell_status "$1 TLS certificates already installed"
		return
	fi

	# half a pair is unusable; set it aside
	for _f in "$_crt" "$_key"; do
		if [ -f "$_f" ]; then
			tell_status "preserving unpaired $_f as $_f.orphan"
			mv "$_f" "$_f.orphan"
		fi
	done

	local _old_crt="$_tlsdir/certs/${TOASTER_MAIL_DOMAIN}.pem"
	local _old_key="$_tlsdir/private/${TOASTER_MAIL_DOMAIN}.pem"
	if [ -f "$_old_crt" ] && [ -f "$_old_key" ]; then
		# copy, not mv: the running jail's config still names these until it is replaced
		tell_status "copying $1 TLS certificates from ${TOASTER_MAIL_DOMAIN}.pem"
		install -m 0644 "$_old_crt" "$_crt"
		install -m 0600 "$_old_key" "$_key"
		return
	fi

	tell_status "installing $1 TLS certificates"
	install -m 0644 /etc/ssl/certs/server.crt "$_crt"
	install -m 0600 /etc/ssl/private/server.key "$_key"
}
