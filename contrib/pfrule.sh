#!/bin/sh

# pfrule.sh
#
# Use pfctl to load and unload PF config files into named PF anchors.
# Config files are named for the anchor they'll be inserted
# at. See https://github.com/msimerson/Mail-Toaster-6/wiki/PF
#
# Matt Simerson, matt@tnpi.net, 2023-06

_etcpath="$(dirname -- "$( readlink -f -- "$0"; )";)"

usage() {
    echo "   usage: $0 [ load | unload ]"
    echo " "
    exit 1
}

for _f in "$_etcpath"/*.conf; do
    [ -f "$_f" ] || continue

    _anchor=$(basename $_f .conf)  # nat, rdr, allow
    _jailname=$(basename "$(dirname "$(dirname $_etcpath)")")

    case "$1" in
        "load" )
            _cmd="pfctl -a $_anchor/$_jailname -f $_f"
        ;;
        "unload" )
            _cmd="pfctl -a $_anchor/$_jailname -F all"
        ;;
        *) 
            usage
        ;;
    esac

    echo "$_cmd"
    $_cmd || exit 1
done

exit