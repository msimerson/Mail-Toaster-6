#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

install_unbound()
{
	tell_status "installing unbound"
	stage_pkg_install unbound || exit
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

	   access-control: 0.0.0.0/0 refuse
	   access-control: 127.0.0.0/8 allow
	   access-control: ${JAIL_NET_PREFIX}.0${JAIL_NET_MASK} allow
	   access-control: $PUBLIC_IP4 allow

	   local-data: "$(get_reverse_ip syslog) PTR syslog"
	   local-data: "$(get_reverse_ip base) PTR base"
	   local-data: "$(get_reverse_ip dns) PTR dns"
	   local-data: "$(get_reverse_ip mysql) PTR mysql"
	   local-data: "$(get_reverse_ip clamav) PTR clamav"
	   local-data: "$(get_reverse_ip spamassassin) PTR spamassassin"
	   local-data: "$(get_reverse_ip dspam) PTR dspam"
	   local-data: "$(get_reverse_ip vpopmail) PTR vpopmail"
	   local-data: "$(get_reverse_ip haraka) PTR haraka"
	   local-data: "$(get_reverse_ip webmail) PTR webmail"
	   local-data: "$(get_reverse_ip monitor) PTR monitor"
	   local-data: "$(get_reverse_ip haproxy) PTR haproxy"
	   local-data: "$(get_reverse_ip rspamd) PTR rspamd"
	   local-data: "$(get_reverse_ip avg) PTR avg"
	   local-data: "$(get_reverse_ip dovecot) PTR dovecot"
	   local-data: "$(get_reverse_ip redis) PTR redis"
	   local-data: "$(get_reverse_ip geoip) PTR geoip"
	   local-data: "$(get_reverse_ip nginx) PTR nginx"
	   local-data: "$(get_reverse_ip lighttpd) PTR lighttpd"
	   local-data: "$(get_reverse_ip apache) PTR apache"
	   local-data: "$(get_reverse_ip postgres) PTR postgres"
	   local-data: "$(get_reverse_ip minecraft) PTR minecraft"
	   local-data: "$(get_reverse_ip joomla) PTR joomla"
	   local-data: "$(get_reverse_ip php7) PTR php7"
	   local-data: "$(get_reverse_ip memcached) PTR memcached"
	   local-data: "$(get_reverse_ip sphinxsearch) PTR sphinxsearch"
	   local-data: "$(get_reverse_ip stage) PTR stage"

	   local-data: "syslog       A $(get_jail_ip syslog)"
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
	   local-data: "nginx        A $(get_jail_ip nginx)"
	   local-data: "lighttpd     A $(get_jail_ip lighttpd)"
	   local-data: "apache       A $(get_jail_ip apache)"
	   local-data: "postgres     A $(get_jail_ip postgres)"
	   local-data: "minecraft    A $(get_jail_ip minecraft)"
	   local-data: "joomla       A $(get_jail_ip joomla)"
	   local-data: "php7         A $(get_jail_ip php7)"
	   local-data: "memcached    A $(get_jail_ip memcached)"
	   local-data: "sphinxsearch A $(get_jail_ip sphinxsearch)"
	   local-data: "stage        A $(get_jail_ip stage)"

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
