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
	sed -i .bak \
        -e 's/# interface: 192.0.2.153$/interface: 0.0.0.0/' \
        -e 's/# interface: 192.0.2.154$/interface: ::0/' \
        -e 's/# control-enable: no/control-enable: yes/' \
        -e "s/# control-interface: 127.*/control-interface: 0.0.0.0/" \
        "$UNB_DIR/unbound.conf"

	get_public_ip

	tee -a "$UNB_DIR/toaster.conf" <<EO_UNBOUND
	   $UNB_LOCAL

	   hide-identity: yes
	   hide-version: yes

	   access-control: 0.0.0.0/0 refuse
	   access-control: 127.0.0.0/8 allow
	   access-control: ${JAIL_NET_PREFIX}.0${JAIL_NET_MASK} allow
	   access-control: $PUBLIC_IP4 allow

	   local-data: "$(get_reverse_ip base) PTR base"
	   local-data: "$(get_reverse_ip dns) PTR dns"
	   local-data: "$(get_reverse_ip mysql) PTR mysql"
	   local-data: "$(get_reverse_ip clamav) PTR clamav"
	   local-data: "$(get_reverse_ip spamassassin) PTR spamassassin"
	   local-data: "$(get_reverse_ip dspam) PTR dspam"
	   local-data: "$(get_reverse_ip vpopmail) PTR vpopmail"
	   local-data: "$(get_reverse_ip vpopmail) PTR haraka"
	   local-data: "$(get_reverse_ip webmail) PTR webmail"
	   local-data: "$(get_reverse_ip monitor) PTR monitor"
	   local-data: "$(get_reverse_ip haproxy) PTR haproxy"
	   local-data: "$(get_reverse_ip rspamd) PTR rspamd"
	   local-data: "$(get_reverse_ip avg) PTR avg"
	   local-data: "$(get_reverse_ip dovecot) PTR dovecot"
	   local-data: "$(get_reverse_ip redis) PTR redis"
	   local-data: "$(get_reverse_ip geoip) PTR geoip"
	   local-data: "$(get_reverse_ip stage) PTR stage"

	   local-data: "base         A $(get_jail_ip base)"
	   local-data: "dns          A $(get_jail_ip dns)"
	   local-data: "mysql        A $(get_jail_ip mysql)"
	   local-data: "clamav       A $(get_jail_ip clamav)"
	   local-data: "spamassassin A $(get_jail_ip spamassassin)"
	   local-data: "dspam        A $(get_jail_ip dspam)"
	   local-data: "vpopmail     A $(get_jail_ip vpopmail)"
	   local-data: "haraka       A $(get_jail_ip haraka)"
	   local-data: "webmail      A $(get_jail_ip webmail)"
	   local-data: "monitor      A $(get_jail_ip monitor)"
	   local-data: "haproxy      A $(get_jail_ip haproxy)"
	   local-data: "rspamd       A $(get_jail_ip rspamd)"
	   local-data: "avg          A $(get_jail_ip avg)"
	   local-data: "dovecot      A $(get_jail_ip dovecot)"
	   local-data: "redis        A $(get_jail_ip redis)"
	   local-data: "geoip        A $(get_jail_ip geoip)"
	   local-data: "stage        A $(get_jail_ip stage)"

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
	# use stage IP for DNS resolution
	echo "nameserver $(get_jail_ip stage)" | tee "$STAGE_MNT/etc/resolv.conf"

	# test if we get an answer
	stage_exec host dns || exit

	# set it back to production value
	echo "nameserver $(get_jail_ip dns)" | tee "$STAGE_MNT/etc/resolv.conf"
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
