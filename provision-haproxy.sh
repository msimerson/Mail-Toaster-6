#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_haproxy()
{
	tell_status "installing haproxy"
	stage_pkg_install haproxy || exit

	if [ "$TLS_LIBRARY" != "libressl" ]; then
		return
	fi

	tell_status "compiling haproxy against libressl"
	echo 'DEFAULT_VERSIONS+=ssl=libressl' >> "$STAGE_MNT/etc/make.conf"
	stage_pkg_install pcre gmake libressl
	stage_exec make -C /usr/ports/net/haproxy build deinstall install clean
}

configure_haproxy_dot_conf()
{
	local _data_cf="$ZFS_DATA_MNT/haproxy/etc/haproxy.conf"
	if [ -f "$_data_cf" ]; then
		tell_status "preserving $_data_cf"
		return
	fi

	tell_status "configuring MT6 default haproxy"
	tee "$_data_cf" <<EO_HAPROXY_CONF
	global
	daemon
	maxconn     256  # Total Max Connections. This is dependent on ulimit
	nbproc      1
	ssl-default-bind-options no-sslv3 no-tls-tickets
	ssl-dh-param-file /data/ssl/dhparam.pem
	tune.ssl.default-dh-param 2048

	defaults
	mode        http
	balance     roundrobin
	option      forwardfor   # set X-Forwarded-For
	option      httpclose
	option      http-server-close
	option      log-separate-errors
	log         global
	timeout     connect 5s
	timeout     server 30s
	timeout     client 30s
	#   timeout     client 86400s
	timeout     tunnel 1h

	#listen stats *:9000
	#    mode http
	#    balance
	#    stats uri /haproxy_stats
	#    stats realm HAProxy\ Statistics
	#    stats auth admin:password
	#    stats admin if TRUE

	frontend http-in
	bind *:80
	bind *:443 ssl crt /etc/ssl/private
	# ciphers AES128+EECDH:AES128+EDH

	http-request  set-header X-Forwarded-Proto https if { ssl_fc }
	http-request  set-header X-Forwarded-Port %[dst_port]
	http-response set-header X-Frame-Options sameorigin

	acl is_websocket hdr(Upgrade) -i WebSocket
	acl is_websocket hdr_beg(Host) -i ws
	acl letsencrypt  path_beg -i /.well-known
	redirect scheme https code 301 if !is_websocket !letsencrypt !{ ssl_fc }

	acl munin        path_beg /munin
	acl nagios       path_beg /nagios
	acl watch        path_beg /watch
	acl haraka       path_beg /haraka
	acl haraka       path_beg /logs
	acl qmailadmin   path_beg /qmailadmin
	acl qmailadmin   path_beg /cgi-bin/qmailadmin
	acl sqwebmail    path_beg /sqwebmail
	acl sqwebmail    path_beg /cgi-bin/sqwebmail
	acl isoqlog      path_beg /isoqlog
	acl rspamd       path_beg /rspamd
	acl roundcube    path_beg /roundcube
	acl rainloop     path_beg /rainloop
	acl squirrelmail path_beg /squirrelmail
	acl nictool      path_beg /nictool
	acl mediawiki    path_beg /wiki
	acl mediawiki    path_beg /w/
	acl smf          path_beg /forum
	acl wordpress    path_beg /wordpress
	acl stage        path_beg /stage
	acl horde	 path_beg /horde

	use_backend websocket_haraka if  is_websocket
	use_backend www_monitor      if  munin
	use_backend www_monitor      if  nagios
	use_backend www_haraka       if  watch
	use_backend www_vpopmail     if  qmailadmin
	use_backend www_sqwebmail    if  sqwebmail
	use_backend www_vpopmail     if  isoqlog
	use_backend www_haraka       if  haraka
	use_backend www_rspamd       if  rspamd
	use_backend www_roundcube    if  roundcube
	use_backend www_rainloop     if  rainloop
	use_backend www_squirrelmail if  squirrelmail
	use_backend www_nictool      if  nictool
	use_backend www_mediawiki    if  mediawiki
	use_backend www_smf          if  smf
	use_backend www_wordpress    if  wordpress
	use_backend www_stage        if  stage
	use_backend www_horde        if horde

	# for Let's Encrypt SSL/TLS certificates
	use_backend www_webmail      if  letsencrypt

	default_backend www_webmail

	backend www_vpopmail
	server vpopmail $(get_jail_ip vpopmail):80

	backend www_sqwebmail
	server sqwebmail $(get_jail_ip sqwebmail):80

	backend www_haraka
	server haraka $(get_jail_ip haraka):80
	reqirep ^([^\ :]*)\ /haraka/(.*)    \1\ /\2

	backend websocket_haraka
	timeout queue 5s
	timeout server 86400s
	timeout connect 86400s
	server haraka $(get_jail_ip haraka):80

	backend www_webmail
	server webmail $(get_jail_ip webmail):80

	backend www_roundcube
	server roundcube $(get_jail_ip roundcube):80
	reqirep ^([^\ :]*)\ /roundcube/(.*)    \1\ /\2

	backend www_squirrelmail
	server squirrelmail $(get_jail_ip squirrelmail):80

	backend www_rainloop
	server rainloop $(get_jail_ip rainloop):80
	reqirep ^([^\ :]*)\ /rainloop/(.*)    \1\ /\2

	backend www_monitor
	server monitor $(get_jail_ip monitor):80

	backend www_rspamd
	server monitor $(get_jail_ip rspamd):11334
	reqirep ^([^\ :]*)\ /rspamd/(.*)    \1\ /\2

	backend www_nictool
	server monitor $(get_jail_ip nictool):80
	reqirep ^([^\ :]*)\ /nictool/(.*)    \1\ /\2

	backend www_mediawiki
	server monitor $(get_jail_ip mediawiki):80

	backend www_smf
	server monitor $(get_jail_ip smf):80

	backend www_wordpress
	server monitor $(get_jail_ip wordpress):80

	backend www_stage
	server monitor $(get_jail_ip stage):80

	backend www_horde
	server monitor $(get_jail_ip horde):80

EO_HAPROXY_CONF
}

configure_haproxy_tls()
{
	if [ ! -f "$STAGE_MNT/etc/ssl/private/server.pem" ]; then
		tell_status "concatenating TLS key and crt to PEM"
		cat /etc/ssl/private/server.key /etc/ssl/certs/server.crt \
			> "$STAGE_MNT/etc/ssl/private/server.pem" || exit 1
	fi

	if [ ! -d "$ZFS_DATA_MNT/haproxy/ssl" ]; then
		tell_status "creating /data/ssl"
		mkdir -p "$ZFS_DATA_MNT/haproxy/ssl" || exit 1
	fi

	if [ ! -d "$ZFS_DATA_MNT/haproxy/ssl.d" ]; then
		tell_status "creating /data/ssl.d"
		mkdir -p "$ZFS_DATA_MNT/haproxy/ssl.d" || exit 1
	fi

	if [ ! -f "$ZFS_DATA_MNT/haproxy/ssl/dhparam.pem" ]; then
		tell_status "creating dhparam file for haproxy"
		openssl dhparam 2048 -out "$ZFS_DATA_MNT/haproxy/ssl/dhparam.pem"
	fi
}

configure_haproxy()
{
	if [ ! -d "$ZFS_DATA_MNT/haproxy/etc" ]; then
		tell_status "creating /data/etc"
		mkdir -p "$ZFS_DATA_MNT/haproxy/etc" || exit
	fi

	configure_haproxy_dot_conf
	stage_sysrc haproxy_config="/data/etc/haproxy.conf"

	if [ -f "$STAGE_MNT/usr/local/etc/haproxy.conf" ]; then
		rm "$STAGE_MNT/usr/local/etc/haproxy.conf"
	fi
	stage_exec ln -s /data/etc/haproxy.conf /usr/local/etc/haproxy.conf

	configure_haproxy_tls
}

start_haproxy()
{
	tell_status "starting haproxy"
	stage_sysrc haproxy_enable=YES

	if [ -f "$ZFS_JAIL_MNT/haproxy/var/run/haproxy.pid" ]; then
		echo "haproxy is running, this might fail."
	fi

	stage_exec service haproxy start
}

test_haproxy()
{
	tell_status "testing haproxy"
	if [ ! -f "$ZFS_JAIL_MNT/haproxy/var/run/haproxy.pid" ]; then
		stage_listening 443
		echo "it worked"
		return
	fi

	echo "previous haproxy is running, ignoring errors"
	sockstat -l -4 -6 -p 443 -j "$(jls -j stage jid)"
}

base_snapshot_exists || exit
create_staged_fs haproxy
start_staged_jail haproxy
install_haproxy
configure_haproxy
start_haproxy
test_haproxy
promote_staged_jail haproxy
