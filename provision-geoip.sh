#!/bin/sh

. mail-toaster.sh || exit

export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/geoip \$path/usr/local/share/GeoIP nullfs rw 0 0\";"

install_geoip()
{
    tell_status "install GeoIP updater"
    stage_pkg_install npm || exit
    stage_exec npm install -g maxmind-geolite-mirror || exit
}

configure_geoip()
{
    stage_sysrc syslogd_enable=NO
    
    mkdir -p $STAGE_MNT/usr/local/etc/periodic/weekly
    stage_exec ln -s /usr/local/bin/maxmind-geolite-mirror \
        /usr/local/etc/periodic/weekly/999.maxmind-geolite-mirror
}

start_geoip()
{
    tell_status "mirroring GeoIP databases"
    stage_exec /usr/local/bin/maxmind-geolite-mirror
}

test_geoip()
{
	echo "testing geoip..."
	stage_exec ls /usr/local/share/GeoIP

    test -f $STAGE_MNT/usr/local/share/GeoIP/GeoIP.dat || exit
    echo "it worked"
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_data_fs geoip
create_staged_fs geoip
stage_sysrc hostname=geoip
start_staged_jail
install_geoip
configure_geoip
start_geoip
test_geoip
promote_staged_jail geoip
