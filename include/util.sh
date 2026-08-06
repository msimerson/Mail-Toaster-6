#!/bin/sh

# bump version when a change in mail toaster effects provision scripts
mt6_version() { echo "20260403"; }

tell_status() { echo; echo "   ***   $1   ***"; echo; }

mt6_version_check()
{
	if [ "$(uname)" != 'FreeBSD' ]; then return; fi

	if [ -d ".git" ]; then echo "v: $(mt6_version)"; return; fi

	local _github
	_github=$(fetch -o - -q "$TOASTER_SRC_URL/include/util.sh" | grep '^mt6_version(' | cut -f2 -d'"')
	if [ -z "$_github" ]; then
		echo "v: <failed lookup>"
		return
	else
		echo "v: $_github"
	fi

	local _this
	_this="$(mt6_version)"
	if [ -n "$_this" ] && [ "$_this" -lt "$_github" ]; then
		echo "NOTICE: updating mail-toaster.sh"
		mt6-update
	fi
}

dec_to_hex() { printf '%04x\n' "$1"; }

# BSD and GNU stat disagree on both the flag and the format specifier. Toasters
# run on FreeBSD; the test suite runs on Linux.
_file_mode()
{
	case "$(uname)" in
		Linux*) stat -c "%a" "$1" ;;
		*)      stat -f "%OLp" "$1" ;;
	esac
}

store_config()
{
	# $1 - path to config file, $2 - operation, STDIN is file contents
	local _operation=${2:-""}
	local _shadow="$1.mt6"

	# "update" reinstalls over a config that still matches what we generated
	# last run, so an untouched file picks up template changes while an edited
	# one is left alone. Answer this before the shadow is replaced below, or the
	# question becomes "does it match what we are about to write", which is a
	# different and far less useful one.
	local _pristine=""
	if [ -f "$1" ] && [ -f "$_shadow" ] && cmp -s "$1" "$_shadow"; then
		_pristine=1
	fi

	if [ ! -d "$(dirname "$1")" ]; then
		tell_status "creating $(dirname "$1")"
		mkdir -p "$(dirname "$1")"
	fi

	# A redirect onto an existing file keeps that file's mode, so a shadow left
	# at 600 by an earlier run would install $1 at 600 too. Recreate it instead,
	# so the mode always derives from umask, as it does on a first run.
	rm -f "$_shadow"
	cat - > "$_shadow"

	if [ ! -f "$1" ] || [ "$_operation" = "overwrite" ]; then
		tell_status "installing $1"
		cp "$_shadow" "$1"
	elif [ "$_operation" = "append" ]; then
		# an appended file is our content plus something else, so it never looks
		# pristine. Excluded deliberately rather than by falling through.
		cat "$_shadow" >> "$1"
	elif [ "$_operation" = "update" ] && [ -n "$_pristine" ]; then
		tell_status "updating unmodified $1"
		cp "$_shadow" "$1"
	else
		tell_status "preserving $1"
	fi

	# The shadow duplicates $1 verbatim, secrets included, tighten it after
	# the copy above, which takes its mode from the shadow.
	chmod 600 "$_shadow"
}

store_exec()
{
	# $1 - path to file, STDIN is file contents
	if [ ! -d "$(dirname "$1")" ]; then
		tell_status "creating $(dirname "$1")"
		mkdir -p "$(dirname "$1")" || exit 1
	fi

	tell_status "installing $1"
	cat - > "$1" || exit 1
	chmod 755 "$1"
}

get_random_pass()
{
	local _pass_len=${1:-"14"}
	local _strength=${2:-"good"}

	# Password Entropy = log2(charset_len^pass_len)
	case "$_strength" in
		strong)
			# https://unix.stackexchange.com/questions/230673/how-to-generate-a-random-string
			# more entropy with 94 ASCII chars but special chars are often problematic
			LC_ALL=C tr -dc '[:graph:]' </dev/urandom 2>/dev/null | head -c "$_pass_len"
			;;
		safe)
			# good entropy, limited by 62 alpha-num characters (no symbols)
			LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom 2>/dev/null | head -c "$_pass_len"
			;;
		*)
			# default, good, limited by base64 charset
			openssl rand -base64 "$((_pass_len + 4))" | head -c "$_pass_len"
			;;
	esac

	echo
}

freebsd_major()
{
	# with a root dir, report the target jail's version rather than the host's
	if [ -n "$1" ]; then
		chroot "$1" /bin/freebsd-version | cut -f1 -d.
	else
		/bin/freebsd-version | cut -f1 -d.
	fi
}

configure_pkg_latest()
{
	local _pkg_host="pkg.FreeBSD.org"

	if jail_is_running bsd_cache; then
		tell_status "switching pkg to bsd_cache"
		_pkg_host="pkg"
	fi

	local REPODIR="$1/usr/local/etc/pkg/repos"
	if [ -f "$REPODIR/FreeBSD.conf" ]; then return; fi

	local _repo_name="FreeBSD-ports"
	if [ "$(freebsd_major "$1")" -lt "15" ]; then _repo_name="FreeBSD"; fi

	tell_status "switching pkg from quarterly to latest"
	mkdir -p "$REPODIR"
	store_config "$REPODIR/FreeBSD.conf" "overwrite" <<EO_PKG
$_repo_name: {
  url: "pkg+http://$_pkg_host/\${ABI}/$TOASTER_PKG_BRANCH"
}
EO_PKG
}

preserve_file()
{
	local _jail_name=$1
	local _file_path=$2

	local _active_cfg="$ZFS_JAIL_MNT/$_jail_name/$_file_path"
	local _stage_cfg="${STAGE_MNT}/$_file_path"

	if [ -f "$_active_cfg" ]; then
		tell_status "preserving $_active_cfg"
		[ -d "$(dirname "$_stage_cfg")" ] || mkdir -p "$(dirname "$_stage_cfg")"
		cp -p "$_active_cfg" "$_stage_cfg" || return 1
		return
	fi

	if [ -d "$ZFS_JAIL_MNT/${_jail_name}.last" ]; then
		preserve_file "${_jail_name}.last" "$_file_path"
	fi
}

reverse_list()
{
	local _rev_list=""
	for _j in "$@"; do
		_rev_list="${_j} ${_rev_list}"
	done
	echo "$_rev_list"
}

enable_bsd_cache()
{
	if ! jail_is_running bsd_cache; then return; fi
	if ! jail_is_running dns; then return; fi

	# assure services are available
	sockstat -4 -6 -p 80 -q -j bsd_cache | grep -q . || return
	sockstat -4 -6 -p 53 -q -j dns | grep -q . || return

	tell_status "enabling bsd_cache"

	store_config "$STAGE_MNT/etc/resolv.conf" "overwrite" <<EO_RESOLV
nameserver $(get_jail_ip dns)
nameserver $(get_jail_ip6 dns)
EO_RESOLV

	local _repo_dir="$STAGE_MNT/usr/local/etc/pkg/repos"
	if [ ! -d "$_repo_dir" ]; then mkdir -p "$_repo_dir"; fi

	local _repo_name="FreeBSD-ports"
	if [ "$(freebsd_major "$STAGE_MNT")" -lt "15" ]; then _repo_name="FreeBSD"; fi

	store_config "$_repo_dir/FreeBSD.conf" <<EO_PKG_CONF
$_repo_name: {
	enabled: no
}
EO_PKG_CONF

	store_config "$_repo_dir/MT6.conf" <<EO_PKG_MT6
MT6: {
	url: "http://pkg/\${ABI}/$TOASTER_PKG_BRANCH",
	enabled: yes
}
EO_PKG_MT6

	# cache pkg audit vulnerability db
	sed_inplace \
		-e '/^#VULNXML_SITE/ s/^#//' \
		-e '/^VULNXML_SITE/ s/vuxml.freebsd.org/vulnxml/' \
		"$STAGE_MNT/usr/local/etc/pkg.conf"

	sed_inplace -e '/^ServerName/ s/update.FreeBSD.org/freebsd-update/' \
		"$STAGE_MNT/etc/freebsd-update.conf"
}
