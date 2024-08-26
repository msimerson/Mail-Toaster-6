#!/bin/sh

# shellcheck disable=SC2044
for _f in $(find /data/vpopmail/ -type f -name .qmail); do

	# ignore files that don't specify maildrop
	if ! grep -q maildrop "$_f"; then continue; fi

	_lines=$(wc -l < "$_f" | bc)
	if [ "$_lines" = 1 ]; then
		# files with only a mailfilter rule can be deleted
		echo "$_lines: rm $_f"
		rm "$_f"
		continue
	fi

	# multiple delivery rules are in the file (see 'man dot-qmail')

	# extract all that isn't a maildrop invocation
	_contents=$(grep -v maildrop "$_f")

	# replace the maildrop rule with fully qualified path to Maildir
	_maildir="$(dirname "$_f" | sed -e 's|/data/vpopmail/home|/usr/local/vpopmail|')/Maildir/"

	echo "$_lines"
	echo "$_f"
	echo

	#echo "$_contents"
	#echo

	# write a new .qmail with the FQ Maildir + other delivery rules
	echo "$_contents" > "$_f.new" || exit 1
	echo "$_maildir" >> "$_f.new" || exit 1
	chown 89:89 "$_f.new" || exit 1
	chmod 600 "$_f.new" || exit 1

	# atomically replace the existing .qmail
	#echo "mv $_f.new $_f"
	#mv "$_f.new" "$_f"
done
