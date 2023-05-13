#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_jekyll()
{
	tell_status "install jekyll"
	stage_pkg_install ruby rubygem-jekyll

	stage_exec gem install jekyll bundler
}

configure_jekyll()
{
	if [ -d "$STAGE_MNT/data/test" ]; then
		tell_status "jeykll site exists"
		return;
	fi

	tell_status "configuring jekyll"
	stage_exec bash -c "cd /data && jekyll new test"
}

start_jekyll()
{
	tell_status "starting up jekyll"
	stage_exec bash -c "cd /data/test && jekyll serve &"
}

test_jekyll()
{
	tell_status "testing jekyll"
	stage_listening 4000 3
}

base_snapshot_exists || exit
create_staged_fs jekyll
start_staged_jail jekyll
install_jekyll
configure_jekyll
start_jekyll
test_jekyll
promote_staged_jail jekyll
