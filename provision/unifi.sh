#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB="fdescfs	$ZFS_JAIL_MNT/unifi/dev/fd	fdescfs	rw	0	0
$ZFS_DATA_MNT/unifi/java	$ZFS_JAIL_MNT/unifi/usr/local/share/java	nullfs	rw	0	0
proc	$ZFS_JAIL_MNT/unifi/proc	procfs	rw	0	0"

mt6-include network

create_unifi_mountpoints()
{
	if [ ! -d "$ZFS_JAIL_MNT/unifi/usr/local/share/java" ]; then
		mkdir -p "$ZFS_JAIL_MNT/unifi/usr/local/share/java"
	fi

	mkdir -p "$STAGE_MNT/usr/local/share/java"

	if [ ! -d "$ZFS_DATA_MNT/unifi/java" ]; then
		mkdir "$ZFS_DATA_MNT/unifi/java"
	fi
}

install_unifi()
{
	tell_status "installing Unifi deps"
	stage_pkg_install snappyjava openjdk17 gmake

	tell_status "installing Unifi"
	stage_make_conf unifi10_SET 'net-mgmt_unifi10_SET=EXTERNALDB'
	stage_port_install net-mgmt/unifi10

	tell_status "installing pf rule for acme.sh"
	store_config "$_pf_etc/filter.conf" <<EO_FILTER
pass in quick inet  proto tcp from any to $(get_jail_ip unifi) port 443
pass in quick inet6 proto tcp from any to $(get_jail_ip6 unifi) port 443
EO_FILTER

	install_acme_sh
	sed_inplace \
		-e 's|^#DEPLOY_UNIFI_KEYSTORE.*|DEPLOY_UNIFI_KEYSTORE="/data/java/unifi/data/keystore"|' \
		-e 's|^#DEPLOY_UNIFI_KEYPASS.*|DEPLOY_UNIFI_KEYPASS="aircontrolenterprise"|' \
		-e 's|^#DEPLOY_UNIFI_RELOAD.*|DEPLOY_UNIFI_RELOAD="service unifi restart"|' \
		-e 's|^#DEPLOY_UNIFI_SYSTEM_PROPERTIES.*|DEPLOY_UNIFI_SYSTEM_PROPERTIES="/data/java/unifi/data/system.properties"|' \
		"$STAGE_MNT/usr/local/share/examples/acme.sh/deploy/unifi.sh"

	tell_status "If your host has a FQDN, install a TLS cert as follows:"
	echo "  acme.sh --issue -d unifi.example.com --alpn --server letsencrypt"
	echo "  acme.sh -d unifi.example.com --deploy --deploy-hook unifi"
}

configure_unifi()
{
	tell_status "Enable UniFi"
	stage_sysrc unifi_enable=YES

	if [ -n "$UNIFI_MONGODB_DSN" ]; then

		if grep db.mongo.local "$DATA_MNT/unifi/java/unifi/data/system.properties" >/dev/null 2>&1; then
			tell_status "Preserving external MongoDB config"
		else
			tell_status "Configuring Unifi to use external MongoDB"
			store_config "$DATA_MNT/unifi/java/unifi/data/system.properties" <<EO_MONGO
db.mongo.local=false
db.mongo.uri=$UNIFI_MONGODB_DSN
statdb.mongo.uri=${UNIFI_MONGODB_DSN}_stat
unifi.db.name=unifi
EO_MONGO

			# tested in 2026
			cat <<EO_MONGO_SETUP
use unifi;
db.createUser({
	user: "ubnt",
	pwd: "<password>",
	roles:[
		{role: "userAdmin", db:"unifi"},
		{role: "readWrite", db:"unifi"},
		{role: "dbAdmin",   db:"unifi"},
		{ role: "readWrite",db: "unifi_stat" },
        { role: "dbAdmin",  db: "unifi_stat" },
		{ role: "readWrite",db: "unifi_audit" },
		{ role: "dbAdmin"  ,db: "unifi_audit" },
        { role: "readWrite" ,db: "unifi_restore" },
		{ role: "dbAdmin"   ,db: "unifi_restore" },
		{ role: "clusterMonitor", db:"admin"},
	]
});
EO_MONGO_SETUP

		fi
	fi
}

start_unifi()
{
	stage_exec service unifi start
}

test_unifi()
{
	stage_test_running java
	sleep 1
}

base_snapshot_exists || exit
create_staged_fs unifi
create_unifi_mountpoints
start_staged_jail unifi
install_unifi
configure_unifi
start_unifi
test_unifi
promote_staged_jail unifi
