#!/bin/sh

test_imap_empty()
{
	pkg info | grep -q ^empty || pkg install -y empty

	if [ -f in ]; then rm -f in; fi
	if [ -f out ]; then rm -f out; fi

	# empty -v -f -i in -o out telnet "$MUA_TEST_HOST" 143
	empty -v -f -i in -o out openssl s_client -quiet -verify_quiet -crlf -connect "$MUA_TEST_HOST:993"
	if [ ! -e out ]; then exit; fi
	empty -v -w -i out -o in "ready"             ". LOGIN $MUA_TEST_USER $MUA_TEST_PASS"$'\n'
	empty -v -w -i out -o in "Logged in"         $'. LIST \"\" \"*\"\n'
	empty -v -w -i out -o in "List completed"    $'. SELECT INBOX\n'
	# shellcheck disable=SC2050
	if [ "has" = "some messages" ]; then
		empty -v -w -i out -o in "Select completed"  $'. FETCH 1 BODY\n'
		empty -v -w -i out -o in "OK Fetch completed" $'. LOGOUT\n'
	else
		empty -v -w -i out -o in "Select completed" $'. LOGOUT\n'
	fi
	echo "Logout completed"
	if [ -e out ]; then
		sleep 1
		if [ -e out ]; then exit; fi
	fi
}

test_imap_openssl()
{
	openssl s_client -quiet -verify_quiet -crlf -connect "$MUA_TEST_HOST:993" <<EOF
. login $MUA_TEST_USER $MUA_TEST_PASS
. LIST "" "*"
. SELECT INBOX
. LOGOUT
EOF
}

test_imap_curl()
{
	# shellcheck disable=SC2001
	curl -k -v --login-options 'AUTH=PLAIN' "imaps://$(echo $MUA_TEST_USER | sed -e 's/@/%40/'):${MUA_TEST_PASS}@${MUA_TEST_HOST}/"
}

test_imap()
{
	echo "testing IMAP AUTH as $MUA_TEST_USER"
	test_imap_curl
	# test_imap_openssl
	# test_imap_empty
}

test_pop3_empty()
{
	pkg info | grep -q ^empty || pkg install -y empty

	if [ -f in ]; then rm -f in; fi
	if [ -f out ]; then rm -f out; fi

	echo "testing POP3 AUTH as $MUA_TEST_USER"

	# empty -v -f -i in -o out telnet "$MUA_TEST_HOST" 110
	empty -v -f -i in -o out openssl s_client -quiet -crlf -connect "$MUA_TEST_HOST:995"
	if [ ! -e out ]; then exit; fi
	empty -v -w -i out -o in "\+OK." "user $MUA_TEST_USER"$'\n'
	empty -v -w -i out -o in "\+OK" "pass $MUA_TEST_PASS"$'\n'
	empty -v -w -i out -o in "OK Logged in" $'list\n'
	empty -v -w -i out -o in "." $'quit\n'

	if [ -e out ]; then
		sleep 1
		if [ -e out ]; then exit; fi
	fi
}

test_pop3()
{
	# shellcheck disable=SC2001
	curl -k -v --login-options 'AUTH=PLAIN' "pop3s://$(echo $MUA_TEST_USER | sed -e 's/@/%40/'):${MUA_TEST_PASS}@${MUA_TEST_HOST}/"
}