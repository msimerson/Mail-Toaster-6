#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_haproxy()
{
	if [ "$TLS_LIBRARY" = "libressl" ]; then
		install_haproxy_libressl || exit 1
		return
	fi

	tell_status "installing haproxy"
	stage_pkg_install haproxy || exit 1

	tell_status "consider installing hatop for a 'top' style haproxy dashboard"
	#stage_pkg_install hatop || exit 1
}

install_haproxy_libressl()
{
	tell_status "compiling haproxy against libressl"
	echo 'DEFAULT_VERSIONS+=ssl=libressl' >> "$STAGE_MNT/etc/make.conf"
	stage_pkg_install pcre gmake libressl || exit 1
	stage_port_install net/haproxy-devel || exit 1
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
	ssl-dh-param-file /etc/ssl/dhparam.pem
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
	compression algo gzip
	compression type text/html "text/html; charset=utf-8" text/html;charset=utf-8 text/plain text/css text/javascript application/x-javascript application/javascript application/ecmascript application/rss+xml application/atomsvc+xml application/atom+xml application/atom+xml;type=entry application/atom+xml;type=feed application/cmisquery+xml application/cmisallowableactions+xml application/cmisatom+xml application/cmistree+xml application/cmisacl+xml image/svg+xml

	#listen stats *:9000
	#    mode http
	#    balance
	#    stats uri /haproxy_stats
	#    stats realm HAProxy\ Statistics
	#    stats auth admin:password
	#    stats admin if TRUE

frontend http-in
	bind :::80 v4v6
	bind :::443 v4v6 alpn h2,http/1.1 ssl crt /etc/ssl/private
	#bind :::443 v4v6 alpn h2,http/1.1 ssl crt /etc/ssl/private crt /data/ssl.d
	# ciphers AES128+EECDH:AES128+EDH

	http-request  set-header X-Forwarded-Proto https if { ssl_fc }
	http-request  set-header X-Forwarded-Port %[dst_port]
	http-response set-header X-Frame-Options sameorigin

	acl is_websocket hdr(Upgrade) -i WebSocket
	acl is_websocket hdr_beg(Host) -i ws
	acl letsencrypt  path_beg -i /.well-known/acme-challenge
	redirect scheme https code 301 if !is_websocket !letsencrypt !{ ssl_fc }

	acl munin        path_beg /munin
	acl nagios       path_beg /nagios
	acl watch        path_beg /watch
	acl haraka       path_beg /haraka
	acl haraka       path_beg /logs
	acl qmailadmin   path_beg /qmailadmin
	acl qmailadmin   path_beg /cgi-bin/qmailadmin
	acl qmailadmin   path_beg /cgi-bin/vqadmin
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
	acl horde        path_beg /horde
	acl prometheus   path_beg /prometheus
	acl grafana      path_beg /grafana

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
	use_backend www_horde        if  horde
	use_backend www_prometheus   if  prometheus
	use_backend www_grafana      if  grafana


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

	backend www_prometheus
	server monitor $(get_jail_ip prometheus):9090
	reqirep ^([^\ :]*)\ /prometheus/(.*)    \1\ /\2

	backend www_grafana
	server monitor $(get_jail_ip grafana):3000
	reqirep ^([^\ :]*)\ /grafana/(.*)    \1\ /\2

EO_HAPROXY_CONF
}

install_ocsp_stapler()
{
	if [ -f "$1" ]; then return; fi

	tee "$1" <<'EO_OCSP'
#!/bin/sh -e

# http://www.jinnko.org/2015/03/ocsp-stapling-with-haproxy.html

# Get an OSCP response from the certificates OCSP issuer for use
# with HAProxy, then reload HAProxy if there have been updates.

OPENSSL=/usr/bin/openssl

# Path to certificates
PEMSDIR=/data/ssl.d

# Path to log output to
LOGDIR=/var/log/haproxy

# Create the log path if it doesn't already exist
[ -d ${LOGDIR} ] || mkdir ${LOGDIR}
UPDATED=0

cd ${PEMSDIR}
for pem in *.pem; do
    echo "= $(date)" >> ${LOGDIR}/${pem}.log

    # Get the OCSP URL from the certificate
    ocsp_url=$($OPENSSL x509 -noout -ocsp_uri -in $pem)

    # Extract the hostname from the OCSP URL
    ocsp_host=$(echo $ocsp_url | cut -d/ -f3)

    # Only process the certificate if we have a .issuer file
    if [ -r ${pem}.issuer ]; then

        # Request the OCSP response from the issuer and store it
        $OPENSSL ocsp \
            -issuer ${pem}.issuer \
            -cert ${pem} \
            -url ${ocsp_url} \
            -header Host ${ocsp_host} \
            -respout ${pem}.ocsp || echo -n ""

        UPDATED=$(( $UPDATED + 1 ))
    fi
done

if [ $UPDATED -gt 0 ]; then
    echo "= $(date) - Updated $UPDATED OCSP responses" >> ${LOGDIR}/${pem}.log
    service haproxy reload > ${LOGDIR}/service-reload.log 2>&1
else
    echo "= $(date) - No updates" >> ${LOGDIR}/${pem}.log
fi

EO_OCSP

	chmod 755 "$1"
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

	if [ ! -d "$STAGE_MNT/usr/local/etc/periodic/daily" ]; then
		mkdir -p "$STAGE_MNT/usr/local/etc/periodic/daily"
	fi
	install_ocsp_stapler "$STAGE_MNT/usr/local/etc/periodic/daily/501.ocsp-staple.sh"
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

	if [ ! -d "$STAGE_MNT/var/run/haproxy" ]; then
		# useful for stats socket
		mkdir "$STAGE_MNT/var/run/haproxy"
	fi

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
