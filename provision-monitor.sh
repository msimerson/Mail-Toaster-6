#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_monitor()
{
	tell_status "installing swaks"
	stage_pkg_install swaks p5-Net-SSLeay || exit


	install_lighttpd
	install_nagios
	install_munin
}

install_lighttpd()
{
	tell_status "installing lighttpd"
	stage_pkg_install lighttpd

	mkdir -p "$STAGE_MNT/var/spool/lighttpd/sockets"
	chown -R www "$STAGE_MNT/var/spool/lighttpd/sockets"
}

install_nagios()
{
	if [ -z "$TOASTER_NRPE" ]; then
		echo "TOASTER_NRPE unset, skipping nagios install"
		return
	fi

	tell_status "installing nagios & nrpe"
	stage_pkg_install nagios nrpe-ssl
}

install_munin()
{
	if [ -z "$TOASTER_MUNIN" ]; then
		echo "TOASTER_MUNIN unset, skipping munin install"
		return
	fi

	tell_status "installing munin"
	stage_pkg_install munin-node munin-master
}

configure_lighttpd()
{
	local _lighttpd_dir="$STAGE_MNT/usr/local/etc/lighttpd"
	local _lighttpd_conf="$_lighttpd_dir/lighttpd.conf"

	# shellcheck disable=2016
	sed -i .bak \
		-e '/^var\.server_root/ s/""/"\/usr\/local\/www"/' \
		-e '/^var\.log_root/ s/""/"\/var\/log\/lighttpd"/' \
		-e '/^server\.username/ s/""/"www"/' \
		-e '/^server\.groupname/ s/""/"www"/' \
		-e '/^server\.use-ipv6/ s/"enable"/"disable"/' \
		-e '/^$SERVER/ s/$S/#$S/' \
		"$_lighttpd_conf"

	tee -a "$_lighttpd_conf" <<EO_LIGHTTPD_MT6

server.modules += (
		"mod_alias",
		"mod_rewrite",
		"mod_fastcgi",
		"mod_extforward",
	)

alias.url += ( "/munin-static" => "/usr/local/www/munin/static" )
alias.url += ( "/munin"        => "/usr/local/www/munin/" )

fastcgi.server += (
	"/munin-cgi/munin-cgi-graph" =>
		( "munin-cgi-graph" => (
			"bin-path"    => "/usr/local/www/cgi-bin/munin-cgi-graph",
			"socket"      => "/var/spool/lighttpd/sockets/munin-cgi-graph.sock", 
			"bin-copy-environment" => ("PATH", "SHELL", "USER"),
			"check-local" => "disable",
			"broken-scriptfilename" => "enable",
		)),
	"/munin-cgi/munin-cgi-html" =>
		( "munin-cgi-html" => (
			"bin-path"    => "/usr/local/www/cgi-bin/munin-cgi-html",
			"socket"      => "/var/spool/lighttpd/sockets/munin-cgi-html.sock",
			"bin-copy-environment" => ("PATH", "SHELL", "USER"),
			"check-local" => "disable",
			"broken-scriptfilename" => "enable",
		))
	)

url.rewrite-repeat += (
	"/munin/(.*)" => "/munin-cgi/munin-cgi-html/\$1",
	"/munin-cgi/munin-cgi-html$" => "/munin-cgi/munin-cgi-html/",
	"/munin-cgi/munin-cgi-html/static/(.*)" => "/munin-static/\$1"
)

extforward.forwarder = (
		"$(get_jail_ip haproxy)" => "trust",
	)
EO_LIGHTTPD_MT6

	stage_sysrc lighttpd_enable="YES"
}

configure_munin()
{
	if [ -d "$STAGE_MNT/data/etc/munin" ]; then
		rm -r "$STAGE_MNT/usr/local/etc/munin"
	else
		mv "$STAGE_MNT/usr/local/etc/munin" "$STAGE_MNT/data/etc/"
	fi
	stage_exec ln -s /data/etc/munin /usr/local/etc/munin

	if [ ! -d "$ZFS_DATA_MNT/monitor/var/munin" ]; then
		mkdir -p "$ZFS_DATA_MNT/monitor/var/munin"
		chown -R 842:842 "$ZFS_DATA_MNT/monitor/var/munin"
	fi

	if ! grep -qs ^#graph_strategy "$STAGE_MNT/data/etc/munin/munin.conf" ; then
		tell_status "preserving munin.conf"
	else
		tell_status "update munin.conf to use ZFS_DATA_MNT"
	
		sed -i .bak \
			-e 's/^#dbdir.*/dbdir   \/data\/var\/munin/' \
			-e 's/^#graph_strategy cron/graph_strategy cgi/' \
			-e 's/^#html_strategy cron/html_strategy cgi/' \
			"$STAGE_MNT/data/etc/munin/munin.conf" || exit
	fi

	#Needed for CGI graph to work
	stage_exec chmod -R 777 /var/log/munin
	stage_exec mkdir -p /var/munin/cgi-tmp
	stage_exec chmod -R 777 /var/munin/cgi-tmp
	stage_exec chown -R www:www /var/munin/cgi-tmp
	
	stage_sysrc munin_node_enable=YES
	stage_sysrc munin_node_config=/data/etc/munin/munin-node.conf
}

configure_nrpe()
{
	if [ -f "$ZFS_DATA_MNT/monitor/etc/nrpe.cfg" ]; then
		tell_status "preserving nrpe.cfg"
		rm "$STAGE_MNT/usr/local/etc/nrpe.cfg"
	else
		tell_status "installing default nrpe.cfg"
		mv "$STAGE_MNT/usr/local/etc/nrpe.cfg" \
			"$ZFS_DATA_MNT/monitor/etc/nrpe.cfg"
	fi

	stage_exec ln -s /data/etc/nrpe.cfg /usr/local/etc/nrpe.cfg
	stage_sysrc nrpe2_enable="YES"
	stage_sysrc nrpe2_configfile=/data/etc/nrpe.cfg
}

configure_monitor()
{
	tell_status "configuring monitor"
	if [ ! -d "$ZFS_DATA_MNT/monitor/etc" ]; then
		mkdir "$ZFS_DATA_MNT/monitor/etc"
	fi

	configure_lighttpd
	if [ -n "$TOASTER_NRPE" ]; then
		configure_nrpe
	fi

	if [ -n "$TOASTER_MUNIN" ]; then
		configure_munin
	fi
}

start_monitor()
{
   	tell_status "starting monitor"
}

test_monitor()
{
	tell_status "testing monitor"

	local _email _server _pass
	_email="postmaster@$TOASTER_MAIL_DOMAIN"
	_server=$(get_jail_ip haraka)
	_pass=$(jexec vpopmail /usr/local/vpopmail/bin/vuserinfo -C "$_email")

	tell_status "sending an email to $_email"
	stage_exec swaks -to "$_email" -server "$_server" -timeout 50 || exit

	tell_status "sending a TLS encrypted and authenticated email"
	stage_exec swaks -to "$_email" -server "$_server" -timeout 50 \
		-tls -au "$_email" -ap "$_pass" || exit

	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs monitor
start_staged_jail monitor
install_monitor
configure_monitor
start_monitor
test_monitor
promote_staged_jail monitor
