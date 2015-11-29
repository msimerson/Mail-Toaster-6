#!/bin/sh

. mail-toaster.sh || exit

install_unbound()
{
	pkg -j $SAFE_NAME install -y unbound || exit
	jexec $SAFE_NAME /usr/local/sbin/unbound-control-setup
}

configure_unbound()
{
	local UNB_DIR="$STAGE_MNT/usr/local/etc/unbound"
	local UNB_LOCAL=""
	cp $UNB_DIR/unbound.conf.sample $UNB_DIR/unbound.conf || exit
	if [ -f "unbound.conf.local" ]; then
	  cp unbound.conf.local $UNB_DIR
	  UNB_LOCAL='include: "/usr/local/etc/unbound/unbound.conf.local"'
	fi

	# for the munin status plugin
	sed -i .bak -e 's/# control-enable: no/control-enable: yes/' $UNB_DIR/unbound.conf
	sed -i .bak -e 's/# control-interface: 127./control-interface: 127./' $UNB_DIR/unbound.conf

	tee -a $UNB_DIR/toaster.conf <<EO_UNBOUND
	   $UNB_LOCAL

	   access-control: 0.0.0.0/0 refuse
	   access-control: 127.0.0.0/8 allow

	   local-data: "2.0.0.127.in-addr.arpa PTR base"
	   local-data: "3.0.0.127.in-addr.arpa PTR dns"
	   local-data: "4.0.0.127.in-addr.arpa PTR mysql"
	   local-data: "5.0.0.127.in-addr.arpa PTR clamav"
	   local-data: "6.0.0.127.in-addr.arpa PTR spamassassin"
	   local-data: "7.0.0.127.in-addr.arpa PTR dspam"
	   local-data: "8.0.0.127.in-addr.arpa PTR vpopmail"
	   local-data: "9.0.0.127.in-addr.arpa PTR smtp"
	   local-data: "10.0.0.127.in-addr.arpa PTR webmail"
	   local-data: "11.0.0.127.in-addr.arpa PTR monitor"
	   local-data: "12.0.0.127.in-addr.arpa PTR haproxy"
	   local-data: "13.0.0.127.in-addr.arpa PTR rspamd"
	   local-data: "14.0.0.127.in-addr.arpa PTR avg"
	   local-data: "base A 127.0.0.2"
	   local-data: "dns A 127.0.0.3"
	   local-data: "mysql A 127.0.0.4"
	   local-data: "clamav A 127.0.0.5"
	   local-data: "spamassassin A 127.0.0.6"
	   local-data: "dspam A 127.0.0.7"
	   local-data: "vpopmail A 127.0.0.8"
	   local-data: "smtp A 127.0.0.9"
	   local-data: "webmail A 127.0.0.10"
	   local-data: "monitor A 127.0.0.11"
	   local-data: "haproxy A 127.0.0.12"
	   local-data: "rspamd A 127.0.0.13"
	   local-data: "avg A 127.0.0.14"
EO_UNBOUND

	sed -i.bak -e '/# local-data-ptr:.*/ a\ 
include: "/usr/local/etc/unbound/toaster.conf" \
' $UNB_DIR/unbound.conf
}

start_unbound()
{
	sysrc -f $STAGE_MNT/etc/rc.conf unbound_enable=YES
	jexec $SAFE_NAME service unbound start || exit
}

test_unbound()
{
	# use staging IP for DNS resolution
	echo "nameserver $STAGE_IP" | tee $STAGE_MNT/etc/resolv.conf

	# test if we get an answer
	jexec $SAFE_NAME host dns || exit

	# set it back to production value
	echo "nameserver ${JAIL_NET_PREFIX}.3" | tee $STAGE_MNT/etc/resolv.conf
}

promote_staged_jail()
{
	stop_staged_jail

	rename_fs_staged_to_ready dns
	stop_active_jail dns
	rename_fs_active_to_last dns
	rename_fs_ready_to_active dns

	echo "start jail $1"
	service jail start $1 || exit
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_staged_fs
sysrc -f $STAGE_MNT/etc/rc.conf hostname=dns
start_staged_jail $SAFE_NAME $STAGE_MNT
install_unbound
configure_unbound
start_unbound
test_unbound
promote_staged_jail dns
proclaim_success dns
