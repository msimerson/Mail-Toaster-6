#!/bin/sh

if [ ! -d "coverage" ]; then
    mkdir -p coverage
fi

if [ ! -x "./test/bats/bin/bats" ]; then
    git submodule update --init --recursive
fi

kcov --exclude-pattern=test \
     --include-path=./include,./provision,./mail-toaster.sh \
     coverage \
    ./test/bats/bin/bats test/*.bats test/include/*.bats

echo; echo "ls coverage/*"
ls coverage/*

#echo; echo "find . -type f"
#find . -type f -maxdepth 1
