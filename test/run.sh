#!/bin/sh

echo "shellcheck *.sh"
shellcheck ./*.sh

echo "shellcheck provision/*.sh"
shellcheck provision/*.sh

echo "shellcheck include/*.sh"
shellcheck include/*.sh

bats test/*.bats
bats test/include/*.bats
