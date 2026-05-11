#!/bin/bash
set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VERSION=0.3.3
REPO=https://github.com/xcat2/goconserver.git
REF=master

WORKDIR=$(mktemp -d)
trap "rm -rf $WORKDIR" EXIT

echo "Cloning goconserver..."
git clone --depth 1 --branch "$REF" "$REPO" "$WORKDIR/goconserver-$VERSION"

cd "$WORKDIR/goconserver-$VERSION"

# etcd storage backend has broken deps with modern Go modules
rm -rf storage/etcd.go storage/etcd/

export GOPATH="$WORKDIR/gopath"
export GOCACHE="$WORKDIR/gocache"
export GOMODCACHE="$WORKDIR/gomodcache"
export CGO_ENABLED=0

go mod init github.com/xcat2/goconserver
go mod tidy

cp -rL "$SCRIPT_DIR/debian" .

dpkg-buildpackage -uc -us

echo "Built debs:"
ls "$WORKDIR"/*.deb
cp "$WORKDIR"/*.deb "$SCRIPT_DIR/../"
