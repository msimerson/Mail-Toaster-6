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
	stage_pkg_install elasticsearch5 elasticsearch5-x-pack

	for dir in etc db log plugins; do
		if [ ! -d "$STAGE_MNT/data/${dir}" ]; then
			tell_status "creating $STAGE_MNT/data/${dir}"
			mkdir "$STAGE_MNT/data/${dir}"
			chown 965:965 "$STAGE_MNT/data/${dir}"
		fi
	done

	tell_status "installing kibana"
	stage_pkg_install kibana5 kibana5-x-pack
}

configure_elasticsearch()
{
	local _data_conf="$STAGE_MNT/data/etc/elasticsearch.yml"
	if [ -f "$_data_conf" ]; then
		tell_status "preserving installed elasticsearch.yml"
		return
	fi

	tell_status "installing elasticsearch.yml"
	local _conf="$STAGE_MNT/usr/local/etc/elasticsearch/elasticsearch.yml"
	echo "cp $_conf $_data_conf"
	cp "$_conf" "$_data_conf" || exit
	chown 965 "$_data_conf"

	# for ES < 5
#	if [ ! -f "$STAGE_MNT/data/etc/logging.yml" ]; then
#		cp "$STAGE_MNT/usr/local/etc/elasticsearch/logging.yml" "$STAGE_MNT/data/etc/"
#	fi

	if [ ! -f "$STAGE_MNT/data/etc/log4j2.properties" ]; then
		cp "$STAGE_MNT/usr/local/etc/elasticsearch/log4j2.properties" "$STAGE_MNT/data/etc/"
		chown 965 "$STAGE_MNT/data/etc/log4j2.properties"
	fi

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
	if [ -f "$STAGE_MNT/data/etc/kibana.yml" ]; then
		tell_status "preserving kibana.yml"
		return
	fi

	tell_status "installing kibana.yml"
	cp "$STAGE_MNT/usr/local/etc/kibana.yml" "$STAGE_MNT/data/etc/"
}

start_elasticsearch()
{
	tell_status "starting Elasticsearch"
	stage_sysrc elasticsearch_enable=YES
	stage_sysrc elasticsearch_min_mem=4g
	stage_sysrc elasticsearch_max_mem=4g
	stage_sysrc elasticsearch_heap_newsize=4g
	stage_exec service elasticsearch start

	tell_status "starting Kibana"
	stage_sysrc kibana_enable=YES
	stage_exec service kibana start
}

test_elasticsearch()
{
	tell_status "testing Elasticsearch (listening 9200)"
	stage_listening 9200 10 3

	# not so good things can happen if two ES instances access the data dir
	# so wait until just before promotion to switch the active config
	stage_sysrc elasticsearch_config=/data/etc

	tell_status "testing Kibana (listening 5601)"
	echo "kibana has initial setup to do, it make take a while..."
	stage_listening 5601 30 5
	stage_sysrc kibana_config=/data/etc/kibana.yml
}

base_snapshot_exists || exit
create_staged_fs elasticsearch
start_staged_jail elasticsearch
install_elasticsearch
configure_elasticsearch
configure_kibana
start_elasticsearch
test_elasticsearch
promote_staged_jail elasticsearch
