#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

install_zonemta_webadmin()
{
	tell_status "installing ZoneMTA webadmin"
	stage_exec bash -c "cd /data && git clone https://github.com/zone-eu/zmta-webadmin.git admin"
	stage_exec bash -c "cd /data/admin && npm install --production"

	sed -i '' \
		-e "/^mongo/ s/127.0.0.1/$(get_jail_ip mongodb)/" \
		-e "/^host/  s/localhost/$(get_jail_ip redis)/; s/\/2/\/7/" \
		-e "/^db = / s/2/7/" \
		"$STAGE_MNT/data/admin/config/default.toml"
}

install_zonemta()
{
	tell_status "installing node.js"
	stage_pkg_install npm-node20 git-tiny

	tell_status "installing ZoneMTA"
	stage_exec bash -c "cd /data && git clone https://github.com/zone-eu/zone-mta-template.git zone-mta"
	stage_exec bash -c "cd /data/zone-mta && npm install eslint --save-dev"
	stage_exec bash -c "cd /data/zone-mta && npm init"
	stage_exec bash -c "cd /data/zone-mta && npm install --production"
	stage_exec bash -c "cd /data/zone-mta && npm install zonemta-wildduck --save"

	sed -i '' \
		-e "/^mongo/ s/127.0.0.1/$(get_jail_ip mongodb)/" \
		-e "/^redis/ s/localhost/$(get_jail_ip redis)/; s/\/2/\/7/" \
		"$STAGE_MNT/data/zone-mta/config/dbs-production.toml"

	sed -i '' \
		-e "/^mongo/   s/127.0.0.1/$(get_jail_ip mongodb)/" \
		-e "/^host = / s/localhost/$(get_jail_ip redis)/" \
		"$STAGE_MNT/data/zone-mta/config/dbs-development.toml"

	# stage_exec bash -c "cd /data/zone-mta && npm install zonemta-delivery-counters --save"

	install_zonemta_webadmin
}

configure_zonemta()
{
	stage_exec npm install -g pm2
	stage_exec pm2 startup
	stage_sysrc pm2_toor_enable=YES
	service pm2_toor start

	tell_status "TODO: configure zonemta-wildduck"
	echo "https://github.com/nodemailer/zonemta-wildduck"
}

start_zonemta()
{
	tell_status "starting zonemta"
	stage_exec bash -c 'cd /data/zone-mta && NODE_ENV=production pm2 start "npm run start" -n zone-mta'

	tell_status "starting zonemta webadmin"
	stage_exec bash -c 'cd /data/admin    && NODE_ENV=production pm2 start "npm run start" -n admin'

	stage_exec pm2 save
}

test_zonemta()
{
	tell_status "testing zonemta"
	stage_listening 2525 3
	echo "it worked"
	stage_listening 8082 3
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs zonemta
start_staged_jail zonemta
install_zonemta
configure_zonemta
start_zonemta
test_zonemta
promote_staged_jail zonemta
