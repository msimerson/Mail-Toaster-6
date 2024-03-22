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

install_webmail()
{
	if [ ! -e "$STAGE_MNT/data/webmail" ]; then
		tell_status "installing wildduck webmail"
		stage_exec bash -c "cd /data && git clone https://github.com/nodemailer/wildduck-webmail.git webmail" || exit 1
		stage_exec bash -c "cd /data/webmail && npm install"
		stage_exec bash -c "cd /data/webmail && npm run bowerdeps"
	else
		tell_status "updating wildduck webmail"
		stage_exec bash -c "cd /data/webmail && git pull && npm install && npm run bowerdeps"
		stage_exec bash -c "cd /data/webmail && mkdir -p public/components && bower install --allow-root"
	fi
}

install_wildduck()
{
	tell_status "installing wildduck dependencies"
	stage_pkg_install npm-node20 git-tiny || exit

	if [ ! -e "$STAGE_MNT/data/webmail" ]; then
		tell_status "installing wildduck"
		stage_exec bash -c "cd /data && git clone https://github.com/nodemailer/wildduck.git" || exit 1
		stage_exec bash -c "cd /data/wildduck && npm install --production"
	else
		tell_status "updating wildduck"
		stage_exec bash -c "cd /data/wildduck && git pull && npm install --production"
	fi

	install_webmail
}

configure_pf()
{
	_pf_etc="$ZFS_DATA_MNT/wildduck/etc/pf.conf.d"

	store_config "$_pf_etc/rdr.conf" <<EO_PF_RDR
rdr proto tcp from any to <ext_ip4> port 993 -> $(get_jail_ip  wildduck) port 9993
rdr proto tcp from any to <ext_ip4> port 995 -> $(get_jail_ip  wildduck) port 9995
EO_PF_RDR

	store_config "$_pf_etc/allow.conf" <<EO_PF_ALLOW
mua_ports = "{ 993 995 9993 9995 }"
table <mua_servers> persist { $(get_jail_ip wildduck), $(get_jail_ip6 wildduck) }
pass in quick proto tcp from any to <mua_servers> port \$mua_ports
EO_PF_ALLOW
}

configure_wildduck()
{
	_db_cfg="$STAGE_MNT/data/wildduck/config/dbs.toml"
	if grep -qE '^mongo.*127' "$_db_cfg"; then
		sed -i '' \
			-e "/^mongo/ s/127.0.0.1/$(get_jail_ip mongodb)/" \
			-e "/^#redis/ s/127.0.0.1/$(get_jail_ip redis)/; s/\/3/\/8/" \
			-e "/^host=/ s/127.0.0.1/$(get_jail_ip redis)/" \
			-e "/^db=3/ s/3/8/" \
			"$_db_cfg"
	fi

	stage_exec npm install -g pm2
	stage_exec pm2 startup

	configure_pf
}

start_wildduck()
{
	tell_status "starting wildduck"
	stage_exec service pm2_toor start

	stage_exec bash -c 'cd /data/wildduck && NODE_ENV=production pm2 start "node server.js" -n wildduck'

	stage_exec bash -c 'cd /data/webmail && NODE_ENV=production pm2 start "node server.js" -n webmail'

	stage_exec pm2 save
}

test_wildduck()
{
	tell_status "testing wildduck"
	stage_listening 9993 3
	stage_listening 9995 3
	stage_listening 3000 3

	# MUA_TEST_USER="postmaster@${TOASTER_MAIL_DOMAIN}"
	# MUA_TEST_PASS=$(jexec vpopmail /usr/local/vpopmail/bin/vuserinfo -C "${MUA_TEST_USER}")
	# MUA_TEST_HOST=$(get_jail_ip stage)

	# test_imap
	# test_pop3
	echo "it worked"
}

base_snapshot_exists || exit 1
preflight_check
create_staged_fs wildduck
start_staged_jail wildduck
install_wildduck
configure_wildduck
start_wildduck
test_wildduck
promote_staged_jail wildduck
