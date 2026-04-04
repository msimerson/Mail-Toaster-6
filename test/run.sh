#!/bin/sh

if [ -n "$1" ]; then
    bats "$1"
    exit
fi

echo "shellcheck *.sh"
shellcheck ./*.sh

echo "shellcheck contrib/*.sh"
shellcheck contrib/*.sh

echo "shellcheck include/*.sh"
shellcheck include/*.sh

echo "shellcheck provision/*.sh"
shellcheck provision/*.sh

bats test/*.bats
bats test/include/*.bats
bats test/provision/*.bats
