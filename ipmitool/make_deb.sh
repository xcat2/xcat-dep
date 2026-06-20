#!/bin/bash
set -e

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if [ -f "$REPO_ROOT/Gitepoch" ]; then
        export SOURCE_DATE_EPOCH=$(cat "$REPO_ROOT/Gitepoch")
    fi
fi

VERSION=1.8.18

tar xvfz ipmitool-$VERSION.tar.gz
cd ipmitool-$VERSION
cp -rL ../debian .
HOST_ARCH=`uname -m`
if [ "$HOST_ARCH" = "ppc64le" ]; then
    HOST_ARCH="ppc64el"
elif [ "$HOST_ARCH" = "x86_64" ]; then
    HOST_ARCH="amd64"
else
    HOST_ARCH="amd64"
fi
TARGET_ARCH=$HOST_ARCH dpkg-buildpackage -uc -us
cd -
rm -rf ipmitool-$VERSION

