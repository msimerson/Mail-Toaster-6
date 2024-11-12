#!/bin/sh

# pfrule.sh
#
# Matt Simerson, matt@tnpi.net, 2024-11
#
# Use pfctl to load and unload PF rules into named anchors from config
# files. See https://github.com/msimerson/Mail-Toaster-6/wiki/PF

ETC_PATH="$(dirname -- "$( readlink -f -- "$0"; )";)"
JAIL_NAME=$(basename "$(dirname "$(dirname $ETC_PATH)")")
PREVIEW="$2"

usage() {
    echo "   usage: $0 [ load | unload ] [-n]"
    echo " "
    exit 1
}

cleanup() {
    if [ -f allow.conf ] && [ ! -f filter.conf ]; then
        echo "mv allow.conf filter.conf"
        mv allow.conf filter.conf
    fi
}

load_tables() {
    for _f in "$ETC_PATH"/*.table; do
        [ -f "$_f" ] || continue
        _table_name=$(basename $_f .table)
        do_cmd "pfctl -t "$_table_name" -T replace -f "$_f""
    done
}

flush_tables() {
    for _f in "$ETC_PATH"/*.table; do
        [ -f "$_f" ] || continue
        _table_name=$(basename $_f .table)
        do_cmd "pfctl -t "$_table_name" -T flush"
    done
}

do_cmd() {
    if [ "$PREVIEW" = "-n" ]; then
        echo "$1"
    else
        $1 || exit 1
    fi
}

flush() {
    case "$1" in
        "nat"   ) do_cmd "$2 -F nat"   ;;
        "rdr"   ) do_cmd "$2 -F nat"   ;;
        "filter") do_cmd "$2 -F rules" ;;
    esac
}

cleanup

# load tables first, they may be referenced in anchored files
if [ "$1" = "load" ]; then load_tables; fi

for _anchor in binat nat rdr filter; do
    _f="$ETC_PATH/$_anchor.conf"
    [ -f "$_f" ] || continue

    _pfctl="pfctl -a $_anchor/$JAIL_NAME"

    case "$1" in
        "load"   ) do_cmd "$_pfctl -f $_f" ;;
        "unload" ) flush "$_anchor" "$_pfctl" ;;
        *        ) usage                 ;;
    esac
done

if [ "$1" = "unload" ]; then flush_tables; fi

exit