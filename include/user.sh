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

