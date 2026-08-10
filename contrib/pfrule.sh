#!/bin/sh

set -eu

# pfrule.sh
#
# Matt Simerson, matt@tnpi.net, 2026-02
#
# Use pfctl to load and unload PF rules into named anchors from config
# files. See https://github.com/msimerson/Mail-Toaster-6/wiki/PF
#
#   pfrule.sh load|unload [jail] [-n]
#
# Naming the jail decouples the anchor name from the install location, so one
# copy can serve every jail. Omit it and the jail name comes from $0
#
# Rules live in $MT6_ETC/<jail>/pf.conf.d, on the host

SELF_DIR="$(dirname -- "$( readlink -f -- "$0"; )";)"

# jail.conf sets exec.clean, so exec.created gets no environment. The install
# location is the root, and jail.conf names it absolutely.
MT6_ETC="${MT6_ETC:-$SELF_DIR}"

usage() {
    echo "   usage: $0 [ load | unload ] [jail] [-n]"
    echo " "
    echo "   jail   name of the jail whose anchors to manage."
    echo "          Omit when pfrule lives in the jail's own rule directory."
    echo "   -n     preview, print the pfctl commands instead of running them"
    echo " "
    exit 1
}

case "${1:-}" in
    load|unload) OPERATION="$1"; shift ;;
    *)           usage ;;
esac

JAIL_NAME=""
PREVIEW=""
for _arg in "$@"; do
    case "$_arg" in
        -n) PREVIEW="-n" ;;
        -*) usage ;;
        *)  if [ -n "$JAIL_NAME" ]; then usage; fi
            JAIL_NAME="$_arg" ;;
    esac
done

# a per-jail copy lives at <data>/<jail>/etc/pf.conf.d/pfrule.sh
jail_name_from_path() {
    basename "$(dirname "$(dirname "$SELF_DIR")")"
}

resolve_etc_path() {
    if [ -n "${PFRULE_ETC:-}" ]; then
        echo "$PFRULE_ETC"
        return 0
    fi

    if [ -d "$MT6_ETC/$JAIL_NAME/pf.conf.d" ]; then
        echo "$MT6_ETC/$JAIL_NAME/pf.conf.d"
        return 0
    fi

    if [ "$(jail_name_from_path)" = "$JAIL_NAME" ]; then
        echo "$SELF_DIR"
        return 0
    fi

    return 1
}

if [ -z "$JAIL_NAME" ]; then
    JAIL_NAME="$(jail_name_from_path)"
fi

if [ -z "$JAIL_NAME" ]; then
    echo "$0: cannot determine the jail name, pass it as an argument" >&2
    exit 1
fi

# the name becomes a pf anchor, so hold it to what pfctl(8) will accept
case "$JAIL_NAME" in
    *[!A-Za-z0-9_.-]*)
        echo "$0: invalid jail name '$JAIL_NAME'" >&2
        exit 1 ;;
esac

# an unreadable PFRULE_ETC would leave every glob empty, so load and unload
# would both report success having touched no firewall state at all
if [ -n "${PFRULE_ETC:-}" ] && [ ! -d "$PFRULE_ETC" ]; then
    echo "$0: PFRULE_ETC is not a directory: $PFRULE_ETC" >&2
    exit 1
fi

if ! ETC_PATH="$(resolve_etc_path)"; then
    echo "$0: no rule directory for jail '$JAIL_NAME'" >&2
    exit 1
fi

cleanup() {
    if [ -f "$ETC_PATH/allow.conf" ]; then
        if [ -f "$ETC_PATH/filter.conf" ]; then
            echo "mv $ETC_PATH/allow.conf $ETC_PATH/allow.bak"
            mv "$ETC_PATH/allow.conf" "$ETC_PATH/allow.bak"
        else
            echo "mv $ETC_PATH/allow.conf $ETC_PATH/filter.conf"
            mv "$ETC_PATH/allow.conf" "$ETC_PATH/filter.conf"
        fi
    fi
}

load_tables() {
    for _f in "$ETC_PATH"/*.table; do
        [ -f "$_f" ] || continue
        _table_name=$(basename "$_f" .table)
        _hit=$(grep -El "^table[[:space:]]+\<$_table_name\>" /etc/pf.conf "$ETC_PATH"/*.conf 2>/dev/null || true)
        if [ -n "$_hit" ]; then
            echo "WARN: table $_table_name appears to ALSO exist in $_hit"
        fi
        do_cmd pfctl -t "$_table_name" -T replace -f "$_f"
    done
}

flush_tables() {
    for _f in "$ETC_PATH"/*.table; do
        [ -f "$_f" ] || continue
        _table_name=$(basename "$_f" .table)
        do_cmd pfctl -t "$_table_name" -T flush
    done
}

do_cmd() {
    if [ "$PREVIEW" = "-n" ]; then
        echo "$*"
    else
        "$@"
    fi
}

flush() {
    case "$1" in
        nat|rdr ) do_cmd pfctl -a "$2" -F nat   ;;
        filter  ) do_cmd pfctl -a "$2" -F rules ;;
    esac
}

cleanup

# load tables first, they may be referenced in anchored files
if [ "$OPERATION" = "load" ]; then load_tables; fi

for _anchor in binat nat rdr filter; do
    _f="$ETC_PATH/$_anchor.conf"
    [ -f "$_f" ] || continue

    case "$OPERATION" in
        "load"   ) do_cmd pfctl -a "$_anchor/$JAIL_NAME" -f "$_f" ;;
        "unload" ) flush "$_anchor" "$_anchor/$JAIL_NAME" ;;
    esac
done

if [ "$OPERATION" = "unload" ]; then flush_tables; fi
