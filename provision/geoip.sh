#!/bin/sh

. mail-toaster.sh || exit

preflight_check() {
	if [ -z "$MAXMIND_LICENSE_KEY" ]; then
		echo "ERROR: edit mail-toaster.conf and set MAXMIND_LICENSE_KEY"
		exit 1
	fi
}

install_geoip_geoipupdate()
{
	tell_status "install geoipupdate"
	stage_pkg_install geoipupdate || exit
}

install_geoip_mm_mirror()
{
	tell_status "install maxmind-geolite-mirror"
	stage_pkg_install npm-node16 || exit
	stage_exec npm set user 0
	stage_exec npm set -g unsafe-perm true
	stage_exec npm install -g maxmind-geolite-mirror || exit
}

install_geoip()
{
	for _d in etc db; do
		_path="$STAGE_MNT/data/$_d"
		[ -d "$_path" ] || mkdir "$_path"
	done

	for _suffix in mmdb dat; do
		for _db in "$STAGE_MNT"/data/*."$_suffix"; do
			mv "$_db" "$STAGE_MNT/data/db"
		done
	done

	if [ "$GEOIP_UPDATER" = "geoipupdate" ]; then
		install_geoip_geoipupdate
	else
		install_geoip_mm_mirror
	fi
}

configure_geoip_geoipupdate()
{
	tee "$_weekly/999.maxmind-geolite-mirror" <<EO_GEO
#!/bin/sh
export MAXMIND_DB_DIR=/data/db/
/usr/local/bin/geoipupdate
EO_GEO
}

configure_geoip_mm_mirror()
{
	tee "$_weekly/999.maxmind-geolite-mirror" <<EO_GEO_MM
#!/bin/sh
export MAXMIND_DB_DIR=/data/db/
export MAXMIND_LICENSE_KEY="$MAXMIND_LICENSE_KEY"
/usr/local/bin/node /usr/local/lib/node_modules/maxmind-geolite-mirror
EO_GEO_MM
}

geoip_periodic()
{
	_weekly="$STAGE_MNT/usr/local/etc/periodic/weekly"
	mkdir -p "$_weekly"
	if [ "$GEOIP_UPDATER" = "geoipupdate" ]; then
		configure_geoip_geoipupdate
	else
		configure_geoip_mm_mirror
	fi
	chmod 700 "$_weekly/999.maxmind-geolite-mirror"
}

configure_geoip()
{
	if [ -f "$ZFS_DATA_MNT/geoip/GeoIP.conf" ]; then
		tell_status "installing GeoIP.conf"
		cp "$ZFS_DATA_MNT/geoip/GeoIP.conf" "$STAGE_MNT/usr/local/etc"
	fi

	geoip_periodic
}

start_geoip()
{
	tell_status "mirroring GeoIP databases"
	if [ "$GEOIP_UPDATER" = "geoipupdate" ]; then
		stage_exec /usr/local/bin/geoipupdate
	else
		stage_exec env MAXMIND_DB_DIR=/data/db/ /usr/local/bin/maxmind-geolite-mirror
	fi
}

test_geoip()
{
	echo "testing geoip..."
	stage_exec ls /data/db/

	test -f "$STAGE_MNT/data/db/GeoLite2-Country.mmdb" || exit
	echo "it worked"
}

preflight_check
base_snapshot_exists || exit
create_staged_fs geoip
start_staged_jail geoip
install_geoip
configure_geoip
start_geoip
test_geoip
promote_staged_jail geoip
