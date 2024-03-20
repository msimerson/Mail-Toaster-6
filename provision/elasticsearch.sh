#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA="enforce_statfs=1"
# shellcheck disable=2016
export JAIL_CONF_EXTRA="\n\t\tenforce_statfs = 1;"
export JAIL_FSTAB="fdescfs $ZFS_JAIL_MNT/elasticsearch/dev/fd fdescfs rw 0 0
proc     $ZFS_JAIL_MNT/elasticsearch/proc   procfs  rw 0 0"

create_data_dirs()
{
	for _dir in etc db log plugins run; do
		local _sub_dir=$STAGE_MNT/data/${_dir}
		if [ ! -d "$_sub_dir" ]; then
			tell_status "creating $_sub_dir"
			mkdir "$_sub_dir"
		fi
		chown 965:965 "$_sub_dir"
	done
}

install_elasticsearch5()
{
	tell_status "installing Elasticsearch"
	stage_pkg_install elasticsearch5 elasticsearch5-x-pack

	create_data_dirs

	tell_status "installing kibana"
	stage_pkg_install kibana5 kibana5-x-pack
}

install_elasticsearch6()
{
	tell_status "installing Elasticsearch"
	stage_pkg_install elasticsearch6

	create_data_dirs

	tell_status "installing kibana"
	stage_pkg_install kibana6

	if [ ! -d "$STAGE_MNT/usr/local/www/kibana6/config" ]; then
		mkdir "$STAGE_MNT/usr/local/www/kibana6/config"
	fi
	touch "$STAGE_MNT/usr/local/www/kibana6/config/kibana.yml"
	chown -R 80:80 "$STAGE_MNT/usr/local/www/kibana6"
}

install_elasticsearch7()
{
	tell_status "installing Elasticsearch"
	stage_pkg_install elasticsearch7 openjdk11
	stage_sysrc elasticsearch_java_home=/usr/local/openjdk11

	create_data_dirs

	tell_status "installing kibana"
	stage_pkg_install kibana7

	if [ ! -d "$STAGE_MNT/usr/local/www/kibana7/config" ]; then
		mkdir "$STAGE_MNT/usr/local/www/kibana7/config"
	fi
	touch "$STAGE_MNT/usr/local/www/kibana7/config/kibana.yml"
	chown -R 80:80 "$STAGE_MNT/usr/local/www/kibana7"
}

install_elasticsearch8()
{
	tell_status "installing Elasticsearch"
	stage_pkg_install elasticsearch8 openjdk17
	stage_sysrc elasticsearch_java_home=/usr/local/openjdk17

	create_data_dirs

	tell_status "installing kibana"
	stage_pkg_install kibana8

	if [ ! -d "$STAGE_MNT/usr/local/www/kibana8/config" ]; then
		mkdir "$STAGE_MNT/usr/local/www/kibana8/config"
	fi
	touch "$STAGE_MNT/usr/local/www/kibana8/config/kibana.yml"
	chown -R 80:80 "$STAGE_MNT/usr/local/www/kibana8"
}

install_elasticsearch()
{
	#install_elasticsearch5
	#install_elasticsearch6
	# install_elasticsearch7
	install_elasticsearch8
}

install_beats()
{
	stage_pkg_install beats8

	local _xcfg="$STAGE_MNT/usr/local/etc/beats/metricbeat.modules.d/elasticsearch-xpack.yml"
	cp "$STAGE_MNT/usr/local/share/examples/beats/metricbeat.modules.d/elasticsearch-xpack.yml.disabled" "$_xcfg"
	sed -i '' \
		-e "/hosts:/ s/localhost/$(get_jail_ip elasticsearch)/" \
		"$_xcfg"

	if ! stage_exec -c 'cd /usr/local/etc/beats && metricbeat modules enable elasticsearch-xpack'; then
		echo "KNOWN ERROR: see https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=272701"
		return
	fi
	stage_sysrc metricbeat_enable=YES
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
	mkdir -p "$STAGE_MNT/data/etc"
	echo "cp $_conf $_data_conf"
	cp "$_conf" "$_data_conf"
	chown 965 "$_data_conf"

	if [ ! -f "$STAGE_MNT/data/etc/jvm.options" ]; then
		if [ -f "$ZFS_JAIL_MNT/elasticsearch/usr/local/etc/elasticsearch/jvm.options" ]; then
			tell_status "preserving jvm.options"
			cp "$ZFS_JAIL_MNT/elasticsearch/usr/local/etc/elasticsearch/jvm.options" "$STAGE_MNT/data/etc/"
		else
			cp "$STAGE_MNT/usr/local/etc/elasticsearch/jvm.options" "$STAGE_MNT/data/etc/"
		fi
	fi

	if [ ! -f "$STAGE_MNT/data/etc/log4j2.properties" ]; then
		cp "$STAGE_MNT/usr/local/etc/elasticsearch/log4j2.properties" "$STAGE_MNT/data/etc/"
		chown 965 "$STAGE_MNT/data/etc/log4j2.properties"
	fi

	sed -i.bak \
		-e "/^#network.host:/ s/#//; s/192.168.0.1/$(get_jail_ip stage)/" \
		-e '/^#node.name/ s/^#//; s/node-1/stage/' \
		-e '/^#cluster.initial/ s/^#//; s/node-1/stage/; s/, "node-2"//' \
			"$_conf"

	sed -i.bak \
		-e "/^#network.host:/ s/#//; s/192.168.0.1/$(get_jail_ip elasticsearch)/" \
		-e '/^path.data: / s/var/data/' \
		-e '/^path.logs: / s/var/data/' \
		-e '/^path\./ s/\/elasticsearch//' \
		-e '/^#cluster_name/ s/^#//; s/my-application/mail-toaster/' \
		-e '/^#node.name/ s/^#//; s/node-1/mt1/' \
		-e '/^#cluster.initial/ s/^#//; s/node-1/mt1/; s/, "node-2"//' \
			"$_data_conf"

	tee -a "$_data_conf" <<EO_ES_CONF
xpack.security.enabled: false
EO_ES_CONF
}

configure_kibana()
{
	tell_status "configuring kibana"

	stage_sysrc kibana_syslog_output_enable=YES

	if [ -f "$STAGE_MNT/data/etc/kibana.yml" ]; then
		tell_status "preserving kibana.yml"
		return
	fi

	chown 80:80 "$STAGE_MNT/usr/local/etc/kibana/kibana.yml"

	tell_status "installing default kibana.yml"
	sed -i '' \
		-e 's/^#server.basePath: ""/server.basePath: "\/kibana"/' \
		"$STAGE_MNT/usr/local/etc/kibana/kibana.yml"

	cp "$STAGE_MNT/usr/local/etc/kibana/kibana.yml" "$STAGE_MNT/data/etc/"

	stage_sysrc kibana_enable=YES
}

start_elasticsearch()
{
	tell_status "configuring Elasticsearch"
	stage_sysrc elasticsearch_enable=YES

	tell_status "starting Elasticsearch"
	stage_exec service elasticsearch start

	tell_status "generating a Kibana setup token"
	echo
	export ES_JAVA_HOME=/usr/local/openjdk17
	stage_exec /usr/local/lib/elasticsearch/bin/elasticsearch-create-enrollment-token --scope kibana
	echo

	tell_status "starting Kibana"
	stage_exec service kibana start
	stage_exec bash -c "cd /usr/local/www/kibana8 && su -m www -c /usr/local/www/kibana8/bin/kibana"
	stage_exec service kibana start
}

test_elasticsearch()
{
	tell_status "testing Elasticsearch (listening 9200)"
	stage_listening 9200 10 3

	tell_status "testing Kibana (listening 5601)"
	echo "kibana has initial setup to do, it takes a few..."
	stage_listening 5601 30 5
}

post_configure()
{
	tell_status "switching configuration to /data"
	stage_sysrc elasticsearch_config=/data/etc
	stage_sysrc kibana_config=/data/etc/kibana.yml
}

base_snapshot_exists
create_staged_fs elasticsearch
start_staged_jail elasticsearch
install_elasticsearch
configure_elasticsearch
configure_kibana
start_elasticsearch
test_elasticsearch
install_beats
post_configure
promote_staged_jail elasticsearch
