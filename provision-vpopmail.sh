#!/bin/sh

. mail-toaster.sh || exit

install_qmail()
{
	mkdir -p $STAGE_MNT/usr/local/etc/rc.d
	stage_pkg_install netqmail daemontools ucspi-tcp || exit
	stage_exec /var/qmail/scripts/enable-qmail

	sysrc -f $STAGE_MNT/etc/make.conf \
		mail_qmail_SET='BIG_CONCURRENCY_PATCH DNS_CNAME DOCS MAILDIRQUOTA_PATCH' \
		mail_qmail_UNSET=RCDLINK

	# TODO
	#stage_exec make -C /usr/ports/mail/qmail deinstall install clean
}

install_maildrop()
{
	stage_pkg_install maildrop
	fetch -o $STAGE_MNT/etc/mailfilter http://mail-toaster.com/install/mt6-mailfilter.txt
	chown 89:89 $STAGE_MNT/etc/mailfilter
	chmod 600 $STAGE_MNT/etc/mailfilter
}

install_vpopmail()
{
	install_qmail
	install_maildrop

	# stage_exec pw groupadd -n vpopmail -g 89
	# stage_exec pw useradd -n vpopmail -s /nonexistent -d /data -u 89 -g 89 -m -h-
	stage_pkg_install vpopmail || exit

	sysrc -f $STAGE_MNT/etc/make.conf mail_vpopmail_SET=CLEAR_PASSWD
	sysrc -f $STAGE_MNT/etc/make.conf mail_vpopmail_UNSET=ROAMING

	# TODO
	# stage_exec make -C /usr/ports/mail/vpopmail deinstall install clean
}

configure_vpopmail()
{
	local _local_etc="$STAGE_MNT/usr/local/etc"

	fetch -o - http://mail-toaster.com/install/mt6-qmail-run.txt | jexec $SAFE_NAME sh
	echo 'mail.example.com' > $STAGE_MNT/var/qmail/control/me

	# sed -i .bak -e 's/localhost/127.0.0.4/' $STAGE_MNT/usr/local/vpopmail/etc/vpopmail.mysql
	# sed -i .bak -e 's/root/vpopmail/' $STAGE_MNT/usr/local/vpopmail/etc/vpopmail.mysql
	# sed -i .bak -e 's/secret/pass.From.Mysql.Setup/' $STAGE_MNT/usr/local/vpopmail/etc/vpopmail.mysql

	echo; echo "Enter the 'main' domain of this server"; echo
	stage_exec /usr/local/vpopmail/bin/vadddomain
}

start_vpopmail()
{
	# stage_sysrc vpopmail_enable=YES
	# stage_exec service vpopmail start
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
