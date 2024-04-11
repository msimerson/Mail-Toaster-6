#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

mt6-include mua

preflight_check()
{
	for _j in dns redis mongodb
	do
		if ! jail_is_running "$_j"; then
			fatal_err "jail $_j is required"
		fi
	done
}

install_wildduck()
{
	tell_status "installing wildduck dependencies"
	stage_pkg_install npm-node20 git-tiny || exit

	if [ ! -e "$STAGE_MNT/data/wildduck" ]; then
		tell_status "installing wildduck"
		stage_exec bash -c "cd /data && git clone https://github.com/nodemailer/wildduck.git wildduck"
		stage_exec bash -c "cd /data/wildduck && npm install --production"
	else
		tell_status "updating wildduck"
		stage_exec bash -c "cd /data/wildduck && git pull && npm install --production"
	fi
}

install_wildduck_webmail()
{
	if [ ! -e "$STAGE_MNT/data/wildduck-webmail" ]; then
		tell_status "installing wildduck webmail"
		stage_exec bash -c "cd /data && git clone https://github.com/nodemailer/wildduck-webmail.git wildduck-webmail"
		stage_exec bash -c "cd /data/wildduck-webmail && npm install"
		stage_exec bash -c "cd /data/wildduck-webmail && npm run bowerdeps"
	else
		tell_status "updating wildduck webmail"
		stage_exec bash -c "cd /data/wildduck-webmail && git pull && npm install && npm run bowerdeps"
		stage_exec bash -c "cd /data/wildduck-webmail && mkdir -p public/components"
		stage_exec bash -c "cd /data/wildduck-webmail && npx bower install --allow-root"
	fi
}

install_zonemta()
{
	_npm_ins="npm install --production --no-optional --no-package-lock --no-audit --ignore-scripts --no-shrinkwrap --progress=false --unsafe-perm"

	if [ ! -e "$STAGE_MNT/data/zone-mta" ]; then
		tell_status "installing ZoneMTA"
		stage_exec bash -c "cd /data && git clone https://github.com/zone-eu/zone-mta-template.git zone-mta"
		stage_exec bash -c "cd /data/zone-mta/plugins && git clone https://github.com/nodemailer/zonemta-wildduck.git wildduck"
		stage_exec bash -c "cd /data/zone-mta/plugins/wildduck && rm -f package-lock.json && $_npm_ins"
		stage_exec bash -c "cd /data/zone-mta && $_npm_ins"
	else
		tell_status "updating ZoneMTA"
		stage_exec bash -c "cd /data/zone-mta/plugins/wildduck && git pull && rm -f package-lock.json && $_npm_ins"
		stage_exec bash -c "cd /data/zone-mta && git pull && $_npm_ins"
	fi

	# stage_exec bash -c "cd /data/zone-mta && npm install zonemta-delivery-counters --save"
}

install_zonemta_webadmin()
{
	tell_status "installing ZoneMTA webadmin"
	if [ ! -e "$STAGE_MNT/data/zone-mta-admin" ]; then
		stage_exec bash -c "cd /data && git clone https://github.com/zone-eu/zmta-webadmin.git zone-mta-admin"
		stage_exec bash -c "cd /data/zone-mta-admin && npm install --production"
	else
		stage_exec bash -c "cd /data/zone-mta-admin && git pull && npm install --production"
	fi
}

install_haraka()
{
	local _npm_cmd="npm install --production --no-package-lock --no-audit --no-shrinkwrap"

	if [ ! -e "$STAGE_MNT/data/haraka" ]; then
		tell_status "installing haraka"
		stage_exec bash -c "cd /data && git clone https://github.com/haraka/Haraka.git haraka"
		stage_exec bash -c "cd /data/haraka && $_npm_cmd"
	else
		tell_status "updating haraka"
		stage_exec bash -c "cd /data/haraka && git pull && $_npm_cmd"
	fi

	if [ ! -e "$STAGE_MNT/data/haraka/plugins/wildduck" ]; then
		stage_exec bash -c "cd /data/haraka/plugins && git clone https://github.com/nodemailer/haraka-plugin-wildduck wildduck"
		stage_exec bash -c "cd /data/haraka/plugins/wildduck && npm install --omit=dev --omit=optional"
	fi
}

install_pm2()
{
	stage_exec npm install -g pm2
	stage_exec pm2 startup
	stage_sysrc pm2_toor_enable=YES
}

configure_tls()
{
	local _tls_dir="$STAGE_MNT/data/etc/tls"
	if [ ! -d "$_tls_dir" ];         then mkdir "$_tls_dir"         0755; fi
	if [ ! -d "$_tls_dir/certs" ];   then mkdir "$_tls_dir/certs"   0755; fi
	if [ ! -d "$_tls_dir/private" ]; then mkdir "$_tls_dir/private" 0700; fi

	if [ -f "/root/.acme/$WILDDUCK_HOSTNAME/$WILDDUCK_HOSTNAME.cer" ]; then
		install "/root/.acme/$WILDDUCK_HOSTNAME/fullchain.cer" "$_tls_dir/certs/$WILDDUCK_HOSTNAME.pem"
		install "/root/.acme/$WILDDUCK_HOSTNAME/$WILDDUCK_HOSTNAME.key" "$_tls_dir/private/$WILDDUCK_HOSTNAME.pem"
	fi
}

configure_wildduck()
{
	local _cfg="$STAGE_MNT/data/wildduck/config"

	if grep -qE '^mongo.*127' "$_cfg/dbs.toml"; then
		tell_status "configuring $_cfg/dbs.toml"
		sed -i '' \
			-e "/^mongo/ s/127.0.0.1/$(get_jail_ip mongodb)/" \
			-e "/^#redis/ s/127.0.0.1/$(get_jail_ip redis)/; s|/3|/9|" \
			-e "/^host=/ s/127.0.0.1/$(get_jail_ip redis)/" \
			-e "/^db=3/ s/3/9/" \
			"$_cfg/dbs.toml"

		if [ -z ${WILDDUCK_MONGO_DSN+x} ]; then
			tell_status "If Mongo requires AUTH, you should set WILDDUCK_MONGO_DSN"
		else
			sed -i '' \
				-e "/^mongo/ s|=.*$|=\"$WILDDUCK_MONGO_DSN\"|" \
				"$_cfg/dbs.toml"
		fi
	fi

	if ! grep -q "$WILDDUCK_HOSTNAME" "$_cfg/default.toml"; then
		tell_status "configuring $_cfg/default.toml"
		sed -i '' \
			-e '/^#emailDomain/ s/^#//' \
			-e "/^emailDomain/ s/mydomain.info/$WILDDUCK_MAIL_DOMAIN/" \
			-e "/rpId/ s/example.com/$WILDDUCK_MAIL_DOMAIN/" \
			-e "/^hostname/ s/localhost/$WILDDUCK_HOSTNAME/" \
			-e '/^port/ s/2587/587/' \
			"$_cfg/default.toml"
	fi

	if ! grep -q "$TOASTER_ORG_NAME" "$_cfg/api.toml"; then
		tell_status "configuring $_cfg/api.toml"
		sed -i '' \
			-e "/^organization/ s/WildDuck Mail Services/$TOASTER_ORG_NAME/" \
			"$_cfg/api.toml"
	fi

	if ! grep -q "$WILDDUCK_HOSTNAME" "$_cfg/imap.toml"; then
		tell_status "configuring $_cfg/imap.toml"
		sed -i '' \
			-e '/^host =/ s/0.0.0.0//' \
			-e '/^port/ s/9993/993/' \
			-e "/^hostname/ s/localhost/$WILDDUCK_HOSTNAME/" \
			"$_cfg/imap.toml"
	fi

	if ! grep -q "$WILDDUCK_HOSTNAME" "$_cfg/lmtp.toml"; then
		tell_status "configuring $_cfg/lmtp.toml"
		sed -i '' \
			-e '/^enabled/ s/false/true/' \
			-e '/^host/ s/127.0.0.1//' \
			-e '/^port/ s/2424/24/' \
			-e "/^name/ s/false/\"$WILDDUCK_HOSTNAME\"/" \
			"$_cfg/lmtp.toml"
	fi

	if ! grep -q "$WILDDUCK_HOSTNAME" "$_cfg/pop3.toml"; then
		tell_status "configuring $_cfg/pop3.toml"
		sed -i '' \
			-e '/^host =/ s/0.0.0.0//' \
			-e '/^port/ s/9995/995/' \
			-e "/^hostname/ s/localhost/$WILDDUCK_HOSTNAME/" \
			"$_cfg/pop3.toml"
	fi

	if ! grep -q ^secret "$_cfg/dkim.toml"; then
		tell_status "configuring $_cfg/dkim.toml"
		echo "secret = \"$(get_random_pass 14)\"" >> "$_cfg/dkim.toml"
	fi

	if ! grep -q "$WILDDUCK_HOSTNAME" "$_cfg/tls.toml"; then
		tell_status "installing $_cfg/tls.toml"
		cat <<EO_TLS_CFG "$_cfg/tls.toml"
key="/data/etc/tls/private/$WILDDUCK_HOSTNAME.pem"
cert="/data/etc/tls/certs/$WILDDUCK_HOSTNAME.pem"
dhparam="/etc/ssl/dhparam.pem"
ca=["/usr/local/share/certs/ca-root-nss.crt"]
EO_TLS_CFG
	fi
}

configure_wildduck_webmail()
{
	local _cfg="$STAGE_MNT/data/wildduck-webmail/config"

	if ! grep -q "$JAIL_NET_PREFIX" "$_cfg/default.toml"; then
		tell_status "configuring $_cfg/default.toml"
		sed -i '' \
			-e "/^name=/ s/Wild Duck/$TOASTER_ORG_NAME/" \
			-e '/^title=/ s/wildduck-www/wildduck-webmail/' \
			-e "/domain/ s/localhost/$WILDDUCK_MAIL_DOMAIN/" \
			-e "/redis=/ s/127.0.0.1/$(get_jail_ip redis)/; s|/5|/9|" \
			-e '/host=/ s/false/""/' \
			-e '/proxy=/ s/false/true/' \
			-e '/secret=/ s/a cat/a secret elephant cat/' \
			-e "/hostname=/ s/localhost/$WILDDUCK_HOSTNAME/" \
			-e '/port=/ s/=2587/=587/; s/=9993/=993/; s/=9995/=995/' \
			"$_cfg/default.toml"
	fi
}

configure_zonemta()
{
	tell_status "configure zonemta-wildduck"
	local _cfg="$STAGE_MNT/data/zone-mta/config"

	if ! grep -q "$JAIL_NET_PREFIX" "$_cfg/dbs-production.toml"; then
		tell_status "configuring $_cfg/dbs-production.toml"
		sed -i '' \
			-e "/^mongo/ s/127.0.0.1/$(get_jail_ip mongodb)/" \
			-e "/^redis/ s/localhost/$(get_jail_ip redis)/; s|/2|/9|" \
			"$_cfg/dbs-production.toml"

		if [ -z ${ZONEMTA_MONGO_DSN+x} ]; then
			tell_status "If Mongo requires AUTH, you should set ZONEMTA_MONGO_DSN"
		else
			sed -i '' \
				-e "/^mongo/ s|=.*$|=\"$ZONEMTA_MONGO_DSN\"|" \
				"$_cfg/dbs-production.toml"
		fi

		echo "# @include \"/data/wildduck/config/dbs.toml\"" \
			>> "$_cfg/dbs-production.toml"
	fi

	if ! grep -q "$JAIL_NET_PREFIX" "$_cfg/dbs-development.toml"; then
		tell_status "configuring $_cfg/dbs-development.toml"
		sed -i '' \
			-e "/^mongo/   s/127.0.0.1/$(get_jail_ip mongodb)/" \
			-e "/^host = / s/localhost/$(get_jail_ip redis)/" \
			"$_cfg/dbs-development.toml"
	fi

	tell_status "disabling DNS cache"
	sed -i '' \
		-e '/^caching/ s/true/false/' \
		"$_cfg/dns.toml"

	tell_status "configuring $_cfg/interfaces/feeder.toml"
	# shellcheck disable=1003
	sed -i '' \
		-e '/^host/ s/127.0.0.1//' \
		-e '/^port=/ s/2525/587/' \
		-e '/^authentication=/ s/false/true/' \
		-e '/^#cert/a\'$'\n''# @include "/data/wildduck/config/tls.toml"' \
		"$_cfg/interfaces/feeder.toml"

	tell_status "configuring $_cfg/pools.toml"
	cat <<EO_POOLS > "$_cfg/pools.toml"
[[default]]
address="0.0.0.0"
name="$WILDDUCK_HOSTNAME"

[[default]]
address="::"
name="$WILDDUCK_HOSTNAME"
EO_POOLS

	# sed -i '' \
	# 	-e "/^secret/ s/super secret_value//" \
	# 	"$_cfg/plugins/loop-breaker.toml"

	tell_status "configuring $_cfg/zones/default.toml"
	sed -i '' \
		-e '/ignoreIPv6/ s/true/false/' \
		"$_cfg/zones/default.toml"

	tell_status "configuring $_cfg/plugins/wildduck.toml"
	cat <<EO_WILDDUCK > "$_cfg/plugins/wildduck.toml"
[wildduck]
enabled=["receiver", "sender"]

# which interfaces this plugin applies to
interfaces=["feeder"]

# optional hostname to be used in headers
# defaults to os.hostname()
hostname="$WILDDUCK_HOSTNAME"

# SRS settings for forwarded emails

[wildduck.srs]
    # Handle rewriting of forwarded emails
    enabled=true
    # SRS secret value. Must be the same as in the MX side
    #secret="haraka/config/wilduck.yaml.srs.secret"
    # SRS domain, must resolve back to MX
    rewriteDomain="$WILDDUCK_MAIL_DOMAIN"

[wildduck.dkim]
# share config with WildDuck installation
# @include "/data/wildduck/config/dkim.toml
EO_WILDDUCK
}

configure_zonemta_admin()
{
	sed -i '' \
		-e "/^mongo/ s/127.0.0.1/$(get_jail_ip mongodb)/" \
		-e "/^host/  s/localhost/$(get_jail_ip redis)/; s|/2|/9|" \
		-e "/^db = / s/2/9/" \
		"$STAGE_MNT/data/zone-mta-admin/config/default.toml"

	if [ -n "$ZONEMTA_MONGO_DSN" ]; then
		sed -i '' \
			-e "/^mongo/ s|\".*\"|\"$ZONEMTA_MONGO_DSN\"|" \
			"$STAGE_MNT/data/zone-mta-admin/config/default.toml"
	fi
}

configure_pf()
{
	local _pf_etc="$ZFS_DATA_MNT/wildduck/etc/pf.conf.d"

	get_public_ip
	get_public_ip ipv6

	store_config "$_pf_etc/rdr.conf" <<EO_PF_RDR
int_ip4 = "$(get_jail_ip wildduck)"
int_ip6 = "$(get_jail_ip6 wildduck)"

ext_ip4 = "$PUBLIC_IP4"
ext_ip6 = "$PUBLIC_IP6"

# mail traffic to wildduck
rdr inet  proto tcp from any to \$ext_ip4 port { 25 465 587 993 995 } -> \$int_ip4
rdr inet6 proto tcp from any to \$ext_ip6 port { 25 465 587 993 995 } -> \$int_ip6

# send HTTP traffic to haproxy
rdr inet  proto tcp from any to \$ext_ip4 port { 80 443 } -> $(get_jail_ip haproxy)
rdr inet6 proto tcp from any to \$ext_ip6 port { 80 443 } -> $(get_jail_ip6 haproxy)
EO_PF_RDR

	store_config "$_pf_etc/nat.conf" <<EO_PF_NAT
int_ip4 = "$(get_jail_ip wildduck)"
int_ip6 = "$(get_jail_ip6 wildduck)"

ext_if = "$PUBLIC_NIC"
ext_ip4 = "$PUBLIC_IP4"
ext_ip6 = "$PUBLIC_IP6"

nat on \$ext_if from \$int_ip4 to any -> \$ext_ip4
nat on \$ext_if from \$int_ip6 to any -> \$ext_ip6
EO_PF_NAT

	store_config "$_pf_etc/allow.conf" <<EO_PF_ALLOW
int_ip4 = "$(get_jail_ip wildduck)"
int_ip6 = "$(get_jail_ip6 wildduck)"
table <wildduck_int> persist { \$int_ip4, \$int_ip6 }
pass in quick proto tcp from any to <wildduck_int> port { 25 465 587 80 443 993 995 }

# ext_ip4 = "$PUBLIC_IP4"
# ext_ip6 = "$PUBLIC_IP6"
# table <wildduck_ext> persist { \$ext_ip4, \$ext_ip6 }
# pass in quick proto tcp from any to <wildduck_ext> port { 25 465 587 80 443 993 995 }
EO_PF_ALLOW
}

configure_haraka()
{
	tell_status "configuring Haraka"
	local _cfg="$ZFS_DATA_MNT/wildduck/haraka/config"

	tell_status "installing $_cfg/clamd.ini"
	cat <<EO_CLAM > "$_cfg/clamd.ini"
clamd_socket=$(get_jail_ip clamav):3310
timeout=29
[reject]
error=false
EO_CLAM

	tell_status "installing $_cfg/helo.checks.ini"
	cat <<EO_HELO > "$_cfg/helo.checks.ini"
[reject]
host_mismatch=false
EO_HELO

	echo "$WILDDUCK_HOSTNAME" > "$_cfg/me"
	echo "local_mx_ok=true" >> "$_cfg/outbound.ini"
	echo "wildduck" >> "$_cfg/plugins"

	tell_status "configuring $_cfg/plugins"
	# shellcheck disable=1003
	sed -i '' \
		-e '/^#process_title/ s/#//' \
		-e '/^# fcrdns/ s/^# //' \
		-e '/^#early_talker/ s/^#//' \
		-e '/^# tls/ s/# //' \
		-e '/^rcpt_to.in_host_list/ s/^rcpt/#rcpt/' \
		-e '/^#attachment/ s/^#//' \
		-e '/^#clamd/ s/^#//' \
		-e '/^#spamassassin/ s/^#//' \
		-e '/^spamassassin/ a\'$'\n''rspamd' \
		-e '/^queue/ s/queue/#queue/' \
		"$_cfg/plugins"

	tell_status "installing $_cfg/rspamd.ini"
	cat <<EO_RSPAMD > "$_cfg/rspamd.ini"
host = $(get_jail_ip rspamd)
add_headers = always

[header]
bar = X-Rspamd-Bar
report = X-Rspamd-Report
score = X-Rspamd-Score
spam = X-Rspamd-Spam

[check]
authenticated=true
private_ip=true
EO_RSPAMD

	get_public_ip

	sed -i '' \
		-e '/^;public_ip/ s/^;//' \
		-e "/^public_ip/ s/N.N.N.N/$PUBLIC_IP4/" \
		-e '/^;nodes/ s/^;//' \
		-e '/^nodes/ s/cpus/1/' \
		"$_cfg/smtp.ini"

	sed -i '' \
		-e '/^;spamd_socket/ s/^;//' \
		-e "/^spamd_socket/ s/127.0.0.1/$(get_jail_ip spamassassin)/" \
		-e '/^;spamd_user=first-recipient (see docs)/ s/^;//' \
		-e '/^spamd_user=first-recipient (see docs)/ s/ (see docs)//' \
		-e '/; reject_threshold/ s/; ?//' \
		-e '/; relay_reject_threshold/ s/; ?//' \
		"$_cfg/spamassassin.ini"

	tell_status "configuring $_cfg/tls.ini"
	# shellcheck disable=1003
	sed -i '' \
		-e "/^; key/ s/^; //; /^key=/ s|=.*$|=/data/etc/tls/private/$WILDDUCK_HOSTNAME.pem|" \
		-e "/^; cert/ s/^; //; /^cert=/ s|=.*$|=/data/etc/tls/certs/$WILDDUCK_HOSTNAME.pem|" \
		-e '/; dhparam/ s/; //; /^dhparam/ s|dhparams.pem|/etc/ssl/dhparam.pem|' \
		-e '/dhparam.pem/ a\'$'\n''ca=/usr/local/share/certs/ca-root-nss.crt' \
		"$_cfg/tls.ini"

	if [ ! -f "$_cfg/wildduck.yaml" ]; then
		tell_status "installing $_cfg/wildduck.yaml"
		sed \
			-e "/host:/ s/'127.0.0.1'/redis/" \
			-e "/db:/ s/3/9/" \
			-e "/mongodb:/ s/127.0.0.1/$(get_jail_ip mongodb)/" \
			"$ZFS_DATA_MNT/wildduck/haraka/plugins/wildduck/config/wildduck.yaml" \
			> "$_cfg/wildduck.yaml"
			# -e "/secret: / s/secret value/$TODO/" \
			# -e "/loopSecret: / s/secret value/$TODO/" \
	fi
}

start_wildduck()
{
	tell_status "starting wildduck"
	stage_exec service pm2_toor start
	stage_exec bash -c 'cd /data/wildduck && NODE_ENV=production pm2 start "node server.js" -n wildduck'
	stage_exec pm2 save
}

start_wildduck_webmail()
{
	stage_exec bash -c 'cd /data/wildduck-webmail && NODE_ENV=production pm2 start "node server.js" -n wildduck-webmail'
	stage_exec pm2 save
}

start_zonemta()
{
	tell_status "starting zonemta"
	stage_exec bash -c 'cd /data/zone-mta && NODE_ENV=production pm2 start "npm run start" -n zone-mta'
	stage_exec pm2 save
}

start_zonemta_webadmin()
{
	tell_status "starting zonemta webadmin"
	stage_exec bash -c 'cd /data/zone-mta-admin && NODE_ENV=production pm2 start "npm run start" -n zone-mta-admin'
	stage_exec pm2 save
}

start_haraka()
{
	tell_status "starting Haraka"
	stage_exec bash -c 'cd /data/haraka && NODE_ENV=production pm2 start "/data/haraka/bin/haraka -c /data/haraka" -n haraka'
	stage_exec pm2 save
}

test_wildduck()
{
	tell_status "testing wildduck"
	stage_listening 24 3
	stage_listening 993 3
	stage_listening 995 3

	# MUA_TEST_USER="postmaster@${WILDDUCK_MAIL_DOMAIN}"
	# MUA_TEST_PASS=$(jexec vpopmail /usr/local/vpopmail/bin/vuserinfo -C "${MUA_TEST_USER}")
	# MUA_TEST_HOST=$(get_jail_ip stage)

	# test_imap
	# test_pop3

	tell_status "testing wildduck API"
	stage_listening 8080 3

	tell_status "testing wildduck webmail"
	stage_listening 3000 3

	tell_status "testing ZoneMTA"
	stage_listening 587 3

	tell_status "testing ZoneMTA webadmin"
	stage_listening 8082 3

	tell_status "testing Haraka"
	stage_listening 25 3

	echo "it worked"
}

test_zonemta()
{
	tell_status "testing zonemta"
	stage_listening 2525 3
	echo "it worked"
	stage_listening 8082 3
	echo "it worked"
}

base_snapshot_exists || exit 1
preflight_check
create_staged_fs wildduck
start_staged_jail wildduck
install_wildduck
install_wildduck_webmail
install_zonemta
install_zonemta_webadmin
install_haraka
install_pm2
configure_tls
configure_wildduck
configure_wildduck_webmail
configure_zonemta
configure_zonemta_admin
configure_haraka
configure_pf
start_wildduck
start_wildduck_webmail
start_zonemta
start_zonemta_webadmin
start_haraka
test_wildduck
promote_staged_jail wildduck
