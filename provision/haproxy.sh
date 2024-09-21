#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

install_haproxy()
{
	case "$TLS_LIBRARY" in
		libressl)  install_haproxy_libressl;;
		openssl*)  install_haproxy_openssl;;
		*)	       install_haproxy_pkg;;
	esac

	tell_status "PRO TIP: install hatop for a 'top' style haproxy dashboard"
	#stage_pkg_install hatop
}

install_haproxy_pkg()
{
	tell_status "installing haproxy"
	stage_pkg_install haproxy
}

install_haproxy_openssl()
{
	tell_status "compiling haproxy against openssl $TLS_LIBRARY"
	echo "DEFAULT_VERSIONS+=ssl=$TLS_LIBRARY" >> "$STAGE_MNT/etc/make.conf"
	stage_pkg_install pcre gmake "$TLS_LIBRARY"
	stage_port_install net/haproxy
}

install_haproxy_libressl()
{
	tell_status "compiling haproxy against libressl"
	echo 'DEFAULT_VERSIONS+=ssl=libressl' >> "$STAGE_MNT/etc/make.conf"
	stage_pkg_install pcre gmake libressl
	stage_port_install net/haproxy
}

configure_haproxy_dot_conf()
{
	local _data_cf="$ZFS_DATA_MNT/haproxy/etc/haproxy.conf"

	store_config "$_data_cf" <<EO_HAPROXY_CONF
global
	daemon
	maxconn     256  # Total Max Connections. This is dependent on ulimit
	ssl-default-bind-options no-sslv3 no-tls-tickets
	ssl-dh-param-file /etc/ssl/dhparam.pem
	tune.ssl.default-dh-param 2048
	stats socket :9999 level admin expose-fd listeners

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

#frontend stats
#    bind *:9000
#    stats enable
#    stats uri /haproxy_stats
#    stats realm HAProxy\ Statistics
#    stats auth admin:password
#    stats admin if TRUE

frontend http-in
	#mode tcp
	bind :::80 v4v6 alpn http/1.1
	bind :::443 v4v6 alpn http/1.1 ssl crt /etc/ssl/private crt /data/ssl.d
	# ciphers AES128+EECDH:AES128+EDH

	http-request  set-header X-Forwarded-Proto https if { ssl_fc }
	http-request  set-header X-Forwarded-Port %[dst_port]
	http-response set-header X-Frame-Options sameorigin

	acl is_websocket hdr(Upgrade) -i WebSocket
	acl is_websocket hdr_beg(Host) -i ws
	acl letsencrypt  path_beg -i /.well-known/acme-challenge
	acl letsencrypt  path_beg -i /.well-known/pki-validation
	redirect scheme https code 301 if !is_websocket !letsencrypt !{ ssl_fc }

	acl munin        path_beg /munin
	acl nagios       path_beg /nagios
	acl watch        path_beg /watch
	acl haraka       path_beg /haraka
	acl haraka       path_beg /logs
	acl qmailadmin   path_beg /qmailadmin
	acl qmailadmin   path_beg /cgi-bin/qmailadmin
	acl qmailadmin   path_beg /cgi-bin/vqadmin
	acl qmailadmin   path_beg /images/vqadmin
	acl sqwebmail    path_beg /sqwebmail
	acl sqwebmail    path_beg /cgi-bin/sqwebmail
	acl isoqlog      path_beg /isoqlog
	acl rspamd       path_beg /rspamd
	acl roundcube    path_beg /roundcube
	acl rainloop     path_beg /rainloop
	acl snappymail   path_beg /snappymail
	acl squirrelmail path_beg /squirrelmail
	acl nictool      path_beg /nictool
	acl mediawiki    path_beg /wiki
	acl mediawiki    path_beg /w/
	acl smf          path_beg /smf
	acl wordpress    path_beg /wordpress
	acl stage        path_beg /stage
	acl horde        path_beg /horde
	acl prometheus   path_beg /prometheus
	acl grafana      path_beg /grafana
	acl dmarc        path_beg /dmarc
	acl kibana       path_beg /kibana
	acl zonemta      hdr_beg(host) -i zonemta
	acl wildduck     hdr_beg(host) -i wildduck

	use_backend websocket_haraka if  is_websocket
	use_backend www_webmail      if  letsencrypt

	use_backend www_munin        if  munin
	use_backend www_nagios       if  nagios
	use_backend www_haraka       if  watch
	use_backend www_vpopmail     if  qmailadmin
	use_backend www_sqwebmail    if  sqwebmail
	use_backend www_vpopmail     if  isoqlog
	use_backend www_haraka       if  haraka
	use_backend www_rspamd       if  rspamd
	use_backend www_roundcube    if  roundcube
	use_backend www_rainloop     if  rainloop
	use_backend www_snappymail   if  snappymail
	use_backend www_squirrelmail if  squirrelmail
	use_backend www_nictool      if  nictool
	use_backend www_mediawiki    if  mediawiki
	use_backend www_smf          if  smf
	use_backend www_wordpress    if  wordpress
	use_backend www_stage        if  stage
	use_backend www_horde        if  horde
	use_backend www_prometheus   if  prometheus
	use_backend www_grafana      if  grafana
	use_backend www_dmarc        if  dmarc
	use_backend www_kibana       if  kibana
	use_backend www_zonemta      if  zonemta
	use_backend www_wildduck     if  wildduck

	default_backend www_webmail

	backend www_vpopmail
	server vpopmail $(get_jail_ip vpopmail):80

	backend www_sqwebmail
	server sqwebmail $(get_jail_ip sqwebmail):80

	backend www_haraka
	server haraka $(get_jail_ip haraka):80
	http-request replace-uri /haraka/(.*) /\1

	backend websocket_haraka
	timeout queue 5s
	timeout server 86400s
	timeout connect 86400s
	server haraka $(get_jail_ip haraka):80

	backend www_webmail
	server webmail $(get_jail_ip webmail):80 send-proxy-v2

	backend www_roundcube
	server roundcube $(get_jail_ip roundcube):80 send-proxy-v2
	http-request replace-path /roundcube/(.*) /\1

	backend www_squirrelmail
	server squirrelmail $(get_jail_ip squirrelmail):80 send-proxy-v2

	backend www_rainloop
	server rainloop $(get_jail_ip rainloop):80 send-proxy-v2
	http-request replace-path /rainloop/(.*) /\1

	backend www_snappymail
	server snappymail $(get_jail_ip snappymail):80 send-proxy-v2
	http-response del-header X-Frame-Options

	backend www_munin
	server munin $(get_jail_ip munin):80

	backend www_rspamd
	server rspamd $(get_jail_ip rspamd):11334
	http-request replace-path /rspamd/(.*) /\1

	backend www_nictool
	server nictool $(get_jail_ip nictool):80
	http-request replace-path /nictool/(.*) /\1

	backend www_mediawiki
	server mediawiki $(get_jail_ip mediawiki):80 send-proxy-v2

	backend www_smf
	server smf $(get_jail_ip smf):80 send-proxy-v2

	backend www_wordpress
	server wordpress $(get_jail_ip wordpress):80 send-proxy-v2

	backend www_stage
	server stage $(get_jail_ip stage):80 send-proxy-v2

	backend www_horde
	server horde $(get_jail_ip horde):80 send-proxy-v2

	backend www_prometheus
	server prometheus $(get_jail_ip prometheus):9090
	http-request replace-path /prometheus/(.*) /\1

	backend www_grafana
	server grafana $(get_jail_ip grafana):3000
	http-request replace-path /grafana/(.*) /\1

	backend www_dmarc
	server dmarc $(get_jail_ip mail_dmarc):8080

	backend www_nagios
	server nagios $(get_jail_ip nagios):80 send-proxy-v2

	backend www_kibana
	server kibana $(get_jail_ip elasticsearch):5601
	http-request replace-uri /kibana/(.*) /\1

	backend www_wildduck
	server wildduck 172.16.15.64:3000

	backend www_zonemta
	server zonemta 172.16.15.64:8082

EO_HAPROXY_CONF

	_data_cf="$STAGE_MNT/usr/local/etc/haproxy.conf"

	store_config "$_data_cf" <<EO_HAPROXY_STAGE_CONF
global
    daemon
    log 172.16.15.1 local0 err
    tune.ssl.default-dh-param 2048

defaults
    mode        http
    log         global

frontend default-http
    bind $(get_jail_ip stage):80
    bind $(get_jail_ip stage):443 alpn http/1.1 ssl crt /data/ssl.d
    bind [$(get_jail_ip6 stage)]:80
    bind [$(get_jail_ip6 stage)]:443 alpn http/1.1 ssl crt /data/ssl.d

    default_backend www_webmail

backend www_webmail
    server webmail80 172.16.15.10:80 send-proxy

EO_HAPROXY_STAGE_CONF
}

install_ocsp_stapler()
{
	if [ -f "$1" ]; then return; fi

	store_exec "$1" <<'EO_OCSP'
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
            -header Host=${ocsp_host} \
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
}

configure_haproxy_tls()
{
	if [ ! -f "$STAGE_MNT/etc/ssl/private/server.pem" ]; then
		tell_status "concatenating TLS key and crt to PEM"
		cat /etc/ssl/private/server.key /etc/ssl/certs/server.crt \
			> "$STAGE_MNT/etc/ssl/private/server.pem"
	fi

	if [ ! -d "$ZFS_DATA_MNT/haproxy/ssl" ]; then
		tell_status "creating /data/ssl"
		mkdir -p "$ZFS_DATA_MNT/haproxy/ssl"
	fi

	if [ ! -d "$ZFS_DATA_MNT/haproxy/ssl.d" ]; then
		tell_status "creating /data/ssl.d"
		mkdir -p "$ZFS_DATA_MNT/haproxy/ssl.d"
	fi

	install_ocsp_stapler "$STAGE_MNT/usr/local/etc/periodic/daily/501.ocsp-staple.sh"
}

configure_haproxy()
{
	if [ ! -d "$ZFS_DATA_MNT/haproxy/etc" ]; then
		tell_status "creating /data/etc"
		mkdir -p "$ZFS_DATA_MNT/haproxy/etc"
	fi

	configure_haproxy_dot_conf

	if [ ! -d "$STAGE_MNT/var/run/haproxy" ]; then
		# useful for stats socket
		mkdir "$STAGE_MNT/var/run/haproxy"
	fi

	_pf_etc="$ZFS_DATA_MNT/haproxy/etc/pf.conf.d"
	store_config "$_pf_etc/rdr.conf" <<EO_PF
rdr inet  proto tcp from any to <ext_ip4> port { 80 443 } -> $(get_jail_ip haproxy)
rdr inet6 proto tcp from any to <ext_ip6> port { 80 443 } -> $(get_jail_ip6 haproxy)
EO_PF

	get_public_ip
	get_public_ip ipv6

	store_config "$_pf_etc/allow.conf" <<EO_PF
table <http_servers> { $PUBLIC_IP4 $PUBLIC_IP6 $(get_jail_ip haproxy) $(get_jail_ip6 haproxy) }
pass in quick proto tcp from any to <http_servers> port { 80 443 }
EO_PF

	configure_haproxy_tls
}

start_haproxy()
{
	tell_status "starting haproxy"
	stage_sysrc haproxy_enable=YES

	stage_exec service haproxy start
}

test_haproxy()
{
	tell_status "testing haproxy"
	stage_listening 443
	echo "it worked"

	stage_sysrc haproxy_config="/data/etc/haproxy.conf"
}

base_snapshot_exists || exit
create_staged_fs haproxy
start_staged_jail haproxy
install_haproxy
configure_haproxy
start_haproxy
test_haproxy
promote_staged_jail haproxy
