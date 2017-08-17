#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
# shellcheck disable=2016
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
	sed -i .bak \
		-e 's/server.use-ipv6 = "enable"/server.use-ipv6 = "disable"/' \
		-e 's/^\$SERVER\["socket"\]/#\$SERVER\["socket"\]/' \
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

$HTTP["url"] =~ "^/awstats/" {
   cgi.assign = ( "" => "/usr/bin/perl" )
}
$HTTP["url"] =~ "^/cgi-bin" {
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
 <script src="//ajax.googleapis.com/ajax/libs/jquery/1.11.1/jquery.min.js"></script>
 <script src="//ajax.googleapis.com/ajax/libs/jqueryui/1.11.0/jquery-ui.min.js"></script>
 <link rel="stylesheet" href="//ajax.googleapis.com/ajax/libs/jqueryui/1.11.0/themes/smoothness/jquery-ui.css" />
 <script>
  var loggedIn = false;
  $(function() {
    $( "#tabs" ).tabs({ disabled: [3] });
  });
  function changeWebmail(sel) {
      if (sel.value === 'roundcube') $('#webmail-item').prop('src','/roundcube/');
      if (sel.value === 'rainloop') $('#webmail-item').prop('src','/rainloop/');
      if (sel.value === 'squirrelmail') $('#webmail-item').prop('src','/squirrelmail/');
      if (sel.value === 'sqwebmail') $('#webmail-item').prop('src','/cgi-bin/sqwebmail?index=1');
      console.log(sel);
  };
  function changeAdmin(sel) {
      if (sel.value === 'qmailadmin') $('#admin-item').prop('src','/cgi-bin/qmailadmin/qmailadmin/');
      if (sel.value === 'rspamd') $('#admin-item').prop('src','/rspamd/');
      if (sel.value === 'watch') $('#admin-item').prop('src','/watch/');
      if (sel.value === 'rainloop') $('#admin-item').prop('src','/rainloop/?admin');
  };
  function changeStats(sel) {
      if (sel.value === 'munin') $('#stats-item').prop('src','/munin/');
      if (sel.value === 'nagios') $('#stats-item').prop('src','/nagios/');
      if (sel.value === 'watch') $('#stats-item').prop('src','/watch/');
  };
  </script>
  <style>
body {
  font-size: 9pt;
}
  </style>
</head>
<body>
<div id="tabs">
   <ul>
       <li id=tab_webmail><a href="#webmail">
           <select id="webmail-select" onChange="changeWebmail(this);">
               <option value=webmail>Webmail</option>
               <option value=roundcube>Roundcube</option>
               <option value=rainloop>Rainloop</option>
               <option value=squirrelmail>Squirrelmail</option>
               <option value=sqwebmail>Sqwebmail</option>
           </select>
       </a>
       </li>
       <li id=tab_admin><a href="#admin">
           <select onChange="changeAdmin(this)">
               <option value=admin>Administration</option>
               <option value=qmailadmin>Qmailadmin</option>
               <option value=rspamd>Rspamd</option>
               <option value=watch>Haraka Watch</option>
               <option value=rainloop>Rainloop Admin</option>
           </select>
       </a>
       </li>
       <li id=tab_stats><a href="#stats">
           <select onChange="changeStats(this)">
               <option value=statistics>Statistics</option>
               <option value=munin>Munin</option>
               <option value=nagios>Nagios</option>
               <option value=watch>Haraka</option>
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

	if [ ! -f "$_htdocs/index.html" ]; then
		install_index
	fi

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
