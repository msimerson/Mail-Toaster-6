#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

configure_ntpd()
{
	if grep -q ^ntpd_enable /etc/rc.conf; then
		return
	fi

	tell_status "enabling NTPd"
	sysrc ntpd_enable=YES || exit
	sysrc ntpd_sync_on_start=YES
	/etc/rc.d/ntpd restart
}

update_syslogd()
{
	if grep -q ^syslogd_flags /etc/rc.conf; then
		tell_status "preserving syslogd_flags"
		return
	fi

	tell_status "configuring syslog to accept messages from jails"
	sysrc syslogd_flags="-b $JAIL_NET_PREFIX.1 -a $JAIL_NET_PREFIX.0$JAIL_NET_MASK:* -cc"
	service syslogd restart
}

update_sendmail()
{
	if grep -q ^sendmail_enable /etc/rc.conf; then
		tell_status "preserving sendmail config"
		return
	fi

	tell_status "disable sendmail network listening"
	sysrc sendmail_enable=NO
	service sendmail onestop
}

install_periodic_conf()
{
	if [ -f /etc/periodic.conf ]; then
		return
	fi

	tell_status "installing /etc/periodic.conf"
	tee -a /etc/periodic.conf <<EO_PERIODIC
# older versions of FreeBSD bark b/c these are defined in
# /etc/defaults/periodic.conf and do not exist. Hush.
daily_local=""
weekly_local=""
monthly_local=""

# in case /etc/aliases isn't set up properly
daily_output="$TOASTER_ADMIN_EMAIL"
weekly_output="$TOASTER_ADMIN_EMAIL"
monthly_output="$TOASTER_ADMIN_EMAIL"

security_show_success="NO"
security_show_info="YES"
security_status_chksetuid_enable="NO"
security_status_neggrpperm_enable="NO"
security_status_pkgaudit_enable="YES"
security_status_tcpwrap_enable="YES"

security_status_ipfwlimit_enable="NO"
security_status_ipfwdenied_enable="NO"
security_status_pfdenied_enable="NO"

daily_accounting_enable="NO"
daily_accounting_compress="YES"
daily_clean_disks_enable="NO"
daily_clean_disks_days=14
daily_clean_disks_verbose="NO"
daily_clean_hoststat_enable="NO"
daily_clean_tmps_enable="YES"
daily_clean_tmps_verbose="NO"
daily_news_expire_enable="NO"
daily_scrub_zfs_enable="YES"

daily_show_success="NO"
daily_show_info="NO"
daily_show_badconfig="YES"

daily_status_disks_enable="NO"
daily_status_include_submit_mailq="NO"
daily_status_mail_rejects_enable="YES"
daily_status_mailq_enable="NO"
daily_status_rwho_enable="NO"
daily_submit_queuerun="NO"
daily_status_smart_enable=YES
daily_status_smart_devices="AUTO"

weekly_show_success="NO"
weekly_show_info="NO"
weekly_show_badconfig="YES"
weekly_whatis_enable="NO"

monthly_show_success="NO"
monthly_show_info="NO"
monthly_show_badconfig="YES"
EO_PERIODIC
}

constrain_sshd_to_host()
{
	if grep -q ^ListenAddress /etc/ssh/sshd_config; then
		tell_status "preserving sshd_config ListenAddress"
		return
	fi

	tell_status "checking sshd listening scope"
	if ! sockstat -L | egrep '\*:22 '; then
		return
	fi

	get_public_ip
	get_public_ip ipv6
	local _sshd_conf="/etc/ssh/sshd_config"

	local _confirm_msg="
	To not interfere with the jails, sshd must be constrained to
	listening on your hosts public facing IP(s).

	Your public IPs are detected as $PUBLIC_IP4
		and $PUBLIC_IP6

	May I update $_sshd_conf?
	"
	dialog --yesno "$_confirm_msg" 13 70 || exit

	tell_status "Limiting SSHd to host IP address"

	sed -i -e "s/#ListenAddress 0.0.0.0/ListenAddress $PUBLIC_IP4/" $_sshd_conf
	if [ -n "$PUBLIC_IP6" ]; then
		sed -i -e "s/#ListenAddress ::/ListenAddress $PUBLIC_IP6/" $_sshd_conf
	fi

	grep ^Listen /etc/ssh/sshd_config
	service sshd configtest || exit
	service sshd restart
}

configure_tls_certs()
{
	if [ -s /etc/ssl/private/server.key ]; then
		tell_status "TLS certificates already exist"
		return
	fi

	if [ ! -d /etc/ssl/certs ]; then
		mkdir "/etc/ssl/certs" "/etc/ssl/private"
		chmod o-r "/etc/ssl/private"
	fi

	if ! grep -q commonName_default /etc/ssl/openssl.cnf; then
		tell_status "updating openssl.cnf defaults"
		local _geo;   _geo=$(fetch -o - https://freegeoip.net/csv)
		local _cc;    _cc=$(echo $_geo | cut -d',' -f2)
		local _state; _state=$(echo $_geo | cut -d',' -f5)
		local _city;  _city=$(echo $_geo | cut -d',' -f6)
		sed -i .bak \
		    -e "/^commonName_max.*/ a\ 
commonName_default = $TOASTER_HOSTNAME" \
			-e "/^emailAddress_max.*/ a\ 
emailAddress_default = $TOASTER_ADMIN_EMAIL" \
			-e "/^localityName.*/ a\ 
localityName_default = $_city" \
			-e "/^countryName_default/ s/AU/$_cc/" \
			-e "/^stateOrProvinceName_default/ s/Some-State/$_state/" \
			/etc/ssl/openssl.cnf
	fi

	if [ -f /etc/ssl/private/server.key ]; then
		tell_status "preserving existing TLS certificates"
		return
	fi

	echo
	echo "A number of daemons use TLS to encrypt connections. Setting up TLS now"
	echo "  saves having to do it multiple times later."
	tell_status "Generating self-signed SSL certificates"

	openssl req -x509 -nodes -days 2190 \
		-newkey rsa:2048 \
		-keyout /etc/ssl/private/server.key \
		-out /etc/ssl/certs/server.crt

	if [ ! -f /etc/ssl/private/server.key ]; then
		fatal_err "no TLS key was generated!"
	fi
}

check_global_listeners()
{
	tell_status "checking for host listeners on all IPs"

	if sockstat -L -4 | egrep '\*:[0-9]' | grep -v 123; then
		echo "oops!, you should not having anything listening
on all your IP addresses!"
		exit 2
	fi
}

add_jail_nat()
{
	if grep -qs bruteforce /etc/pf.conf; then
		tell_status "preserving pf.conf settings"
		return
	fi

	get_public_ip
	get_public_ip ipv6

	if [ -z "$PUBLIC_NIC" ]; then echo "PUBLIC_NIC unset!"; exit; fi
	if [ -z "$PUBLIC_IP4" ]; then echo "PUBLIC_IP4 unset!"; exit; fi

	tell_status "enabling NAT for jails"
	tee -a /etc/pf.conf <<EO_PF_RULES
ext_if="$PUBLIC_NIC"
table <ext_ips> { $PUBLIC_IP4 $PUBLIC_IP6 }
table <bruteforce>  persist

# default route to the internet for jails
nat on \$ext_if from $JAIL_NET_PREFIX.0${JAIL_NET_MASK} to any -> (\$ext_if)

# POP3 & IMAP traffic to dovecot jail
rdr proto tcp from any to <ext_ips> port { 110 143 993 995 } -> $(get_jail_ip dovecot)

# SMTP traffic to the Haraka jail
rdr proto tcp from any to <ext_ips> port { 25 465 587 } -> $(get_jail_ip haraka)

# HTTP traffic to HAproxy
rdr proto tcp from any to <ext_ips> port { 80 443 } -> $(get_jail_ip haproxy)

# DHCP traffic
rdr proto udp from any to any port { 67 68 } -> $(get_jail_ip dhcp)

block in quick from <bruteforce>
EO_PF_RULES

	_pf_loaded=$(kldstat -m pf | grep pf)
	if [ -n "$_pf_loaded" ]; then
		pfctl -f /etc/pf.conf 2>/dev/null || exit
	else
		kldload pf
	fi

	sysrc pf_enable=YES
	/etc/rc.d/pf restart 2>/dev/null || exit
}

install_jailmanage()
{
	if [ -s /usr/local/sbin/jailmanage ]; then return; fi

	tell_status "installing jailmanage"
	fetch -o /usr/local/sbin/jailmanage https://raw.githubusercontent.com/msimerson/jailmanage/master/jailmanage.sh
	chmod 755 /usr/local/sbin/jailmanage || exit
}

set_jail_start_order()
{
	if grep -q ^jail_list /etc/rc.conf; then
		tell_status "preserving jail order"
		return
	fi

	tell_status "setting jail startup order"
	sysrc jail_list="$JAIL_STARTUP_LIST"
}

jail_reverse_shutdown()
{
	local _fbsd_major; _fbsd_major=$(freebsd-version | cut -f1 -d'.')
	if [ "$_fbsd_major" == "11" ]; then
		if grep -q jail_reverse_stop /etc/rc.conf; then
			return
		fi
		tell_status "reverse jails when shutting down"
		sysrc jail_reverse_stop=YES
        return
	fi

	if grep -q _rev_jail_list /etc/rc.d/jail; then
		echo "rc.d/jail is already patched"
		return
	fi

	tell_status "patching jail so shutdown reverses jail order"
	patch -d / <<'EO_JAIL_RCD'
Index: etc/rc.d/jail
===================================================================
--- etc/rc.d/jail
+++ etc/rc.d/jail
@@ -516,7 +516,10 @@
 		command=$jail_program
 		rc_flags=$jail_flags
 		command_args="-f $jail_conf -r"
-		$jail_jls name | while read _j; do
+		for _j in $($jail_jls name); do
+			_rev_jail_list="${_j} ${_rev_jail_list}"
+		done
+		for _j in ${_rev_jail_list}; do
 			echo -n " $_j"
 			_tmp=`mktemp -t jail` || exit 3
 			$command $rc_flags $command_args $_j >> $_tmp 2>&1
@@ -532,6 +535,9 @@
 	;;
 	esac
 	for _j in $@; do
+		_rev_jail_list="${_j} ${_rev_jail_list}"
+	done
+	for _j in ${_rev_jail_list}; do
 		_j=$(echo $_j | tr /. _)
 		parse_options $_j || continue
 		if ! $jail_jls -j $_j > /dev/null 2>&1; then
EO_JAIL_RCD
}

enable_jails()
{
	sysrc jail_enable=YES
	jail_reverse_shutdown
	set_jail_start_order

	if grep -sq 'exec' /etc/jail.conf; then
		return
	fi

	jail_conf_header
}

update_ports_tree()
{
	tell_status "updating FreeBSD ports tree"
	portsnap fetch || exit

	if [ -d /usr/ports/mail/vpopmail ]; then
		portsnap update || portsnap extract || exit
	else
		portsnap extract || exit
	fi
}

update_freebsd() {

	if grep -q '^Components src' /etc/freebsd-update.conf; then
		tell_status "remove src from freebsd-update"
		sed -i .bak -e '/^Components/ s/src .*/world kernel/' /etc/freebsd-update.conf
	fi

	tell_status "updating FreeBSD with security patches"
	freebsd-update fetch install

	tell_status "updating FreeBSD pkg collection"
	pkg update || exit

	update_ports_tree
}

plumb_jail_nic()
{
	if [ "$JAIL_NET_INTERFACE" != "lo1" ]; then
		tell_status "plumb_jail_nic: using $JAIL_NET_INTERFACE"
		return;
	fi

	if ! grep -q cloned_interfaces /etc/rc.conf; then
		tell_status "plumb lo1 interface at startup"
		sysrc cloned_interfaces=lo1 || exit
	fi

	local _missing;
	_missing=$(ifconfig lo1 2>&1 | grep 'does not exist')
	if [ -n "$_missing" ]; then
		tell_status "plumb lo1 interface"
		ifconfig lo1 create || exit
	fi
}

assign_syslog_ip()
{
	if ! grep -q ifconfig_lo1 /etc/rc.conf; then
		tell_status "adding syslog IP to lo1"
		sysrc ifconfig_lo1="$JAIL_NET_PREFIX.1 netmask 255.255.255.0" || exit
	fi

	local _present
	_present=$(ifconfig lo1 2>&1 | grep "$JAIL_NET_PREFIX.1 ")
	if [ -z "$_present" ]; then
		echo "assigning $JAIL_NET_PREFIX.1 to lo1"
		ifconfig lo1 "$JAIL_NET_PREFIX.1" netmask 255.255.255.0 || exit
	fi
}

configure_etc_hosts()
{
	# this is really important since syslog does a DNS lookup for the remote
	# hosts DNS on *every* incoming syslog message.
	if grep -q "^$JAIL_NET_PREFIX" /etc/hosts; then
		tell_status "removing /etc/hosts toaster additions"
		sed -i .bak -e "/^$JAIL_NET_PREFIX.*/d" /etc/hosts
	fi

	tell_status "adding /etc/hosts entries"
	local _hosts

	for j in $JAIL_ORDERED_LIST;
	do
		_hosts="$_hosts
$(get_jail_ip $j)		$j"
	done

	echo "$_hosts" | tee -a "/etc/hosts"
}

configure_bourne_shell()
{
	if ! grep -q '^alias ll' /etc/profile; then
		tell_status "adding ll alias to /etc/profile"
		echo 'alias ll="ls -alFG"' | tee -a /etc/profile
	fi

	if ! grep -q ^PS1 /etc/profile; then
		tell_status "customizing bourne shell prompt"
		echo 'PS1="$(whoami)@$(hostname -s):\\w $ "' | tee -a /etc/profile
		echo 'PS1="$(whoami)@$(hostname -s):\\w # "' | tee -a /root/.profile
	fi
}

update_host() {
	update_freebsd
	configure_ntpd
	update_sendmail
	install_periodic_conf
	constrain_sshd_to_host
	plumb_jail_nic
	assign_syslog_ip
	update_syslogd
	check_global_listeners
	add_jail_nat
	configure_tls_certs
	enable_jails
	install_jailmanage
	configure_etc_hosts
	configure_bourne_shell
	echo; echo "Success! Your host is ready to install Mail Toaster 6!"; echo
}

update_host
