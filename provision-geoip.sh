#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/geoip \$path/usr/local/share/GeoIP nullfs rw 0 0\";"

install_geoip()
{
	tell_status "install GeoIP updater"
	stage_pkg_install npm4 || exit
	stage_exec npm install -g maxmind-geolite-mirror || exit
}

configure_geoip()
{
	local _weekly="$STAGE_MNT/usr/local/etc/periodic/weekly"
	mkdir -p "$_weekly"
	tee "$_weekly/999.maxmind-geolite-mirror" <<EO_GEO
#!/bin/sh
/usr/local/bin/node /usr/local/lib/node_modules/maxmind-geolite-mirror
EO_GEO
	chmod 755 "$_weekly/999.maxmind-geolite-mirror"
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

	test -f "$STAGE_MNT/usr/local/share/GeoIP/GeoIP.dat" || exit
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs geoip
start_staged_jail geoip
install_geoip
configure_geoip
start_geoip
test_geoip
promote_staged_jail geoip
