#!/bin/sh

mt6-fetch()
{
	local _dir="$1"
	local _file="$2"

	if [ -z "$_dir" ] || [ -z "$_file" ]; then
		echo "FATAL: invalid args to mt6-fetch"; return 1
	fi

	if [ ! -d "$_dir" ]; then mkdir "$_dir"; fi

	fetch -o "$_dir" -m "$TOASTER_SRC_URL/$_dir/$2"
}
