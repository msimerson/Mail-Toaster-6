#!/bin/sh
#
# rebuild-ezmlm-subscribers.sh
#
# Rebuild every ezmlm-idx subscriber database so that each entry is hashed and
# formatted by the *currently installed* ezmlm-idx tools. Fixes the case where
# ezmlm-unsub (and qmailadmin's "delete user") report success but never remove
# legacy subscribers, because those records were written by an older ezmlm and
# live in the wrong hash bucket / old on-disk format.
#
# For each subscribers DB it:  ezmlm-list  ->  backup  ->  clear  ->  ezmlm-sub
#
# Runs a dry-run by default. Add --apply to make changes.
#
#   ./rebuild-ezmlm-subscribers.sh                 # dry run, default domains dir
#   ./rebuild-ezmlm-subscribers.sh --apply         # do it
#   ./rebuild-ezmlm-subscribers.sh --base=/path --apply

set -u

BASE="/usr/local/vpopmail/domains"
EZBIN="/usr/local/bin"
VUSER="vpopmail"
APPLY=0

for a in "$@"; do
	case "$a" in
		--apply)   APPLY=1 ;;
		--base=*)  BASE="${a#--base=}" ;;
		-h|--help)
			sed -n '2,20p' "$0"
			exit 0 ;;
		*) echo "unknown argument: $a" >&2; exit 2 ;;
	esac
done

if [ "$(id -u)" != "0" ]; then
	echo "must run as root (uses 'su - $VUSER')" >&2
	exit 1
fi

if [ ! -d "$BASE" ]; then
	echo "no such directory: $BASE" >&2
	exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="/var/backups/ezmlm-rebuild-$TS"
WORK="$(mktemp -d "/tmp/ezmlm-rebuild.XXXXXX")" || exit 1
DUMP="$WORK/dump"
trap 'rm -rf "$WORK"' EXIT

is_companion() {
	case "$1" in
		mod|deny|allow|digest) return 0 ;;
		*) return 1 ;;
	esac
}

n_ok=0; n_warn=0; n_skip=0; n_plan=0

# Enumerate every subscribers directory (main lists AND companion DBs).
find "$BASE" -type d -name subscribers 2>/dev/null | sort > "$WORK/dbs"

while IFS= read -r subs; do
	container="$(dirname "$subs")"
	cbase="$(basename "$container")"

	if is_companion "$cbase"; then
		listdir="$(dirname "$container")"
		sub="$cbase"
		label="$listdir [$sub]"
	else
		listdir="$container"
		sub=""
		label="$listdir"
	fi

	if [ -f "$listdir/sql" ]; then
		echo "SKIP  sql-backed   $label"
		n_skip=$((n_skip + 1))
		continue
	fi

	su -m "$VUSER" -c "$EZBIN/ezmlm-list '$listdir' $sub" 2>/dev/null \
		| grep '@' | sort -u > "$DUMP"
	before="$(wc -l < "$DUMP" | tr -d ' ')"

	if [ "$before" -eq 0 ]; then
		echo "skip  empty        $label"
		n_skip=$((n_skip + 1))
		continue
	fi

	if [ "$APPLY" -eq 0 ]; then
		echo "PLAN  rebuild $before   $label"
		n_plan=$((n_plan + 1))
		continue
	fi

	bkp="$BACKUP_ROOT$subs"
	mkdir -p "$(dirname "$bkp")"
	cp -Rp "$subs" "$bkp"

	su -m "$VUSER" -c "cd '$listdir' && rm -f '$subs'/* && \
		while IFS= read -r addr; do \
			$EZBIN/ezmlm-sub '$listdir' $sub \"\$addr\"; \
		done < '$DUMP'"

	after="$(su -m "$VUSER" -c "$EZBIN/ezmlm-list '$listdir' $sub" 2>/dev/null \
		| grep '@' | sort -u | wc -l | tr -d ' ')"

	if [ "$before" -eq "$after" ]; then
		echo "OK    $after subscribers   $label"
		n_ok=$((n_ok + 1))
	else
		echo "WARN  count $before -> $after   $label   (backup: $bkp)"
		n_warn=$((n_warn + 1))
	fi
done < "$WORK/dbs"

echo "------------------------------------------------------------"
if [ "$APPLY" -eq 0 ]; then
	echo "dry run: $n_plan database(s) would be rebuilt, $n_skip skipped."
	echo "re-run with --apply to make changes."
else
	echo "done: $n_ok rebuilt, $n_warn warnings, $n_skip skipped."
	echo "backups: $BACKUP_ROOT"
fi
