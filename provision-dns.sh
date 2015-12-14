#!/bin/sh

. mail-toaster.sh || exit

install_unbound()
{
	stage_pkg_install unbound || exit
	stage_exec /usr/local/sbin/unbound-control-setup
}

configure_unbound()
{
	local UNB_DIR="$STAGE_MNT/usr/local/etc/unbound"
	local UNB_LOCAL=""
	cp "$UNB_DIR/unbound.conf.sample" "$UNB_DIR/unbound.conf" || exit
	if [ -f "unbound.conf.local" ]; then
	  cp unbound.conf.local "$UNB_DIR"
	  UNB_LOCAL='include: "/usr/local/etc/unbound/unbound.conf.local"'
	fi

	# for the munin status plugin
	sed -i .bak -e 's/# control-enable: no/control-enable: yes/' "$UNB_DIR/unbound.conf"
	sed -i .bak -e 's/# control-interface: 127./control-interface: 127./' "$UNB_DIR/unbound.conf"

	local _rev_net
	_rev_net=$(echo "$JAIL_NET_PREFIX" | awk '{split($1,a,".");printf("%s.%s.%s",a[3],a[2],a[1])}')
	get_public_ip

	tee -a "$UNB_DIR/toaster.conf" <<EO_UNBOUND
	   $UNB_LOCAL

	   access-control: 0.0.0.0/0 refuse
	   access-control: 127.0.0.0/8 allow
	   access-control: ${JAIL_NET_PREFIX}.0${JAIL_NET_MASK} allow
	   access-control: $PUBLIC_IP4 allow

	   local-data:   "2.${_rev_net}.in-addr.arpa PTR base"
	   local-data:   "3.${_rev_net}.in-addr.arpa PTR dns"
	   local-data:   "4.${_rev_net}.in-addr.arpa PTR mysql"
	   local-data:   "5.${_rev_net}.in-addr.arpa PTR clamav"
	   local-data:   "6.${_rev_net}.in-addr.arpa PTR spamassassin"
	   local-data:   "7.${_rev_net}.in-addr.arpa PTR dspam"
	   local-data:   "8.${_rev_net}.in-addr.arpa PTR vpopmail"
	   local-data:   "9.${_rev_net}.in-addr.arpa PTR smtp"
	   local-data:  "10.${_rev_net}.in-addr.arpa PTR webmail"
	   local-data:  "11.${_rev_net}.in-addr.arpa PTR monitor"
	   local-data:  "12.${_rev_net}.in-addr.arpa PTR haproxy"
	   local-data:  "13.${_rev_net}.in-addr.arpa PTR rspamd"
	   local-data:  "14.${_rev_net}.in-addr.arpa PTR avg"
	   local-data:  "15.${_rev_net}.in-addr.arpa PTR dovecot"
	   local-data: "254.${_rev_net}.in-addr.arpa PTR staged"

	   local-data: "base     A ${JAIL_NET_PREFIX}.2"
	   local-data: "DNS      A ${JAIL_NET_PREFIX}.3"
	   local-data: "mysql    A ${JAIL_NET_PREFIX}.4"
	   local-data: "clamav   A ${JAIL_NET_PREFIX}.5"
	   local-data: "spamassassin A ${JAIL_NET_PREFIX}.6"
	   local-data: "dspam    A ${JAIL_NET_PREFIX}.7"
	   local-data: "vpopmail A ${JAIL_NET_PREFIX}.8"
	   local-data: "smtp     A ${JAIL_NET_PREFIX}.9"
	   local-data: "webmail  A ${JAIL_NET_PREFIX}.10"
	   local-data: "monitor  A ${JAIL_NET_PREFIX}.11"
	   local-data: "haproxy  A ${JAIL_NET_PREFIX}.12"
	   local-data: "rspamd   A ${JAIL_NET_PREFIX}.13"
	   local-data: "avg      A ${JAIL_NET_PREFIX}.14"
	   local-data: "dovecot  A ${JAIL_NET_PREFIX}.15"
	   local-data: "staged   A ${JAIL_NET_PREFIX}.254"

EO_UNBOUND

	sed -i.bak -e '/# local-data-ptr:.*/ a\ 
include: "/usr/local/etc/unbound/toaster.conf" \
' "$UNB_DIR/unbound.conf"
}

start_unbound()
{
	stage_sysrc unbound_enable=YES
	stage_exec service unbound start || exit
}

test_unbound()
{
	# use staged IP for DNS resolution
	echo "nameserver $(get_jail_ip stage)" | tee "$STAGE_MNT/etc/resolv.conf"

	# test if we get an answer
	stage_exec host dns || exit

	# set it back to production value
	echo "nameserver $(get_jail_ip dns)" | tee "$STAGE_MNT/etc/resolv.conf"
}

base_snapshot_exists || exit
create_staged_fs dns
stage_sysrc hostname=dns
start_staged_jail
install_unbound
configure_unbound
start_unbound
test_unbound
promote_staged_jail dns
