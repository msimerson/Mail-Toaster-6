#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""


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
	stage_pkg_install npm-node16 git-lite || exit

	tell_status "installing ZoneMTA"
	stage_exec bash -c "cd /data && git clone https://github.com/zone-eu/zone-mta-template.git zone-mta"
	stage_exec bash -c "cd /data/zone-mta && npm install eslint --save-dev"
	stage_exec bash -c "cd /data/zone-mta && npm init"
	stage_exec bash -c "cd /data/zone-mta && npm install --production"

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
	echo "nothing, yet"
}

start_zonemta()
{
	tell_status "starting zonemta"
	stage_exec bash -c "cd /data/zone-mta && npm start &"

	tell_status "starting zonemta webadmin"
	stage_exec bash -c "cd /data/admin && npm start &"
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
