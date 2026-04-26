#!/bin/sh

set -u

MODE="${1:-}"

case "$MODE" in
    --dry-run|--check|-n) MODE=dry ;;
    --ask|-i)             MODE=ask ;;
    --auto|-y)            MODE=auto ;;
    *)
        echo "Usage: $0 <mode>"
        echo "  -n, --dry-run, --check   Show what would be done, no changes"
        echo "  -i, --ask                Ask permission before each change"
        echo "  -y, --auto               Apply all changes automatically"
        exit 1
        ;;
esac

do_action() {
    _desc="$1"; shift
    if [ "$MODE" = dry ]; then
        echo "  [dry-run] $_desc"
        return 0
    fi
    if [ "$MODE" = ask ]; then
        printf '  Apply? [y/N] '
        read -r _ans </dev/tty
        case "$_ans" in
            [yY]*) ;;
            *) echo "  Skipped."; return 0 ;;
        esac
    fi
    echo "  [applying] $_desc"
    "$@"
}

_newtmp=$(mktemp)

find /usr/local/vpopmail/domains -type f -name .qmail | while IFS= read -r _f; do

    if grep -q maildrop "$_f" 2>/dev/null; then
        _has_maildrop=1
    else
        _has_maildrop=0
    fi

    if [ "$_has_maildrop" = 0 ]; then
        continue
    fi

    if _lines=$(wc -l < "$_f"); then
        _lines=$(printf '%s' "$_lines" | tr -d ' ')
    else
        echo "WARNING: could not read $_f, skipping"
        continue
    fi

    if [ "$_lines" = 1 ]; then
        echo "--- $_f (will be deleted)"
        sed 's/^/- /' "$_f"
        echo
        do_action "rm $_f" rm "$_f"
        continue
    fi

    if _contents=$(grep -v maildrop "$_f"); then
        :
    else
        echo "WARNING: grep -v maildrop failed on $_f, skipping"
        continue
    fi

    _maildir="$(dirname "$_f")/Maildir/"

    # write proposed new content to temp file for diffing
    printf '%s\n' "$_contents" > "$_newtmp"
    printf '%s\n' "$_maildir" >> "$_newtmp"

    echo "==> $_f"
    diff -u "$_f" "$_newtmp" \
        --label "$_f (current)" \
        --label "$_f (proposed)" \
        | tail -n +3
    echo

    do_action "rewrite $_f" sh -c "
        mv \"\$1\" \"\$2.new\"
        chown 89:89 \"\$2.new\"
        chmod 600 \"\$2.new\"
        mv \"\$2.new\" \"\$2\"
    " -- "$_newtmp" "$_f"

done