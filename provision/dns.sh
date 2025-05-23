#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		allow.raw_sockets;
		exec.poststart = \"$ZFS_DATA_MNT/dns/etc/rc.d/poststart.sh\";
		exec.prestop = \"$ZFS_DATA_MNT/dns/etc/rc.d/prestop.sh\";
"
export JAIL_FSTAB=""

install_unbound()
{
	tell_status "installing unbound"
	stage_pkg_install unbound
}

get_mt6_data()
{
	local _spf_ips

	if [ -z "$PUBLIC_IP6" ]; then
		_spf_ips="ip4:${JAIL_NET_PREFIX}.0/24 ip4:$PUBLIC_IP4 ip6:$JAIL_NET6::/112"
	else
		_spf_ips="ip4:${JAIL_NET_PREFIX}.0/24 ip4:$PUBLIC_IP4 ip6:$JAIL_NET6::/112 ip6:$PUBLIC_IP6"
	fi

	echo "

	   local-zone: $TOASTER_MAIL_DOMAIN typetransparent
	   local-data: \"stage		A $(get_jail_ip stage)\"
	   local-data: \"$(get_reverse_ip stage) PTR stage\"
	   local-data: \"$TOASTER_HOSTNAME A $(get_jail_ip vpopmail)\"
	   local-data: \"$TOASTER_HOSTNAME AAAA $(get_jail_ip6 vpopmail)\"
	   local-data: '$TOASTER_MAIL_DOMAIN TXT \"v=spf1 a mx $_spf_ips -all\"'
	   local-data: \"freebsd-update		A $(get_jail_ip bsd_cache)\"
	   local-data: \"pkg				A $(get_jail_ip bsd_cache)\"
	   local-data: \"vulnxml		    A $(get_jail_ip bsd_cache)\""

	if [ "$TOASTER_HOSTNAME" != "$TOASTER_MAIL_DOMAIN" ]; then
		echo -n "
	   local-data: '$TOASTER_HOSTNAME TXT \"v=spf1 a $_spf_ips -all\"'
	   local-data: \"$TOASTER_MAIL_DOMAIN MX 0 $TOASTER_HOSTNAME\""
	fi

	for _j in $JAIL_ORDERED_LIST; do
		echo "
	   local-data: \"$_j		A $(get_jail_ip "$_j")\"
	   local-data: \"$(get_reverse_ip "$_j") PTR $_j\"
	   local-data: \"$_j		AAAA $(get_jail_ip6 "$_j")\"
	   local-data: \"$(get_reverse_ip6 "$_j") PTR $_j\""
	done
}

install_access_conf()
{
	store_config "$ZFS_DATA_MNT/dns/access.conf" <<EO_UNBOUND_ACCESS

	   access-control: 0.0.0.0/0 refuse
	   access-control: 127.0.0.0/8 allow
	   access-control: ${JAIL_NET_PREFIX}.0${JAIL_NET_MASK} allow
	   access-control: $PUBLIC_IP4 allow
	   access-control: $JAIL_NET6::/112 allow

EO_UNBOUND_ACCESS
}

install_local_conf()
{
	store_config "$ZFS_DATA_MNT/dns/mt6-local.conf" "overwrite" <<EO_UNBOUND
	   $UNBOUND_LOCAL

	   $(get_mt6_data)
EO_UNBOUND
}

tweak_unbound_conf()
{
	tell_status "configuring unbound.conf"
	# control.conf for the munin stats plugin
	# shellcheck disable=1004
	sed -i.bak \
		-e 's/# interface: 192.0.2.153$/interface: 0.0.0.0/' \
		-e 's/# interface: 192.0.2.154$/interface: ::0/' \
		-e '/# use-syslog/s/# //' \
		-e '/# chroot: /s/# //' \
		-e '/chroot: /s/".*"/""/' \
		-e '/# hide-identity: /s/# //' \
		-e '/hide-identity: /s/no/yes/' \
		-e '/# hide-version: /s/# //' \
		-e '/hide-version: /s/no/yes/' \
		-e '/# access-control: ::ffff:127.*/ a\ 
include: "/data/access.conf" \
' \
		-e '/# local-data-ptr:.*/ a\ 
include: "/data/mt6-local.conf" \
' \
		-e '/^remote-control:/ a\ 
	include: "/data/control.conf" \
' \
		"$UNBOUND_DIR/unbound.conf"
}

enable_control()
{
	if [ -d "$ZFS_DATA_MNT/dns/control" ]; then
		tell_status "preserving unbound-control"
		return
	fi

	tell_status "creating $ZFS_DATA_MNT/dns/control"
	mkdir "$ZFS_DATA_MNT/dns/control"

	tell_status "configuring unbound-control"
	tee "$ZFS_DATA_MNT/dns/control.conf" <<EO_CONTROL_CONF
		control-enable: yes
		control-interface: 0.0.0.0

		# chroot must be disabled for unbound to access the server certs here
		server-key-file: "/data/control/unbound_server.key"
		server-cert-file: "/data/control/unbound_server.pem"

		control-key-file: "/data/control/unbound_control.key"
		control-cert-file: "/data/control/unbound_control.pem"
EO_CONTROL_CONF

	sed -i.bak \
		-e '/^DESTDIR=/ s/=.*$/=\/data\/control/' \
		"$STAGE_MNT/usr/local/sbin/unbound-control-setup"

	stage_exec /usr/local/sbin/unbound-control-setup
}

configure_unbound()
{
	UNBOUND_DIR="$STAGE_MNT/usr/local/etc/unbound"
	UNBOUND_LOCAL=""

	cp "$UNBOUND_DIR/unbound.conf.sample" "$UNBOUND_DIR/unbound.conf"
	if [ -f 'unbound.conf.local' ]; then
		tell_status "moving unbound.conf.local to data volume"
		mv unbound.conf.local "$ZFS_DATA_MNT/dns/"
	fi

	if [ -f "$ZFS_DATA_MNT/dns/unbound.conf.local" ]; then
		tell_status "activating unbound.conf.local"
		UNBOUND_LOCAL='include: "/data/unbound.conf.local"'
	fi

	enable_control
	tweak_unbound_conf

	get_public_ip ipv6
	get_public_ip

	install_access_conf
	install_local_conf
}

start_unbound()
{
	tell_status "starting unbound"
	stage_sysrc unbound_enable=YES
	stage_exec service unbound start
}

test_unbound()
{
	tell_status "testing unbound"
	stage_test_running unbound

	# use stage IP for DNS resolution
	echo "nameserver $(get_jail_ip stage)" | tee "$STAGE_MNT/etc/resolv.conf"

	# test if we get an answer
	stage_exec host dns

	# set it back to production value
	echo "nameserver $(get_jail_ip dns)" | tee "$STAGE_MNT/etc/resolv.conf"
	echo "it worked."

	if [ -f "$ZFS_DATA_MNT/dns/unbound.conf" ]; then
		stage_sysrc unbound_conf=/data/unbound.conf
	fi
}

switch_host_resolver()
{
	if sysrc -c -f /etc/resolvconf.conf resolvconf=NO; then
		echo "turning resolvconf back on"
		truncate -s 0 /etc/resolvconf.conf
	fi

	store_exec "$ZFS_DATA_MNT/dns/etc/rc.d/poststart.sh" <<EO_POSTSTART
#!/bin/sh
echo "nameserver $(get_jail_ip dns) $(get_jail_ip6 dns)" | /sbin/resolvconf -a lo1.dns -m 0
EO_POSTSTART

	store_exec "$ZFS_DATA_MNT/dns/etc/rc.d/prestop.sh" <<EO_PRESTOP
#!/bin/sh
/sbin/resolvconf -d lo1.dns
EO_PRESTOP
}

base_snapshot_exists || exit 1
create_staged_fs dns
start_staged_jail dns
install_unbound
configure_unbound
start_unbound
test_unbound
switch_host_resolver
promote_staged_jail dns
