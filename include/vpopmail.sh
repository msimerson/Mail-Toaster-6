#!/bin/sh


install_vpopmail_port()
{
	local _vpopmail_deps="gmake gettext ucspi-tcp netqmail fakeroot"

	if [ "$TOASTER_MYSQL" = "1" ]; then
		tell_status "adding mysql dependency"
		if [ "$TOASTER_MARIADB" = "1" ]; then
			_vpopmail_deps="$_vpopmail_deps mariadb104-client"
		else
			_vpopmail_deps="$_vpopmail_deps mysql57-client"
		fi

		VPOPMAIL_OPTIONS_SET="$VPOPMAIL_OPTIONS_SET MYSQL VALIAS"
		VPOPMAIL_OPTIONS_UNSET="$VPOPMAIL_OPTIONS_UNSET CDB"
	fi

	local _installed_opts="$ZFS_JAIL_MNT/vpopmail/var/db/ports/mail_vpopmail/options"
	if [ -f "$_installed_opts" ]; then
		tell_status "preserving vpopmail port options"
		if [ ! -d "$STAGE_MNT/var/db/ports/mail_vpopmail" ]; then
			mkdir -p "$STAGE_MNT/var/db/ports/mail_vpopmail"
		fi
		cp "$_installed_opts" \
			"$STAGE_MNT/var/db/ports/mail_vpopmail/"
	fi

	if grep -qs ^mail_vpopmail_ "$ZFS_JAIL_MNT/vpopmail/etc/make.conf"; then
		tell_status "copying vpopmail options from vpopmail jail"
		grep ^mail_vpopmail "$ZFS_JAIL_MNT/vpopmail/etc/make.conf" >> "$STAGE_MNT/etc/make.conf"
	else
		tell_status "installing vpopmail port with custom options"
		stage_make_conf mail_vpopmail_ "
mail_vpopmail_SET=$VPOPMAIL_OPTIONS_SET
mail_vpopmail_UNSET=$VPOPMAIL_OPTIONS_UNSET
"
	fi

	tell_status "install vpopmail deps"
	stage_pkg_install $_vpopmail_deps

	if ! grep -qs ^CFLAGS "/usr/ports/mail/vpopmail/Makefile"; then
		# https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=257672
		tell_status "patching vpopmail Makefile"
		echo "CFLAGS+=	-fcommon" | tee -a "/usr/ports/mail/vpopmail/Makefile" || exit
	fi

	tell_status "installing vpopmail port with custom options"
	stage_exec make -C /usr/ports/mail/vpopmail build deinstall install clean
}

install_qmail()
{
	tell_status "installing qmail"
	stage_pkg_install netqmail daemontools ucspi-tcp || exit

	if [ -n "$TOASTER_QMHANDLE" ] && [ "$TOASTER_QMHANDLE" != "0" ]; then
		stage_pkg_install qmhandle || exit
		if [ -f "$ZFS_JAIL_MNT/vpopmail/usr/local/etc/qmHandle.conf" ]; then
			tell_status "preserving qmHandle.conf"
			cp "$ZFS_JAIL_MNT/vpopmail/usr/local/etc/qmHandle.conf" \
				"$STAGE_MNT/usr/local/etc/" || exit
		fi
	fi

	for _cdir in control users
	do
		local _vmdir="$ZFS_DATA_MNT/vpopmail/qmail-${_cdir}"
		if [ ! -d "$_vmdir" ]; then
			tell_status "creating $_vmdir"
			mkdir -p "$_vmdir" || exit
		fi

		local _qmdir="$STAGE_MNT/var/qmail/$_cdir"
		if [ -d "$_qmdir" ]; then
			tell_status "rm -rf $_qmdir"
			rm -rf "$_qmdir" || exit
		fi
	done

	tell_status "linking qmail control and user dirs"
	stage_exec ln -s /usr/local/vpopmail/qmail-control /var/qmail/control
	stage_exec ln -s /usr/local/vpopmail/qmail-users /var/qmail/users

	mkdir -p "$STAGE_MNT/usr/local/etc/rc.d"

	tell_status "setting qmail hostname to $TOASTER_HOSTNAME"
	echo "$TOASTER_HOSTNAME" > "$ZFS_DATA_MNT/vpopmail/qmail-control/me"

	if grep -qs ^mail_qmail_ "$ZFS_JAIL_MNT/vpopmail/etc/make.conf"; then
		tell_status "copying qmail port options from existing vpopmail jail"
		grep ^mail_qmail_ "$ZFS_JAIL_MNT/vpopmail/etc/make.conf" >> "$STAGE_MNT/etc/make.conf"
	else
		tell_status "setting custom options for qmail port"
		stage_make_conf mail_qmail_ 'mail_qmail_SET=DNS_CNAME DOCS MAILDIRQUOTA_PATCH
mail_qmail_UNSET=RCDLINK
'
	fi
	# stage_exec make -C /usr/ports/mail/qmail deinstall install clean
}
