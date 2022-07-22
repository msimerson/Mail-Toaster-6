#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_puppeteer()
{
	tell_status "install puppeteer"
	stage_pkg_install npm-node16 chromium

	stage_exec PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true npm install -g puppeteer
	stage_exec npm install -g https://github.com/msimerson/google-charts-node.git
}

configure_puppeteer()
{
	if [ -d "$STAGE_MNT/data/test" ]; then
		tell_status "puppeteer site exists"
		return;
	fi

	tell_status "configuring puppeteer"
	stage_exec bash -c "cd /data && puppeteer new test"
}

start_puppeteer()
{
	tell_status "starting up puppeteer"
	#stage_exec bash -c "cd /data/test && puppeteer serve &"
}

test_puppeteer()
{
	tell_status "testing puppeteer"
	#stage_listening 4000 3
}

base_snapshot_exists || exit
create_staged_fs puppeteer
start_staged_jail puppeteer
install_puppeteer
configure_puppeteer
start_puppeteer
test_puppeteer
promote_staged_jail puppeteer
