#!/bin/bash
set -e

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if [ -f "$REPO_ROOT/Gitepoch" ]; then
        export SOURCE_DATE_EPOCH=$(cat "$REPO_ROOT/Gitepoch")
    fi
fi

tar xvfz elilo-3.14-source.tar.gz
cd elilo
cp -rL ../debian .
dpkg-buildpackage -uc -us
cd -
rm -rf elilo
