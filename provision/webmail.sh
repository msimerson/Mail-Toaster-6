#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

mt6-include nginx

configure_nginx_server_port_80()
{
	if [ "$TOASTER_WEBMAIL_PROXY" = "nginx" ]; then
		# nginx terminates TLS; ACME intercepts challenges internally,
		# redirect all else to HTTPS
		_NGINX_SERVER="
		server_name $TOASTER_HOSTNAME default_server;

		location / {
			return 301 https://\$server_name\$request_uri;
		}"
	else
		# haproxy terminates TLS; nginx on port 80
		_NGINX_SERVER="
		server_name $TOASTER_HOSTNAME default_server;
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

		location / {
			index  index.html index.htm;
		}"
	fi
	export _NGINX_SERVER
	configure_nginx_server_d webmail
}

configure_nginx_server_port_443()
{
	if [ "$TOASTER_WEBMAIL_PROXY" != "nginx" ]; then return; fi

	local _NGINX_SERVER='
	server {
		listen      443 ssl;'

	if [ -n "$PUBLIC_IP6" ]; then
		_NGINX_SERVER="$_NGINX_SERVER
		listen [::]:443 ssl;"
	fi

	_NGINX_SERVER="$_NGINX_SERVER

		server_name $TOASTER_HOSTNAME;"

	if [ "$TOASTER_NGINX_ACME" = "1" ]; then
		_NGINX_SERVER="$_NGINX_SERVER
		acme_certificate      letsencrypt;

		ssl_certificate       \$acme_certificate;
		ssl_certificate_key   \$acme_certificate_key;
		ssl_certificate_cache max=2;"
	else
		_NGINX_SERVER="$_NGINX_SERVER
		ssl_certificate	/data/etc/tls/certs/$TOASTER_HOSTNAME.pem;
		ssl_certificate_key /data/etc/tls/private/$TOASTER_HOSTNAME.pem;"
	fi

	_NGINX_SERVER="$_NGINX_SERVER

		include /data/etc/nginx/webmail.conf;
	}"

	export _NGINX_SERVER
	configure_nginx_server_d webmail $TOASTER_HOSTNAME
}

configure_nginx_server()
{
	get_public_ip6

	configure_nginx_server_port_80
	configure_nginx_server_port_443

	tee "$ZFS_DATA_MNT/webmail/etc/nginx/webmail.conf" <<EO_WEBMAIL_INCLUDE
		proxy_set_header X-Forwarded-For \$remote_addr;
		proxy_set_header X-Forwarded-Proto \$scheme;
		proxy_set_header Host \$host;

		add_header X-XSS-Protection "1; mode=block" always;
		add_header X-Content-Type-Options "nosniff" always;
		add_header X-Frame-Options "SAMEORIGIN" always;
		add_header Referrer-Policy "strict-origin-when-cross-origin" always;
		add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' wss: ws:; frame-ancestors 'self';" always;

		# Forbid access to other dotfiles
		location ~ /\.(?!well-known).* {
			return 403;
		}

		location ~ /\.ht {
			deny  all;
		}

		location /roundcube {
			rewrite /roundcube/(.*) /\$1  break;
			proxy_redirect     off;
			proxy_pass         http://$(get_jail_ip roundcube):80;
		}

		location /snappymail {
			proxy_pass	http://$(get_jail_ip snappymail):80;
			proxy_hide_header X-Frame-Options;
		}

		location /afterlogic {
			proxy_pass	http://$(get_jail_ip afterlogic):80;
			proxy_hide_header X-Frame-Options;
		}

		location /haraka/ {
			include /data/etc/nginx/protected.conf;
			rewrite /haraka/(.*) /\$1  break;
			proxy_redirect     off;
			proxy_pass	http://$(get_jail_ip haraka):80;
		}

		location /watch {
			include /data/etc/nginx/protected.conf;
			proxy_pass	http://$(get_jail_ip haraka):80;

			proxy_http_version 1.1;
			proxy_set_header Upgrade \$http_upgrade;
			proxy_set_header Connection \$connection_upgrade;

			proxy_read_timeout 86400;
			proxy_send_timeout 86400;
		}

		location /logs/ {
			proxy_pass	http://$(get_jail_ip haraka):80;
		}

		location ~ /(qmailadmin|vqadmin) {
			proxy_pass	http://$(get_jail_ip vpopmail):80;
		}

		location /images/mt {
			proxy_pass	http://$(get_jail_ip vpopmail):80;
		}

		location ~ /sqwebmail {
			proxy_pass	http://$(get_jail_ip sqwebmail):80;
		}

		location /rspamd/ {
			include /data/etc/nginx/protected.conf;
			proxy_pass	http://$(get_jail_ip rspamd):11334/;
		}

		location /dmarc {
			include /data/etc/nginx/protected.conf;
			proxy_pass	http://$(get_jail_ip mail_dmarc):8080/;
		}

		location /munin {
			include /data/etc/nginx/protected.conf;
			proxy_pass	http://$(get_jail_ip munin):80;
		}

		location /nagios {
			include /data/etc/nginx/protected.conf;
			proxy_pass	http://$(get_jail_ip nagios):80;
		}

		location /squirrelmail {
			proxy_pass	http://$(get_jail_ip squirrelmail):80;
		}

		location /rainloop {
			rewrite /rainloop/(.*) /\$1  break;
			proxy_redirect     off;
			proxy_pass         http://$(get_jail_ip rainloop):80;
		}

		location /nictool {
			rewrite /nictool/(.*) /\$1  break;
			proxy_redirect     off;
			proxy_pass         http://$(get_jail_ip nictool):80;
		}

		location /wiki {
			proxy_pass	http://$(get_jail_ip mediawiki):80;
		}

		location /w/ {
			proxy_pass	http://$(get_jail_ip mediawiki):80;
		}

		location /smf {
			proxy_pass	http://$(get_jail_ip smf):80;
		}

		location /wordpress {
			proxy_pass	http://$(get_jail_ip wordpress):80;
		}

		location /stage {
			proxy_pass	http://$(get_jail_ip stage):80;
		}

		location /horde {
			proxy_pass	http://$(get_jail_ip horde):80;
		}

		location /prometheus {
			include /data/etc/nginx/protected.conf;
			rewrite /prometheus/(.*) /\$1  break;
			proxy_redirect     off;
			proxy_pass         http://$(get_jail_ip prometheus):9090;
		}

		location /grafana {
			include /data/etc/nginx/protected.conf;
			rewrite /grafana/(.*) /\$1  break;
			proxy_redirect     off;
			proxy_pass         http://$(get_jail_ip grafana):3000;
		}

		location /kibana {
			include /data/etc/nginx/protected.conf;
			rewrite /kibana/(.*) /\$1  break;
			proxy_redirect     off;
			proxy_pass         http://$(get_jail_ip elasticsearch):5601;
		}

		location /zonemta {
			rewrite /zonemta/(.*) /\$1  break;
			proxy_pass         http://$(get_jail_ip zonemta):8082;
			proxy_set_header   Host \$host;
			proxy_set_header   X-Forwarded-For \$remote_addr;
			proxy_set_header   X-Forwarded-Proto \$scheme;
		}

		location /wildduck {
			rewrite /wildduck/(.*) /\$1  break;
			proxy_pass         http://$(get_jail_ip wildduck):3000;
			proxy_set_header   Host \$host;
			proxy_set_header   X-Forwarded-For \$remote_addr;
			proxy_set_header   X-Forwarded-Proto \$scheme;
		}

		# Auth probe (fetch): validate credentials but return bare 401 so
		# browsers don't pop a credential dialog for background requests.
		location = /auth-check {
			include /data/etc/nginx/protected.conf;
			error_page 401 =401 @auth_check_silent;
			return 204;
		}
		location @auth_check_silent { internal; return 401; }

		# Auth login: on success return a page that sets a session cookie
		# and navigates to /. No redirect — avoids credential-cache
		# confusion that causes brief dialog flashes after auth.
		location = /auth-login {
			include /data/etc/nginx/protected.conf;
			default_type text/html;
			return 200 '<html><script>document.cookie="is_admin=1;Path=/;SameSite=Strict;Secure";location.replace("/")</script></html>';
		}

		location / {
			root   /data/htdocs;
			index  index.html index.htm;
		}

		error_page   500 502 503 504  /50x.html;
		location = /50x.html {
			root   /usr/local/www/nginx-dist;
		}
EO_WEBMAIL_INCLUDE
}

configure_nginx_auth()
{
	local _etc="$ZFS_DATA_MNT/webmail/etc/nginx"

	store_config "$_etc/protected.conf" <<'EO_PROTECTED'
# Routes that include this file require a valid login unless the client IP
# is explicitly allowed below.  Edit and reload nginx to apply changes:
#   service nginx reload
#
# To bypass auth for a trusted network, add:
#   allow  192.0.2.0/24;
#
# To remove auth from a route, delete its include line in webmail.conf.
#
# manage password entries with:
#   htpasswd /data/etc/nginx/.htpasswd <username>

satisfy any;
allow   127.0.0.1;
allow   ::1;
deny    all;

auth_basic           "Restricted";
auth_basic_user_file /data/etc/nginx/.htpasswd;
EO_PROTECTED

	# Create an empty htpasswd file so nginx starts without errors.
	if [ ! -f "$_etc/.htpasswd" ]; then
		store_config "$_etc/.htpasswd" <<EO_HTPASSWD
# Add password entries with:
#   htpasswd /data/etc/nginx/.htpasswd <username>
EO_HTPASSWD
		chown 0:80 "$_etc/.htpasswd"
		chmod 640 "$_etc/.htpasswd"
	fi

	store_exec "$STAGE_MNT/usr/local/bin/htpasswd" <<'EO_HTPASSWD'
#!/bin/sh

usage() {
  cat <<EOF
Usage: $0 <htpasswd-file> <username>
EOF
}

if [ $# -eq 2 ]; then
  printf "%s:%s\n" "$2" "$(openssl passwd -6)" >> "$1"
else
  usage
fi
EO_HTPASSWD
}

configure_nginx_acme()
{
	if [ "$TOASTER_NGINX_ACME" != "1" ]; then return; fi

	local _conf="$ZFS_DATA_MNT/webmail/etc/nginx/nginx.conf"
	local _acme_conf="$ZFS_DATA_MNT/webmail/etc/nginx/server.d/acme.conf"

	if [ -f "$_acme_conf" ]; then
		tell_status "preserving $_acme_conf"
		return
	fi

	tell_status "configuring ACME module"

	sed_inplace -e '/ngx_http_acme_module.so/ s/^# //;' "$_conf"

	mkdir -p "$ZFS_DATA_MNT/webmail/etc/acme/letsencrypt"

	store_config "$_acme_conf" <<EO_NGINX_ACME
	resolver $(get_jail_ip dns) valid=60s;

	acme_shared_zone zone=ngx_acme_shared:1M;

	acme_issuer letsencrypt {
		uri        https://acme-v02.api.letsencrypt.org/directory;
		contact    $TOASTER_ADMIN_EMAIL;
		state_path /data/etc/acme/letsencrypt;
		accept_terms_of_service;
	}
EO_NGINX_ACME
}

install_webmail()
{
	stage_setup_tls
	install_nginx
	configure_nginx_server
}

configure_webmail_pf()
{
	_pf_etc="$ZFS_DATA_MNT/webmail/etc/pf.conf.d"

	if [ "$TOASTER_WEBMAIL_PROXY" = "nginx" ]; then
		store_config "$_pf_etc/rdr.conf" <<EO_WEBMAIL_RDR
int_ip4 = "$(get_jail_ip webmail)"
int_ip6 = "$(get_jail_ip6 webmail)"

rdr inet  proto tcp from any to <ext_ip4> port { 80 443 } -> \$int_ip4
rdr inet6 proto tcp from any to <ext_ip6> port { 80 443 } -> \$int_ip6
EO_WEBMAIL_RDR
	fi

	get_public_ip4
	get_public_ip6

	store_config "$_pf_etc/webmail.table" <<EO_WEBMAIL_TABLE
$PUBLIC_IP4
$PUBLIC_IP6
$(get_jail_ip webmail)
$(get_jail_ip6 webmail)
EO_WEBMAIL_TABLE

	store_config "$_pf_etc/filter.conf" <<EO_WEBMAIL_FILTER
pass in quick proto tcp from any to <webmail> port { 80 443 }
EO_WEBMAIL_FILTER
}

configure_webmail()
{
	configure_nginx webmail
	configure_nginx_server

	if [ "$TOASTER_WEBMAIL_PROXY" = "nginx" ]; then
		configure_nginx_acme
		configure_nginx_auth
	fi

	configure_webmail_pf

	_data="$ZFS_DATA_MNT/webmail"
	_htdocs="$_data/htdocs"
	if [ ! -d "$_htdocs/img" ]; then mkdir -p "$_htdocs/img"; fi

	if [ -f "$_htdocs/index.html" ]; then
		tell_status "backing up index.html"
		cp "$_htdocs/index.html" "$_htdocs/index.html-$(date +%Y.%m.%d)"
	fi

	for _f in index.html mt.js style.css img/snappymail.png img/roundcube.png img/qmailadmin.png; do
		fetch -o "$_htdocs/$_f" "$TOASTER_SRC_URL/htdocs/$_f"
	done

	if [ ! -f "$_htdocs/robots.txt" ]; then
		store_config "$_htdocs/robots.txt" <<EO_ROBOTS_TXT
User-agent: *
Disallow: /
EO_ROBOTS_TXT
	fi
}

start_webmail()
{
	tell_status "starting nginx"
	stage_sysrc nginx_enable=YES
	stage_exec service nginx start
}

test_webmail()
{
	tell_status "testing webmail httpd"
	stage_listening 80

	if [ "$TOASTER_WEBMAIL_PROXY" = "nginx" ]; then
		stage_listening 443
	fi
}

base_snapshot_exists || exit
create_staged_fs webmail
start_staged_jail webmail
install_webmail
configure_webmail
start_webmail
test_webmail
promote_staged_jail webmail
