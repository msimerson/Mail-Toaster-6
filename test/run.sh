#!/bin/sh

echo "shellcheck *.sh"
shellcheck ./*.sh

echo "shellcheck include/*.sh"
shellcheck include/*.sh

echo "shellcheck provision/*.sh"
shellcheck provision/*.sh

bats test/*.bats
bats test/include/*.bats
bats test/provision/*.bats