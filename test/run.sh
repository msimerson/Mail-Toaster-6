#!/bin/sh

if [ -n "$1" ]; then
    bats "$1"
    exit
fi

# One shellcheck run per directory. Handing it every file at once makes it
# follow `. mail-toaster.sh` from each of the 70 provision scripts, which takes
# 20s instead of 2s.
echo "shellcheck *.sh"
shellcheck ./*.sh

echo "shellcheck contrib/*.sh"
shellcheck contrib/*.sh

echo "shellcheck include/*.sh"
shellcheck include/*.sh

echo "shellcheck provision/*.sh"
shellcheck provision/*.sh

# bats --jobs needs GNU parallel. Files run concurrently, tests within a file
# stay in order: they share the tree their setup_file built.
BATS_JOBS=""
if command -v parallel > /dev/null 2>&1; then
    _cpus=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
    BATS_JOBS="--jobs $_cpus --no-parallelize-within-files"
fi

# shellcheck disable=SC2086
bats $BATS_JOBS test/*.bats test/include/*.bats test/provision/*.bats test/contrib/*.bats
