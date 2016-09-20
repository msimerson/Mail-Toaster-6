#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit


install_sphinxsearch()
{
	tell_status "installing Sphinxsearch"
	stage_pkg_install sphinxsearch || exit
	stage_make_conf textproc_sphinxsearch   'textproc_sphinxsearch_SET=ID64'

	stage_pkg_install dialog4ports || exit
	
	tell_status "Compiling Sphinx search"

	export BATCH=${BATCH:="1"}
	stage_exec make -C /usr/ports/textproc/sphinxsearch  deinstall install clean || exit
}

start_sphinxsearch()
{
	tell_status "Enable Sphinxsearch"
	stage_sysrc sphinxsearch_enable=YES

	#stage_exec service sphinxsearch start

}

base_snapshot_exists || exit
create_staged_fs sphinxsearch
start_staged_jail
install_sphinxsearch
start_sphinxsearch
promote_staged_jail sphinxsearch


