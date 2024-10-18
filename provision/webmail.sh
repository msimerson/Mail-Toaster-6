#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

mt6-include nginx

configure_nginx_server()
{
	_NGINX_SERVER='
		server_name webmail default_server;
		root /data/htdocs;

		# serve ACME requests from /data
		location /.well-known/acme-challenge {
			try_files $uri =404;
		}

		location /.well-known/pki-validation {
			try_files $uri =404;
		}

		# Forbid access to other dotfiles
		location ~ /\.(?!well-known).* {
			return 403;
		}

		location / {
			# redirect to HTTPS, use with TOASTER_WEBMAIL_PROXY=nginx
			#return 301 https://$server_name$request_uri;
			index  index.html index.htm;
		}
'
	export _NGINX_SERVER
	configure_nginx_server_d webmail

	if [ "$TOASTER_WEBMAIL_PROXY" = "nginx" ]; then
		# shellcheck disable=SC2089
		_NGINX_SERVER="
	server {
		listen	    443 ssl;
		listen [::]:443 ssl;

		server_name  $TOASTER_HOSTNAME;

		ssl_certificate	/data/etc/tls/certs/$TOASTER_HOSTNAME.pem;
		ssl_certificate_key /data/etc/tls/private/$TOASTER_HOSTNAME.pem;

		proxy_set_header X-Forwarded-For \$remote_addr;
		proxy_set_header X-Forwarded-Proto \$scheme;
		proxy_set_header Host \$host;

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
		}

		location /haraka/ {
			rewrite /haraka/(.*) /\$1  break;
			proxy_redirect     off;
			proxy_pass	http://$(get_jail_ip haraka):80;
		}

		location /watch/ {
			proxy_pass	http://$(get_jail_ip haraka):80;
			proxy_http_version 1.1;
			proxy_set_header Upgrade \$http_upgrade;
			proxy_set_header Connection \"upgrade\";
			proxy_read_timeout 86400;
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
			proxy_pass	http://$(get_jail_ip rspamd):11334/;
		}

		location /dmarc {
			proxy_pass	http://$(get_jail_ip mail_dmarc):8080/;
		}

		location / {
			root   /data/htdocs;
			index  index.html index.htm;
		}

		error_page   500 502 503 504  /50x.html;
		location = /50x.html {
			root   /usr/local/www/nginx-dist;
		}
	}
"
		# shellcheck disable=SC2090
		export _NGINX_SERVER

		configure_nginx_server_d webmail webmail-tls
	fi
}

install_lighttpd()
{
	tell_status "installing lighttpd"
	stage_pkg_install lighttpd

	mkdir -p "$STAGE_MNT/var/spool/lighttpd/sockets"
	chown -R www "$STAGE_MNT/var/spool/lighttpd/sockets"
}

configure_lighttpd()
{
	local _lighttpd_dir="$STAGE_MNT/usr/local/etc/lighttpd"
	local _lighttpd_conf="$_lighttpd_dir/lighttpd.conf"

	# shellcheck disable=2016
	sed -i.bak \
		-e 's/^#include_shell "cat/include_shell "cat/' \
		-e '/^var.server_root/ s/\/usr\/local\/www\/data/\/data\/htdocs/' \
		"$_lighttpd_conf"

	store_config "$_lighttpd_dir/vhosts.d/mail-toaster.conf" <<EO_LIGHTTPD_MT6
server.modules += ( "mod_alias" )

alias.url = (
		"/cgi-bin/"        => "/usr/local/www/cgi-bin/",
	)

server.modules += (
		"mod_cgi",
		"mod_fastcgi",
		"mod_extforward",
	)

\$HTTP["url"] =~ "^/awstats/" {
   cgi.assign = ( "" => "/usr/bin/perl" )
}
\$HTTP["url"] =~ "^/cgi-bin" {
   cgi.assign = ( "" => "" )
}
extforward.forwarder = (
		"$(get_jail_ip haproxy)" => "trust",
	)

EO_LIGHTTPD_MT6
}

install_webmail()
{
	if [ "$WEBMAIL_HTTPD" = "lighttpd" ]; then
		install_lighttpd
	else
		install_nginx

		if [ "$TOASTER_WEBMAIL_PROXY" = "nginx" ]; then
			stage_setup_tls
		fi

		configure_nginx_server
	fi
}

install_index()
{
	store_config "$_htdocs/index.html" "overwrite" <<'EO_INDEX'
<html>
<head>
 <script src="//code.jquery.com/jquery-3.6.2.min.js"></script>
 <script src="//code.jquery.com/ui/1.13.2/jquery-ui.min.js"></script>
 <link rel="stylesheet" href="//code.jquery.com/ui/1.13.2/themes/smoothness/jquery-ui.css" />
 <script>
  let loggedIn = false;
  $(function() {
    $( "#tabs" ).tabs({ disabled: [3] });
  });
  const webPaths = {
    'webmail'     : '',
    'roundcube'   : '/roundcube/',
    'snappymail'  : '/snappymail/',
    // 'rainloop'    : '/rainloop/',
    // 'sqwebmail'   : '/cgi-bin/sqwebmail?index=1',
    // 'squirrelmail': '/squirrelmail/src/webmail.php',
  }
  const adminPaths = {
    'admin'     : '',
    'qmailadmin': '/cgi-bin/qmailadmin/qmailadmin/',
    'rspamd'    : '/rspamd/',
    'watch'     : '/watch/',
    'snappymail': '/snappymail/?admin',
    // 'rainloop'  : '/rainloop/?admin',
  }
  const statsPaths = {
    'statistics': '',
    'munin'     : '/munin/',
    'nagios'    : '/nagios/',
    'watch'     : '/watch/',
    'grafana'   : '/grafana/',
  }
  function changeWebmail(sel) {
    if (!sel || !sel.value) return;
    $('#webmail-item').prop('src', webPaths[sel.value]);
    $('#tabs').tabs({ active: [0] });
  }
  function changeAdmin(sel) {
    if (!sel || !sel.value) return;
    $('#admin-item').prop('src', adminPaths[sel.value]);
    $('#tabs').tabs({ active: [1] });
  }
  function changeStats(sel) {
    if (!sel || !sel.value) return;
    $('#stats-item').prop('src', statsPaths[sel.value]);
    $('#tabs').tabs({ active: [2] });
  }
  function checkSuccess(tab, w) {
    if ($(`#${tab}-select option[value=${w}]`).length > 0) {
      // console.log(`${w} success, present, no action`)
    }
    else {
      // console.log(`${w} success, missing, adding`)
      $(`#${tab}-select`).append(`<option value="${w}">${w}</option>`);
    }
  }
  function checkFail(tab, w) {
    if ($(`#${tab}-select option[value=${w}]`).length > 0) {
      // console.log(`${w} not responding, present, removing`)
      $(`#${tab}-select option[value=${w}]`).remove();
    }
    else {
      // console.log(`${w} not responding,  missing, no action`)
    }
  }
  function checkWebmail() {
    for (const w in webPaths) {
      if (w === 'webmail') continue
      $.ajax({
        url: `${webPaths[w]}`,
        success: (data) => { checkSuccess('webmail', w); },
        timeout: 3000,
      })
      .fail(() => { checkFail('webmail', w); })
    }
  }
  function checkAdmin() {
    for (const w in adminPaths) {
      if (w === 'admin') continue
      $.ajax({
        url: `${adminPaths[w]}`,
        success: (data) => { checkSuccess('admin', w); },
        timeout: 3000,
      })
      .fail(() => { checkFail('admin', w); })
    }
  }
  function checkStats() {
    for (const w in statsPaths) {
      if (w === 'statistics') continue
      $.ajax({
        url: `${statsPaths[w]}`,
        success: (data) => { checkSuccess('stats', w); },
        timeout: 3000,
      })
      .fail(() => { checkFail('stats', w); })
    }
  }
  function checkAll () {
    checkWebmail();
    checkAdmin();
    checkStats();
  }
  </script>
  <style>body { font-size: 9pt; }</style>
</head>
<body onLoad="checkAll()">
<div id="tabs">
   <ul>
       <li id=tab_webmail><a href="#webmail">
           <select id="webmail-select" onChange="changeWebmail(this);">
               <option value=webmail>Webmail</option>
               <option value=roundcube>Roundcube</option>
               <option value=snappymail>Snappymail</option>
               <!--<option value=squirrelmail>Squirrelmail</option>-->
               <!--<option value=rainloop>Rainloop</option>-->
               <!--<option value=sqwebmail>Sqwebmail</option>-->
           </select>
       </a>
       </li>
       <li id=tab_admin><a href="#admin">
           <select id="admin-select" onChange="changeAdmin(this)">
               <option value=admin>Administration</option>
               <option value=qmailadmin>Qmailadmin</option>
               <option value=rspamd>Rspamd</option>
               <option value=watch>Haraka Watch</option>
               <option value=snappymail>Snappymail Admin</option>
               <!--<option value=rainloop>Rainloop Admin</option>-->
           </select>
       </a>
       </li>
       <li id=tab_stats><a href="#stats">
           <select id="stats-select" onChange="changeStats(this)">
               <option value=statistics>Statistics</option>
               <option value=munin>Munin</option>
               <option value=nagios>Nagios</option>
               <option value=watch>Haraka Watch</option>
               <option value=grafana>Grafana</option>
           </select>
       </a>
       </li>
       <!--<li><a href="#help">Help</a> </li>-->
       <li><a href="#login">Login</a></li>
   </ul>
 <div id="webmail">
     <iframe id="webmail-item" src="" style="width: 100%; height: 100%;"></iframe>
 </div>
 <div id="admin">
     <iframe id="admin-item" src="" style="width: 100%; height: 100%;"></iframe>
 </div>
 <div id="stats">
     <iframe id="stats-item" src="" style="width: 100%; height: 100%;"></iframe>
 </div>
 <div id="login">
     <fieldset>
         <legend>Login</legend>
         <input type=text id=login placeholder="user@domain.com"></input>
         <input type=password id=password></input>
     </fieldset>
 </div>
<!-- <div id="help">
  <p>Help</p>
 </div>-->
</div>
</body>
</html>
EO_INDEX
}

configure_webmail_pf()
{
	_pf_etc="$ZFS_DATA_MNT/webmail/etc/pf.conf.d"

	if [ "$TOASTER_WEBMAIL_PROXY" = "nginx" ]; then
		store_config "$_pf_etc/rdr.conf" <<EO_HTTP_RDR
int_ip4 = "$(get_jail_ip webmail)"
int_ip6 = "$(get_jail_ip6 webmail)"

rdr inet  proto tcp from any to <ext_ip4> port { 80 443 } -> \$int_ip4
rdr inet6 proto tcp from any to <ext_ip6> port { 80 443 } -> \$int_ip6
EO_HTTP_RDR
	fi

	store_config "$_pf_etc/allow.conf" <<EO_HTTP_ALLOW
int_ip4 = "$(get_jail_ip webmail)"
int_ip6 = "$(get_jail_ip6 webmail)"

table <webmail_int> persist { \$int_ip4, \$int_ip6 }

pass in quick proto tcp from any to <ext_ip> port { 80 443 }
pass in quick proto tcp from any to <webmail_int> port { 80 443 }
EO_HTTP_ALLOW
}

configure_webmail()
{
	if [ "$WEBMAIL_HTTPD" = "lighttpd" ]; then
		configure_lighttpd
	else
		configure_nginx webmail
		configure_nginx_server
	fi

	configure_webmail_pf

	_data="$ZFS_DATA_MNT/webmail"
	_htdocs="$_data/htdocs"
	if [ ! -d "$_htdocs" ]; then
	   mkdir -p "$_htdocs"
	fi

	if [ -f "$_htdocs/index.html" ]; then
		tell_status "backing up index.html"
		cp "$_htdocs/index.html" "$_htdocs/index.html-$(date +%Y.%m.%d)"
	fi
	install_index

	if [ ! -f "$_htdocs/robots.txt" ]; then
		store_config "$_htdocs/robots.txt" <<EO_ROBOTS_TXT
User-agent: *
Disallow: /
EO_ROBOTS_TXT
	fi
}

start_webmail()
{
	if [ "$WEBMAIL_HTTPD" = "lighttpd" ]; then
		tell_status "starting lighttpd"
		stage_sysrc lighttpd_enable=YES
		stage_exec service lighttpd start
	else
		start_nginx
	fi
}

test_webmail()
{
	tell_status "testing webmail httpd"
	stage_listening 80
}

base_snapshot_exists || exit
create_staged_fs webmail
start_staged_jail webmail
install_webmail
configure_webmail
start_webmail
test_webmail
promote_staged_jail webmail
