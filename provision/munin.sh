#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_lighttpd()
{
	tell_status "installing lighttpd"
	stage_pkg_install lighttpd

	mkdir -p "$STAGE_MNT/var/spool/lighttpd/sockets"
	chown -R www "$STAGE_MNT/var/spool/lighttpd/sockets"
}

install_munin()
{
	install_lighttpd

	tell_status "installing munin"
	stage_pkg_install munin-node munin-master
}

configure_lighttpd()
{
	local _lighttpd_dir="$STAGE_MNT/usr/local/etc/lighttpd"
	local _lighttpd_conf="$_lighttpd_dir/lighttpd.conf"

	# shellcheck disable=2016
	sed -i.bak \
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
	configure_lighttpd

	tell_status "configuring munin"

	if [ ! -d "$ZFS_DATA_MNT/munin/etc" ]; then
		mkdir "$ZFS_DATA_MNT/munin/etc"
	fi
	if [ -d "$STAGE_MNT/data/etc/munin" ]; then
		rm -r "$STAGE_MNT/usr/local/etc/munin"
	else
		mv "$STAGE_MNT/usr/local/etc/munin" "$STAGE_MNT/data/etc/"
	fi
	stage_exec ln -s /data/etc/munin /usr/local/etc/munin

	if [ ! -d "$ZFS_DATA_MNT/munin/var/munin" ]; then
		mkdir -p "$ZFS_DATA_MNT/munin/var/munin"
		chown -R 842:842 "$ZFS_DATA_MNT/munin/var/munin"
	fi

	if ! grep -qs ^#graph_strategy "$STAGE_MNT/data/etc/munin/munin.conf" ; then
		tell_status "preserving munin.conf"
	else
		tell_status "update munin.conf to use ZFS_DATA_MNT"

		sed -i.bak \
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

start_munin()
{
	tell_status "starting munin"
	stage_exec service lighttpd start
	stage_exec service munin-server start
}

test_munin()
{
	tell_status "testing munin"

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
create_staged_fs munin
start_staged_jail munin
install_munin
configure_munin
start_munin
test_munin
promote_staged_jail munin
