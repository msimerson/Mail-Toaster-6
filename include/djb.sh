#!/bin/sh

set -e

install_daemontools()
{
	tell_status "installing daemontools"
	stage_pkg_install rsync daemontools
}

install_ucspi_tcp()
{
        tell_status "installing ucspi-tcp with IPv6"
	stage_make_conf sysutils_ucspi-tcp_SET 'sysutils_ucspi-tcp_SET=IPV6'
	stage_make_conf sysutils_ucspi-tcp_UNSET 'sysutils_ucspi-tcp_UNSET=LIMITS RBL2SMTPD RSS_DIFF SSL'
	stage_port_install sysutils/ucspi-tcp
}

install_djbdns()
{
	if [ ! -d "$STAGE_MNT/data/home" ]; then
		mkdir "$STAGE_MNT/data/home"
	fi

	stage_pkg_install rsync

	stage_exec pw useradd tinydns -d /data/home/tinydns -m

	install_djbdns_source
}

install_djbdns_port()
{
	tell_status "installing djbdns port with IPv6"
	stage_make_conf dns_djbdns_SET 'dns_djbdns_SET=IP6'
	stage_port_install dns/djbdns
}

install_djbdns_source()
{
	tell_status "installing djbdns + IPv6 from source"

	store_exec "$STAGE_MNT/usr/src/djb.sh" <<EO_DJBDNS_INSTALLER
#!/bin/sh

set -e

cd /usr/src
if [ -d djbdns-1.05 ]; then rm -r djbdns-1.05; fi
fetch -m http://cr.yp.to/djbdns/djbdns-1.05.tar.gz
fetch -m http://www.fefe.de/dns/djbdns-1.05-test32.diff.xz
tar -xzf djbdns-1.05.tar.gz
cd djbdns-1.05
xzcat ../djbdns-1.05-test32.diff.xz | patch
echo "cc" > conf-cc
echo 'cc -s' > conf-ld
sed -i .bak -e 's/"\/"/auto_home/; s/02755/0755/g' hier.c
fetch -q -o - https://www.internic.net/domain/named.root \
    | grep ' A ' \
    | awk '{ print $4 }' \
    > dnsroots.global
make setup check
EO_DJBDNS_INSTALLER

	stage_exec sh /usr/src/djb.sh
}

configure_svscan()
{
	if [ ! -d "$STAGE_MNT/var/service" ]; then
		tell_status "creating default service dir"
		mkdir -p "$STAGE_MNT/var/service"
	fi

	if [ ! -d "$STAGE_MNT/data/service" ]; then
		tell_status "creating local service dir"
		mkdir -p "$STAGE_MNT/data/service"
	fi

	stage_sysrc svscan_enable="YES"
}

configure_tinydns4()
{
	tell_status "creating tinydns server"
	stage_exec tinydns-conf tinydns bin /var/service/tinydns "$(get_jail_ip stage)"
	store_exec "$STAGE_MNT/var/service/tinydns/run" <<EO_TINYDNS_RUN
#!/bin/sh

# logging enabled
#exec 2>&1

# logging disabled
exec 1>/dev/null 2>&1

exec envuidgid tinydns envdir ./env softlimit -d300000 /usr/local/bin/tinydns
EO_TINYDNS_RUN

	echo "/data/root" > "$STAGE_MNT/var/service/tinydns/env/ROOT"
}

configure_tinydns6()
{
	tell_status "creating tinydns IPv6 server"
	stage_exec tinydns-conf tinydns bin /var/service/tinydns-v6 "$(get_jail_ip6 stage)"
	store_exec "$STAGE_MNT/var/service/tinydns-v6/run" <<EO_TINYDNS_RUN
#!/bin/sh

# logging enabled
#exec 2>&1

# logging disabled
exec 1>/dev/null 2>&1

exec envuidgid tinydns envdir ./env softlimit -d300000 /usr/local/bin/tinydns
EO_TINYDNS_RUN

	echo "/data/root" > "$STAGE_MNT/var/service/tinydns-v6/env/ROOT"
}

configure_axfrdns4()
{
	tell_status "creating axfrdns server"
	stage_exec axfrdns-conf tinydns bin /var/service/axfrdns /data "$(get_jail_ip stage)"
	store_exec "$STAGE_MNT/var/service/axfrdns/run" <<'EO_AXFRDNS_RUN'
#!/bin/sh

# logging enabled
#exec 2>&1

# logging disabled
exec 1>/dev/null 2>&1

exec envdir ./env sh -c '
        exec envuidgid tinydns softlimit -d300000 tcpserver -vDRHl0 -x tcp.cdb -- "$IP" 53 /usr/local/bin/axfrdns
'
EO_AXFRDNS_RUN

	store_config "$STAGE_MNT/var/service/axfrdns/tcp" "overwrite" <<EOTCP
:allow,AXFR=""
:deny
EOTCP
	stage_exec make -C /var/service/axfrdns
}

configure_axfrdns6()
{
	tell_status "creating axfrdns IPv6 server"
	stage_exec axfrdns-conf tinydns bin /var/service/axfrdns-v6 /data "$(get_jail_ip6 stage)"
	store_exec "$STAGE_MNT/var/service/axfrdns-v6/run" <<'EO_AXFRDNS_RUN'
#!/bin/sh

# logging enabled
#exec 2>&1

# logging disabled
exec 1>/dev/null 2>&1

exec envdir ./env sh -c '
        exec envuidgid tinydns softlimit -d300000 tcpserver -vDRHl0 -x tcp.cdb -- "$IP" 53 /usr/local/bin/axfrdns
'
EO_AXFRDNS_RUN

	store_config "$STAGE_MNT/var/service/axfrdns-v6/tcp" "overwrite" <<EOTCP6
:allow,AXFR=""
:deny
EOTCP6
	stage_exec make -C /var/service/axfrdns-v6
}

start_tinydns()
{
	tell_status "starting dns daemons"
	stage_exec service svscan start
}
