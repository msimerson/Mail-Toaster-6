#!/bin/sh

. mail-toaster.sh || exit

export VPOPMAIL_OPTIONS="CLEAR_PASSWD"
#export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/vpopmail \$path/usr/local/vpopmail nullfs rw 0 0\";"

install_qmail()
{
	mkdir -p $STAGE_MNT/usr/local/etc/rc.d
	stage_pkg_install netqmail daemontools ucspi-tcp || exit
	stage_exec /var/qmail/scripts/enable-qmail

	grep qmail_SET $STAGE_MNT/etc/make.conf || \
		tee -a $STAGE_MNT/etc/make.conf <<EO_QMAIL_SET
mail_qmail_SET=DNS_CNAME DOCS MAILDIRQUOTA_PATCH
mail_qmail_UNSET=RCDLINK
EO_QMAIL_SET

	# stage_exec make -C /usr/ports/mail/qmail deinstall install clean
}

install_maildrop()
{
	stage_pkg_install maildrop
	fetch -o $STAGE_MNT/etc/mailfilter http://mail-toaster.com/install/mt6-mailfilter.txt
	chown 89:89 $STAGE_MNT/etc/mailfilter
	chmod 600 $STAGE_MNT/etc/mailfilter
}

install_vpopmail_port()
{
	if [ "$TOASTER_MYSQL" = "1" ]; then
		stage_pkg_install mysql56-client
		VPOPMAIL_OPTIONS="$VPOPMAIL_OPTIONS MYSQL VALIAS"
	fi

	grep -qs vpopmail_SET $STAGE_MNT/etc/make.conf || \
		tee -a $STAGE_MNT/etc/make.conf <<EO_VPOP_SET
mail_vpopmail_SET=$VPOPMAIL_OPTIONS
mail_vpopmail_UNSET=ROAMING
EO_VPOP_SET

	stage_pkg_install gmake gettext dialog4ports
	stage_exec make -C /usr/ports/mail/vpopmail deinstall install clean
}

install_vpopmail()
{
	install_qmail
	install_maildrop

	# stage_exec pw groupadd -n vpopmail -g 89
	# stage_exec pw useradd -n vpopmail -s /nonexistent -d /usr/local/vpopmail -u 89 -g 89 -m -h-

	stage_pkg_install vpopmail || exit
	install_vpopmail_port
}

install_vpopmail_mysql()
{
	local _init_db=1
	local _vpass=`openssl rand -hex 18`

	local _vpe="$STAGE_MNT/usr/local/vpopmail/etc/vpopmail.mysql"
	sed -i -e "s/localhost/$JAIL_NET_PREFIX.4/" $_vpe
	sed -i -e 's/root/vpopmail/' $_vpe
	sed -i -e "s/secret/$_vpass/" $_vpe

	local _grant='GRANT ALL PRIVILEGES ON vpopmail.* to'
	local _vpopmail_host=`get_jail_ip vpopmail`
	local _mysql_cmd="$_grant 'vpopmail'@'${_vpopmail_host}' IDENTIFIED BY '${_vpass}';"

	if mysql_db_exists vpopmail; then
		_init_db=0
	else
		_mysql_cmd="create database vpopmail; $_mysql_cmd"
	fi

	echo $_mysql_cmd | jexec mysql /usr/local/bin/mysql || exit
}

configure_vpopmail()
{
	local _local_etc="$STAGE_MNT/usr/local/etc"

	fetch -o - http://mail-toaster.com/install/mt6-qmail-run.txt | jexec $SAFE_NAME sh
	echo $TOASTER_HOSTNAME > $STAGE_MNT/var/qmail/control/me

	if [ "$TOASTER_MYSQL" = "1" ]; then
		install_vpopmail_mysql
	fi

	echo; echo "ATTN: Your postmaster password is..."; echo
	stage_exec /usr/local/vpopmail/bin/vadddomain -r14 $TOASTER_HOSTNAME
}

start_vpopmail()
{
}

test_vpopmail()
{
	echo "testing vpopmail..."
	sleep 1   # give the daemons a second to start listening
	stage_exec sockstat -l -4 | grep 89 || exit
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_data_fs vpopmail
create_staged_fs vpopmail
stage_sysrc hostname=vpopmail
start_staged_jail
install_vpopmail
configure_vpopmail
start_vpopmail
test_vpopmail
promote_staged_jail vpopmail
