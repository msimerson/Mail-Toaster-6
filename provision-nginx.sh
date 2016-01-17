#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

install_nginx()
{
	stage_pkg_install nginx dialog4ports || exit

	tell_status "building nginx with HTTP_REALIP option"
	export BATCH=${BATCH:="1"}
	stage_make_conf www_nginx 'www_nginx_SET=HTTP_REALIP'
	stage_exec make -C /usr/ports/www/nginx build deinstall install clean
}

configure_nginx()
{
	local _nginx_conf="$STAGE_MNT/usr/local/etc/nginx/conf.d"
	mkdir -p "$_nginx_conf" || exit

	tee "$_nginx_conf/mail-toaster.conf" <<EO_NGINX_MT6
set_real_ip_from $(get_jail_ip haproxy);
real_ip_header X-Forwarded-For;

location ~  ^/squirrelmail/(.+\.php)$ {
    alias /usr/local/www;
    fastcgi_pass   $(get_jail_ip squirrelmail):9000;
    fastcgi_index  index.php;
    fastcgi_param  SCRIPT_FILENAME  \$document_root/\$1/\$2;
    include        fastcgi_params;
}

location /squirrelmail/ {
    root /usr/local/www/;
    index  index.php;
}

location ~  ^/roundcube/(.+\.php)$ {
    alias /usr/local/www;
    fastcgi_pass   $(get_jail_ip roundcube):9000;
    fastcgi_index  index.php;
    fastcgi_param  SCRIPT_FILENAME  \$document_root/\$1/\$2;
    include        fastcgi_params;
}

location /roundcube/ {
    root /usr/local/www/;
    index  index.php;
}
EO_NGINX_MT6

	patch -d "$STAGE_MNT/usr/local/etc/nginx" <<'EO_NGINX_CONF'
--- nginx.conf-dist     2016-01-16 15:02:13.343163000 -0800
+++ nginx.conf  2016-01-16 15:05:00.651156640 -0800
@@ -34,7 +34,7 @@
 
     server {
         listen       80;
-        server_name  localhost;
+        server_name  nginx;
 
         #charset koi8-r;
 
@@ -45,6 +45,8 @@
             index  index.html index.htm;
         }
 
+        include conf.d/mail-toaster.conf;
+
         #error_page  404              /404.html;
 
         # redirect server error pages to the static page /50x.html

EO_NGINX_CONF

}

install_mt_index()
{
	tee "$STAGE_MNT/usr/local/www/nginx/index.html" <<'EO_INDEX'
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
      if (sel.value === 'squirrelmail') $('#webmail-item').prop('src','/squirrelmail/');
      console.log(sel);
  };
  function changeAdmin(sel) {
      if (sel.value === 'qmailadmin') $('#admin-item').prop('src','/cgi-bin/qmailadmin/qmailadmin/');
      if (sel.value === 'rspamd') $('#admin-item').prop('src','/rspamd/');
      if (sel.value === 'watch') $('#admin-item').prop('src','/watch/');
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
               <option value=squirrelmail>Squirrelmail</option>
           </select>
       </a>
       </li>
       <li id=tab_admin><a href="#admin">
           <select onChange="changeAdmin(this)">
               <option value=admin>Administration</option>
               <option value=qmailadmin>Qmailadmin</option>
               <option value=rspamd>Rspamd</option>
               <option value=watch>Haraka Watch</option>
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

	fetch -o "$STAGE_MNT/usr/local/etc/mime.types" \
		http://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types
}

start_nginx()
{
	tell_status "starting nginx"
	stage_sysrc nginx_enable=YES
	stage_exec service nginx start
}

test_nginx()
{
	tell_status "testing nginx"
	stage_exec sockstat -l -4 | grep :80 || exit
	stage_exec sockstat -l -4 | grep :443 || exit
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs nginx
start_staged_jail
install_nginx
configure_nginx
install_mt_index
start_nginx
test_nginx
promote_staged_jail nginx
