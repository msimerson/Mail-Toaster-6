#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/minecraft/etc \$path/usr/local/etc/minecraft-server nullfs rw 0 0\";
		mount += \"$ZFS_DATA_MNT/minecraft/db \$path/var/db/minecraft-server nullfs rw 0 0\";"
export JAIL_FSTAB=""

install_minecraft()
{
	tell_status "installing java"
	stage_pkg_install openjdk21 || exit

	tell_status "installing minecraft dependencies"
	stage_pkg_install autoconf portconfig tmux zip || exit

	tell_status "installing minecraft"
	stage_make_conf games_minecraft-server 'games_minecraft-server_SET=DAEMON
games_minecraft-server_UNSET=STANDALONE'
	# export BATCH=${BATCH:="1"}
	stage_port_install games/minecraft-server || exit
}

configure_minecraft()
{
	tell_status "configuring minecraft"
	if [ ! -d "$ZFS_DATA_MNT/minecraft/etc" ]; then
		mkdir "$ZFS_DATA_MNT/minecraft/etc"
	fi
	if [ ! -d "$ZFS_DATA_MNT/minecraft/db" ]; then
		mkdir "$ZFS_DATA_MNT/minecraft/db"
	fi

	# stage_exec /usr/local/bin/minecraft-server
	stage_exec service minecraft onestart
	local _eula="$STAGE_MNT/usr/local/etc/minecraft-server/eula.txt"
	until [ -f "$_eula" ]; do
		echo "waiting for $_eula to appear"
		sleep 1
	done
	tell_status "accepting EULA"
	sed -i.bak -e '/^eula/ s/false/true/' "$_eula"
	echo "done"
	# stage_sysrc minecraft_memx=
	# stage_sysrc minecraft_mems=
}

start_minecraft()
{
	stage_sysrc minecraft_enable=YES
	stage_exec service minecraft start
	tell_status "starting minecraft"
	sleep 3
}

test_minecraft()
{
	tell_status "testing minecraft"
	stage_listening 25565 5 2
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs minecraft
start_staged_jail minecraft
install_minecraft
configure_minecraft
start_minecraft
test_minecraft
promote_staged_jail minecraft
