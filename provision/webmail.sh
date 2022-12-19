#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include nginx

configure_nginx_server()
{
	local _nginx_conf="$STAGE_MNT/usr/local/etc/nginx/conf.d"
	mkdir -p "$_nginx_conf" || exit

	local _datadir="$ZFS_DATA_MNT/webmail"
	if [ -f "$_datadir/etc/nginx-locations.conf" ]; then
		tell_status "preserving /data/etc/nginx-locations.conf"
		return
	fi

	tell_status "saving /data/etc/nginx-locations.conf"
	tee "$_datadir/etc/nginx-locations.conf" <<'EO_NGINX_SERVER'

	server_name  webmail;

	location / {
		root   /data/htdocs;
		index  index.html index.htm;
	}

EO_NGINX_SERVER

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

	tee "$_lighttpd_dir/vhosts.d/mail-toaster.conf" <<EO_LIGHTTPD_MT6
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
		install_lighttpd || exit
	else
		install_nginx || exit
	fi
}

install_index()
{
	tell_status "installing index.html"
	tee "$_htdocs/index.html" <<'EO_INDEX'
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
    'rainloop'    : '/rainloop/',
    'roundcube'   : '/roundcube/',
    'snappymail'  : '/snappymail/',
    'sqwebmail'   : '/cgi-bin/sqwebmail?index=1',
    'squirrelmail': '/squirrelmail/',
  }
  const adminPaths = {
    'admin'     : '',
    'qmailadmin': '/cgi-bin/qmailadmin/qmailadmin/',
    'rspamd'    : '/rspamd/',
    'watch'     : '/watch/',
    'rainloop'  : '/rainloop/?admin',
    'snappymail': '/snappymail/?admin',
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
  <style>
body {
  font-size: 9pt;
}
  </style>
</head>
<body onLoad="checkAll()">
<div id="tabs">
   <ul>
       <li id=tab_webmail><a href="#webmail">
           <select id="webmail-select" onChange="changeWebmail(this);">
               <option value=webmail>Webmail</option>
               <option value=roundcube>Roundcube</option>
               <option value=snappymail>Snappymail</option>
               <option value=squirrelmail>Squirrelmail</option>
               <option value=rainloop>Rainloop</option>
               <option value=sqwebmail>Sqwebmail</option>
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
               <option value=rainloop>Rainloop Admin</option>
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

configure_webmail()
{
	if [ "$WEBMAIL_HTTPD" = "lighttpd" ]; then
		configure_lighttpd || exit
	else
		configure_nginx webmail || exit
		configure_nginx_server
	fi

	_htdocs="$ZFS_DATA_MNT/webmail/htdocs"
	if [ ! -d "$_htdocs" ]; then
	   mkdir -p "$_htdocs"
	fi

	if [ -f "$_htdocs/index.html" ]; then
		tell_status "backing up index.html"
		cp "$_htdocs/index.html" "$_htdocs/index.html-$(date +%Y.%m.%d)"
	fi
	install_index

	if [ ! -f "$_htdocs/robots.txt" ]; then
		tell_status "installing robots.txt"
		tee "$_htdocs/robots.txt" <<EO_ROBOTS_TXT
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
