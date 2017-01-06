#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_haproxy()
{
	tell_status "installing haproxy"
	stage_pkg_install haproxy || exit
}

configure_haproxy()
{
	if [ -f "$ZFS_DATA_MNT/haproxy/etc/haproxy.conf" ]; then
		tell_status "using $ZFS_DATA_MNT/haproxy/etc/haproxy.conf"
		stage_sysrc haproxy_config="/data/etc/haproxy.conf"
		return
	fi

	tell_status "configuring MT6 default haproxy"
	tee "$STAGE_MNT/usr/local/etc/haproxy.conf" <<EO_HAPROXY_CONF
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
    acl is_websocket hdr(Upgrade) -i WebSocket
    acl is_websocket hdr_beg(Host) -i ws
    use_backend websocket_haraka    if  is_websocket
    redirect scheme https code 301 if !is_websocket !{ ssl_fc }

frontend https-in
    bind *:443 ssl crt /etc/ssl/private
    # ciphers AES128+EECDH:AES128+EDH
    reqadd X-Forwarded-Proto:\ https
    default_backend www_webmail

    acl is_websocket hdr(Upgrade) -i WebSocket
    acl is_websocket hdr_beg(Host) -i ws

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
    acl stage        path_beg /stage

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
    use_backend www_stage        if  stage

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

backend www_stage
    server monitor $(get_jail_ip stage):80

EO_HAPROXY_CONF

	if ls /etc/ssl/private/*.pem; then
		tell_status "copying PEM files"
		cp /etc/ssl/private/*.pem "$STAGE_MNT/etc/ssl/private/"
	else
		tell_status "concatenating server key and crt to PEM"
		cat /etc/ssl/private/server.key /etc/ssl/certs/server.crt \
			> "$STAGE_MNT/etc/ssl/private/server.pem" || exit 1
	fi

    if [ ! -d "$ZFS_DATA_MNT/haproxy/ssl" ]; then
        mkdir -p "$ZFS_DATA_MNT/haproxy/ssl" || exit 1
    fi

    if [ ! -f "$ZFS_DATA_MNT/haproxy/ssl/dhparam.pem" ]; then
        tell_status "creating dhparam file for haproxy"
        openssl dhparam 2048 -out "$ZFS_DATA_MNT/haproxy/ssl/dhparam.pem"
    fi
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
start_staged_jail
install_haproxy
configure_haproxy
start_haproxy
test_haproxy
promote_staged_jail haproxy
