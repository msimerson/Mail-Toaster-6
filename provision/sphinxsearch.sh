#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_sphinxsearch()
{
	tell_status "installing Sphinxsearch"
	stage_pkg_install sphinxsearch || exit
	stage_make_conf textproc_sphinxsearch   'textproc_sphinxsearch_SET=ID64'

	tell_status "Compiling Sphinx search"

	export BATCH=${BATCH:="1"}
	stage_port_install textproc/sphinxsearch || exit
}

configure_sphinxsearch()
{
  local _dbdir="$ZFS_DATA_MNT/db"
  if [ ! -d "$_dbdir" ]; then
    mkdir -p "$_dbdir" || exit
  fi

  tell_status "Setting config to data mount"
  stage_sysrc sphinxsearch_conffile="/data/sphinx.conf"
  stage_sysrc sphinxsearch_user="www"
  stage_sysrc sphinxsearch_group="www"
  stage_sysrc sphinxsearch_dir="/data/db/"
}
start_sphinxsearch()
{
	tell_status "Enable Sphinxsearch"
	stage_sysrc sphinxsearch_enable=YES

	#stage_exec service sphinxsearch start

}

base_snapshot_exists || exit
create_staged_fs sphinxsearch
start_staged_jail sphinxsearch
install_sphinxsearch
configure_sphinxsearch
start_sphinxsearch
promote_staged_jail sphinxsearch
