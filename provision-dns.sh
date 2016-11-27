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

get_jails_conf()
{
    echo "

	   access-control: 0.0.0.0/0 refuse
	   access-control: 127.0.0.0/8 allow
	   access-control: ${JAIL_NET_PREFIX}.0${JAIL_NET_MASK} allow
	   access-control: $PUBLIC_IP4 allow

	   local-data: \"stage        A $(get_jail_ip stage)\"
	   local-data: \"$(get_reverse_ip stage) PTR stage\""

	local _octet=${JAIL_NET_START:=1}
	for _j in $JAIL_ORDERED_LIST
	do
	    echo "
	   local-data: \"$_j       A $(get_jail_ip $_j)\"
	   local-data: \"$(get_reverse_ip $_j) PTR $_j\""
	done
}

configure_unbound()
{
	local UNB_DIR="$STAGE_MNT/usr/local/etc/unbound"
	local UNB_LOCAL=""
	cp "$UNB_DIR/unbound.conf.sample" "$UNB_DIR/unbound.conf" || exit
	if [ -f "unbound.conf.local" ]; then
		tell_status "installing unbound.conf.local"
		cp unbound.conf.local "$UNB_DIR"
		UNB_LOCAL='include: "/usr/local/etc/unbound/unbound.conf.local"'
	fi

	tell_status "configuring unbound-control"
	stage_exec /usr/local/sbin/unbound-control-setup

	tell_status "configuring unbound.conf"
	# for the munin status plugin
	sed -i .bak \
		-e 's/# interface: 192.0.2.153$/interface: 0.0.0.0/' \
		-e 's/# interface: 192.0.2.154$/interface: ::0/' \
		-e 's/# control-enable: no/control-enable: yes/' \
		-e "s/# control-interface: 127.*/control-interface: 0.0.0.0/" \
		-e 's/# use-syslog: yes/use-syslog: yes/' \
		-e 's/# hide-identity: no/hide-identity: yes/' \
		-e 's/# hide-version: no/hide-version: yes/' \
		-e '/# local-data-ptr:.*/ a\ 
include: "/usr/local/etc/unbound/toaster.conf" \
' \
		"$UNB_DIR/unbound.conf" || exit

	get_public_ip

	tell_status "installing unbound/toaster.conf"
	tee -a "$UNB_DIR/toaster.conf" <<EO_UNBOUND
       $UNB_LOCAL

	   $(get_jails_conf)
EO_UNBOUND
}

start_unbound()
{
	tell_status "starting unbound"
	stage_sysrc unbound_enable=YES
	stage_exec service unbound start || exit
}

test_unbound()
{
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
start_staged_jail
install_unbound
configure_unbound
start_unbound
test_unbound
promote_staged_jail dns

# shellcheck disable=2039,2094
echo -e "nameserver $(get_jail_ip dns)\n$(cat /etc/resolv.conf)" > /etc/resolv.conf
