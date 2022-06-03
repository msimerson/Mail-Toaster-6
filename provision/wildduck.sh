#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
		mount += \"$ZFS_DATA_MNT/wildduck \$path/data nullfs rw 0 0\";"


install_wildduck()
{
	tell_status "installing node.js"
	stage_pkg_install npm-node16 git-lite || exit

	tell_status "installing wildduck"
	stage_pkg_install dialog4ports
	stage_exec bash -c "cd /data && git clone git://github.com/nodemailer/wildduck.git && cd wildduck && npm install --production"
}

configure_wildduck()
{
	echo "nothing, yet"
}

start_wildduck()
{
	tell_status "starting wildduck"
	stage_exec service wildduck start || exit
}

test_imap()
{
	pkg install -y empty

	POST_USER="postmaster@${TOASTER_MAIL_DOMAIN}"
	POST_PASS=$(jexec vpopmail /usr/local/vpopmail/bin/vuserinfo -C "${POST_USER}")
	rm -f in out

	echo "testing IMAP AUTH as $POST_USER"

	# empty -v -f -i in -o out telnet "$(get_jail_ip stage)" 143
	empty -v -f -i in -o out openssl s_client -quiet -crlf -connect "$(get_jail_ip stage):9993"
	if [ ! -e out ]; then exit; fi
	empty -v -w -i out -o in "ready"             ". LOGIN $POST_USER $POST_PASS\n"
	empty -v -w -i out -o in "Logged in"         ". LIST \"\" \"*\"\n"
	empty -v -w -i out -o in "List completed"    ". SELECT INBOX\n"
	# shellcheck disable=SC2050
	if [ "has" = "some messages" ]; then
		empty -v -w -i out -o in "Select completed"  ". FETCH 1 BODY\n"
		empty -v -w -i out -o in "OK Fetch completed" ". LOGOUT\n"
	else
		empty -v -w -i out -o in "Select completed" ". LOGOUT\n"
	fi
	echo "Logout completed"
	if [ -e out ]; then exit; fi
}

test_pop3()
{
	pkg install -y empty

	POST_USER="postmaster@${TOASTER_MAIL_DOMAIN}"
	POST_PASS=$(jexec vpopmail /usr/local/vpopmail/bin/vuserinfo -C "${POST_USER}")
	rm -f in out

	echo "testing POP3 AUTH as $POST_USER"

	# empty -v -f -i in -o out telnet "$(get_jail_ip stage)" 110
	empty -v -f -i in -o out openssl s_client -quiet -crlf -connect "$(get_jail_ip stage):9995"
	if [ ! -e out ]; then exit; fi
	empty -v -w -i out -o in "\+OK." "user $POST_USER\n"
	empty -v -w -i out -o in "\+OK" "pass $POST_PASS\n"
	empty -v -w -i out -o in "OK Logged in" "list\n"
	empty -v -w -i out -o in "." "quit\n"

	if [ -e out ]; then exit; fi
}

test_wildduck()
{
	tell_status "testing wildduck"
	stage_listening 9993 3
	stage_listening 9995 3
	test_imap
	test_pop3
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs wildduck
start_staged_jail wildduck
install_wildduck
configure_wildduck
start_wildduck
test_wildduck
promote_staged_jail wildduck
