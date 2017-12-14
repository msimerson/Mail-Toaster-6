#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_unbound()
{
	tell_status "installing unbound"
	stage_pkg_install unbound || exit
}

get_mt6_data()
{
	get_public_ip

	local _spf_ips

	if [ -z "$PUBLIC_IP6" ]; then
		_spf_ips="ip4:${JAIL_NET_PREFIX}.0/24 ip4:$PUBLIC_IP4 ip6:$JAIL_NET6::/64"
	else
		_spf_ips="ip4:${JAIL_NET_PREFIX}.0/24 ip4:$PUBLIC_IP4 ip6:$JAIL_NET6::/64 ip6:$PUBLIC_IP6"
	fi

	echo "

	   local-data: \"stage		A $(get_jail_ip stage)\"
	   local-data: \"$(get_reverse_ip stage) PTR stage\"
	   local-data: \"$TOASTER_HOSTNAME A $(get_jail_ip vpopmail)\"
	   local-data: \"$TOASTER_HOSTNAME AAAA $(get_jail_ip6 vpopmail)\"
	   local-data: \"$TOASTER_HOSTNAME TXT 'v=spf1 a $_spf_ips -all'\"
	   local-data: \"$TOASTER_MAIL_DOMAIN TXT 'v=spf1 a mx $_spf_ips -all'\"
	   local-data: \"$TOASTER_MAIL_DOMAIN MX 0 $TOASTER_HOSTNAME\""

	for _j in $JAIL_ORDERED_LIST
	do
		echo "
	   local-data: \"$_j		A $(get_jail_ip "$_j")\"
	   local-data: \"$(get_reverse_ip "$_j") PTR $_j\"
	   local-data: \"$_j		AAAA $(get_jail_ip6 "$_j")\"
	   local-data: \"$(get_reverse_ip6 "$_j") PTR $_j\""
	done
}

install_access_conf()
{
	if [ ! -f "$ZFS_DATA_MNT/dns/access.conf" ]; then
		tell_status "installing access.conf"
		tee "$ZFS_DATA_MNT/dns/access.conf" <<EO_UNBOUND_ACCESS

	   access-control: 0.0.0.0/0 refuse
	   access-control: 127.0.0.0/8 allow
	   access-control: ${JAIL_NET_PREFIX}.0${JAIL_NET_MASK} allow
	   access-control: $PUBLIC_IP4 allow
	   access-control: $JAIL_NET6::/64 allow

EO_UNBOUND_ACCESS
	else
		tell_status "preserving access.conf"
	fi
}

install_local_conf()
{
	if [ -f "$ZFS_DATA_MNT/dns/mt6-local.conf" ]; then
		tell_status "updating unbound/mt6-local.conf"
	else
		tell_status "installing unbound/mt6-local.conf"
	fi

	tee "$ZFS_DATA_MNT/dns/mt6-local.conf" <<EO_UNBOUND
	   $UNBOUND_LOCAL

	   $(get_mt6_data)
EO_UNBOUND
}

tweak_unbound_conf()
{
	tell_status "configuring unbound.conf"
	# control.conf for the munin stats plugin
	# shellcheck disable=1004
	sed -i .bak \
		-e 's/# interface: 192.0.2.153$/interface: 0.0.0.0/' \
		-e 's/# interface: 192.0.2.154$/interface: ::0/' \
		-e '/# use-syslog/      s/# //' \
		-e '/# chroot: /        s/# //; s/".*"/""/' \
		-e '/# hide-identity: / s/# //; s/no/yes/' \
		-e '/# hide-version: /  s/# //; s/no/yes/' \
		-e '/# access-control: ::ffff:127.*/ a\ 
include: "/data/access.conf" \
' \
		-e '/# local-data-ptr:.*/ a\ 
include: "/data/mt6-local.conf" \
' \
		-e '/^remote-control:/ a\ 
	include: "/data/control.conf" \
' \
		"$UNBOUND_DIR/unbound.conf" || exit
}

enable_control()
{
	tell_status "configuring unbound-control"
	if [ -d "$ZFS_DATA_MNT/dns/control" ]; then
		tell_status "preserving unbound control"
		return
	fi

	tell_status "creating $ZFS_DATA_MNT/dns/control"
	mkdir "$ZFS_DATA_MNT/dns/control" || exit

	tee -a "$ZFS_DATA_MNT/dns/control.conf" <<EO_CONTROL_CONF
		control-enable: yes
		control-interface: 0.0.0.0

		# chroot must be disabled for unbound to access the server certs here
		server-key-file: "/data/control/unbound_server.key"
		server-cert-file: "/data/control/unbound_server.pem"

		control-key-file: "/data/control/unbound_control.key"
		control-cert-file: "/data/control/unbound_control.pem"
EO_CONTROL_CONF

	sed -i .bak \
		-e '/^DESTDIR=/ s/=.*$/=\/data\/control/' \
		"$STAGE_MNT/usr/local/sbin/unbound-control-setup"

	stage_exec /usr/local/sbin/unbound-control-setup
}

configure_unbound()
{
	UNBOUND_DIR="$STAGE_MNT/usr/local/etc/unbound"
	UNBOUND_LOCAL=""

	cp "$UNBOUND_DIR/unbound.conf.sample" "$UNBOUND_DIR/unbound.conf" || exit
	if [ -f 'unbound.conf.local' ]; then
		tell_status "moving unbound.conf.local to data volume"
		mv unbound.conf.local "$ZFS_DATA_MNT/dns/" || exit
	fi

	if [ -f "$ZFS_DATA_MNT/dns/unbound.conf.local" ]; then
		tell_status "activating unbound.conf.local"
		UNBOUND_LOCAL='include: "/data/unbound.conf.local"'
	fi

	enable_control
	tweak_unbound_conf
	get_public_ip

	install_access_conf
	install_local_conf
}

start_unbound()
{
	tell_status "starting unbound"
	stage_sysrc unbound_enable=YES
	stage_exec service unbound start || exit
}

test_unbound()
{
	tell_status "testing unbound"
	stage_test_running unbound

	# use stage IP for DNS resolution
	echo "nameserver $(get_jail_ip stage)" | tee "$STAGE_MNT/etc/resolv.conf"

	# test if we get an answer
	stage_exec host dns || exit

	# set it back to production value
	echo "nameserver $(get_jail_ip dns)" | tee "$STAGE_MNT/etc/resolv.conf"
	echo "it worked."
}

base_snapshot_exists || exit
create_staged_fs dns
start_staged_jail dns
install_unbound
configure_unbound
start_unbound
test_unbound
promote_staged_jail dns

if [ ! -f /etc/resolv.conf.orig ]; then
	cp /etc/resolv.conf /etc/resolv.conf.orig
fi

if ! grep "^nameserver $(get_jail_ip dns)" /etc/resolv.conf;
then
	echo "switching host resolver to $(get_jail_ip dns)"
	echo "nameserver $(get_jail_ip dns)" > /etc/resolv.conf
	echo "nameserver $(get_jail_ip6 dns)" >> /etc/resolv.conf
	cat /etc/resolv.conf.orig >> /etc/resolv.conf
fi