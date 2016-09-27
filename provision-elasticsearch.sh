#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA="enforce_statfs=1"
# shellcheck disable=2016
export JAIL_CONF_EXTRA="
		mount.fdescfs;
		mount.procfs;
		enforce_statfs = 1;
		mount += \"$ZFS_DATA_MNT/elasticsearch \$path/data nullfs rw 0 0\";"

install_elasticsearch()
{
	tell_status "installing Elasticsearch"
	stage_pkg_install elasticsearch2

	tell_status "installing kopf plugin"
	stage_exec /usr/local/lib/elasticsearch/bin/plugin install lmenezes/elasticsearch-kopf

	if [ ! -d "$ZFS_DATA_MNT/elasticsearch/etc" ]; then
		mkdir "$ZFS_DATA_MNT/elasticsearch/etc"
	fi

	if [ ! -d "$ZFS_DATA_MNT/elasticsearch/db" ]; then
		mkdir "$ZFS_DATA_MNT/elasticsearch/db" || exit
		chown 965:965 "$ZFS_DATA_MNT/elasticsearch/db"
	fi

	if [ ! -d "$ZFS_DATA_MNT/elasticsearch/log" ]; then
		mkdir "$ZFS_DATA_MNT/elasticsearch/log" || exit
		chown 965:965 "$ZFS_DATA_MNT/elasticsearch/log"
	fi

	if [ ! -d "$ZFS_DATA_MNT/elasticsearch/plugins" ]; then
		mkdir "$ZFS_DATA_MNT/elasticsearch/plugins"
	fi

	tell_status "installing kibana"
	stage_pkg_install kibana45
}

configure_elasticsearch()
{
	local _data_conf="$ZFS_DATA_MNT/elasticsearch/etc/elasticsearch.yml"
	if [ -f "$_data_conf" ]; then
		tell_status "preserving installed elasticsearch.yml"
		return
	fi

	tell_status "installing elasticsearch.yml"
	local _conf="$STAGE_MNT/usr/local/etc/elasticsearch/elasticsearch.yml"
	cp "$_conf" "$_data_conf"
	chown 965 "$_data_conf"
	cp "$STAGE_MNT/usr/local/etc/elasticsearch/logging.yml" "$ZFS_DATA_MNT/elasticsearch/etc/"

	sed -i .bak \
		-e '/^path.data: / s/var/data/' \
		-e '/^path.logs: / s/var/data/' \
		-e '/^path\./ s/\/elasticsearch//' \
			"$_data_conf"

	tee -a "$_data_conf" <<EO_ES_CONF
path.conf: /data/etc
path.plugins: /data/plugins
EO_ES_CONF
}

configure_kibana()
{
	tell_status "configuring kibana"
	if [ -f "$ZFS_DATA_MNT/elasticsearch/etc/kibana.yml" ]; then
		tell_status "preserving kibana.yml"
		return
	fi

	cp "$STAGE_MNT/usr/local/etc/kibana.yml" "$ZFS_DATA_MNT/elasticsearch/etc/"
}

start_elasticsearch()
{
	tell_status "starting Elasticsearch"
	stage_sysrc elasticsearch_enable=YES
	stage_sysrc elasticsearch_config=/data/etc
	stage_exec service elasticsearch start

	tell_status "starting Kibana"
	stage_sysrc kibana_enable=YES
	stage_sysrc kibana_config=/data/etc/kibana.yml
	stage_exec service kibana start
}

test_elasticsearch()
{
	tell_status "waiting 10 seconds for ES to start"
	sleep 10

	tell_status "testing Elasticsearch (listening 9200)"
	stage_listening 9200

	tell_status "waiting 10 seconds for kibana to start"
	sleep 10

	tell_status "testing Kibana (listening 5601)"
	stage_listening 5601
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs elasticsearch
start_staged_jail
install_elasticsearch
configure_elasticsearch
configure_kibana
start_elasticsearch
test_elasticsearch
promote_staged_jail elasticsearch
