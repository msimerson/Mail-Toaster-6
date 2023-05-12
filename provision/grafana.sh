#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_grafana()
{
	tell_status "installing Grafana"
	stage_pkg_install grafana9 || exit
}

configure_grafana()
{
	for _d in etc db db/plugins logs; do
		if [ ! -d "$STAGE_MNT/data/$_d" ]; then
			tell_status "creating data/$_d dir"
			mkdir "$STAGE_MNT/data/$_d" || exit
			chown 904:904 "$STAGE_MNT/data/$_d"
		fi
	done

	local _gini="$STAGE_MNT/data/etc/grafana.ini"
	if [ ! -f "$_gini" ]; then
		tell_status "installing default grafana.ini"
		cp "$STAGE_MNT/usr/local/etc/grafana/grafana.ini" "$_gini" || exit

		sed -i '' \
			-e "/^;domain =/ s/localhost/${TOASTER_HOSTNAME}/" \
			-e '/^data =/ s/\/.*/\/data\/db/' \
			-e '/^logs =/ s/\/.*/\/data\/logs/' \
			-e '/^plugins =/ s/\/.*/\/data\/db\/plugins/' \
			-e "/^;root_url =/ s/= .*/= https:\/\/${TOASTER_HOSTNAME}\/grafana\//" \
			"$STAGE_MNT/data/etc/grafana.ini" || exit
	fi

	stage_sysrc grafana_config="/data/etc/grafana.ini"

	tell_status "Enabling Grafana"
	stage_sysrc grafana_enable=YES
}

start_grafana()
{
	stage_exec service grafana start
}

test_grafana()
{
	stage_test_running grafana
}

base_snapshot_exists || exit
create_staged_fs grafana
start_staged_jail grafana
install_grafana
configure_grafana
start_grafana
test_grafana
promote_staged_jail grafana
