#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_jekyll()
{
	tell_status "install jekyll"
	stage_pkg_install ruby ruby26-gems rubygem-jekyll

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

install_jekyll_macosx()
{
	sudo port install ruby26 rb26-nokogiri
	sudo port select --set ruby ruby26

	ruby -r rubygems -e 'require "jekyll-import";
    JekyllImport::Importers::WordPress.run({
      "dbname"         => "wordpress_ms_simerson",
      "user"           => "jekyll",
      "password"       => "secret",
      "host"           => "mysql",
      "port"           => "3306",
      "socket"         => "",
      "table_prefix"   => "wp_",
      "site_prefix"    => "2_",
      "clean_entities" => true,
      "comments"       => true,
      "categories"     => true,
      "tags"           => true,
      "more_excerpt"   => true,
      "more_anchor"    => true,
      "extension"      => "html",
      "status"         => ["publish"]
    })'

	# GRANT SELECT ON wordpress_ms_simerson.* TO 'jekyll'@'172.16.15.55' IDENTIFIED BY 'secret';
}


base_snapshot_exists || exit
create_staged_fs jekyll
start_staged_jail jekyll
install_jekyll
configure_jekyll
start_jekyll
test_jekyll
promote_staged_jail jekyll
