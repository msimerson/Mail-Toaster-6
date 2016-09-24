#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

# shellcheck disable=2016
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/elasticsearch \$path/data nullfs rw 0 0\";"

install_elasticsearch()
{
	tell_status "installing Elasticsearch"
	stage_pkg_install elasticsearch2

    tell_status "install kopf plugin"
    stage_pkg_install /usr/local/bin/elasticsearch-plugin lmenezes/elasticsearch-kopf

    tell_status "installing kibana"
    stage_pkg_install kibana45
}

configure_elasticsearch()
{
    local _data_conf="$ZFS_DATA_MNT/elasticsearch/etc/elasticsearch.yml"
    if [ ! -f "$_data_conf" ]; then
        tell_status "preserving installed elasticsearch.yml"
        return
    fi

    tell_status "installing elasticsearch.yml"
    local _conf="$STAGE_MNT/usr/local/etc/elasticsearch/elasticsearch.yml"
    cp "$_conf" "$_data_conf"

    sed -i .bak \
        -e '/^path.data: / s/var/data/'
        -e '/^path.logs: / s/var/data/' \
        -e '/^path\. / s/\/elasticsearch//' \
            "$_data_conf"

    tee -a "$_data_conf" <<EO_ES_CONF
path.conf: /data/etc
path.plugins: /data/plugins
EO_ES_CONF
}

configure_kibana()
{
    tell_status "configuring kibana"
    
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
	tell_status "testing Elasticsearch"
    sleep 2
	stage_exec sockstat -l -4 | grep :9200 || exit
	echo "it worked"

    tell_status "testing Kibana"
    sleep 5
    stage_exec sockstat -l -4 | grep :5601 || exit
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
