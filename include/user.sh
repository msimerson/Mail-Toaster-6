#!/bin/sh



preserve_passdb()
{
	if [ -z "$1" ]; then
		echo "ERR: jail name is required"
		exit
	fi

	for _f in master.passwd group;
	do
		if [ -f "$ZFS_JAIL_MNT/$1/etc/$_f" ]; then
			tell_status "preserving /etc/$_f"
			cp "$ZFS_JAIL_MNT/$1/etc/$_f" "$STAGE_MNT/etc/"
			stage_exec pwd_mkdb -p /etc/master.passwd
		fi
	done
}


preserve_ssh_host_keys()
{
	if [ -z "$1" ]; then
		echo "ERR: jail name is required"
		exit
	fi

	if [ -f "$ZFS_JAIL_MNT/$1/etc/ssh/ssh_config" ]; then
		tell_status "preserving ssh host keys"
		cp "$ZFS_JAIL_MNT/$1/etc/ssh/ssh_host_*" "$STAGE_MNT/etc/ssh/"
	fi
}