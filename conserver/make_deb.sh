#!/bin/bash
set -e

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if [ -f "$REPO_ROOT/Gitepoch" ]; then
        export SOURCE_DATE_EPOCH=$(cat "$REPO_ROOT/Gitepoch")
    fi
fi

tar xvfz conserver-8.2.1.tar.gz
cd conserver-8.2.1
cp -rL ../debian .
dpkg-buildpackage -uc -us
cd -
rm -rf conserver-8.2.1
