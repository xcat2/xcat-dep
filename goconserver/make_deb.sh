#!/bin/bash
set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VERSION=0.3.3
REPO=https://github.com/xcat2/goconserver.git
# Pinned upstream commit (xcat2/goconserver). goconserver 0.3.3 is UNRELEASED (newest tag is v0.3.2),
# so it exists only on master -- pin an immutable SHA instead of the moving branch so every matrix
# cell builds the SAME source and the build is reproducible (PR #63 review follow-up; matches the EL
# GOCONSERVER_REF in mockbuild-all.pl). Bump deliberately when uptaking a new goconserver.
REF=6166fe5ec1c5b3c20475e322a9f0e8e93c87e45f

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    if [ -f "$REPO_ROOT/Gitepoch" ]; then
        export SOURCE_DATE_EPOCH=$(cat "$REPO_ROOT/Gitepoch")
    fi
fi

if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    SNAP_TS=$(date -d "@$SOURCE_DATE_EPOCH" --utc '+%Y%m%d%H%M')
else
    SNAP_TS=$(date '+%Y%m%d%H%M')
fi
FULL_VERSION="${VERSION}-snap${SNAP_TS}"

WORKDIR=$(mktemp -d)
trap "rm -rf $WORKDIR" EXIT

echo "Cloning goconserver at pinned SHA $REF..."
# --branch does not accept a raw SHA; shallow-fetch the pinned commit by object id (GitHub allows
# reachable-SHA fetches) so the checkout is reproducible and no full history is pulled.
gc_dir="$WORKDIR/goconserver-$VERSION"
mkdir -p "$gc_dir"
git -C "$gc_dir" init -q
git -C "$gc_dir" remote add origin "$REPO"
git -C "$gc_dir" fetch -q --depth 1 origin "$REF"
git -C "$gc_dir" checkout -q FETCH_HEAD

cd "$WORKDIR/goconserver-$VERSION"

# etcd storage backend has broken deps with modern Go modules
rm -rf storage/etcd.go storage/etcd/

export GOPATH="$WORKDIR/gopath"
export GOCACHE="$WORKDIR/gocache"
export GOMODCACHE="$WORKDIR/gomodcache"
export CGO_ENABLED=0

go mod init github.com/xcat2/goconserver
# kr/pty is abandoned and its pty.Start sets Ctty in a way Go >=1.15 rejects
# ("Setctty set but Ctty not valid in child"), breaking rcons/goconserver on
# modern Go (noble ships go1.22). creack/pty is the maintained, API-compatible
# fork that fixes it.
go mod edit -replace github.com/kr/pty=github.com/creack/pty@v1.1.21
go mod tidy

cp -rL "$SCRIPT_DIR/debian" .

sed -i "s/Version=${VERSION}/Version=${FULL_VERSION}/g" debian/rules

if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    export DEBEMAIL="${DEBEMAIL:-xcat-build@xcat.org}"
    export DEBFULLNAME="${DEBFULLNAME:-xCAT Build}"
    deterministic_date=$(date -R -d "@$SOURCE_DATE_EPOCH" --utc)
    sed -i "1s/(.*)/(${FULL_VERSION})/" debian/changelog
    sed -i "s/^ -- .*/ -- $DEBFULLNAME <$DEBEMAIL>  $deterministic_date/" debian/changelog
else
    dch -v "$FULL_VERSION" -b -D unstable "Snap build for xCAT"
fi

dpkg-buildpackage -uc -us

echo "Built debs:"
ls "$WORKDIR"/*.deb
cp "$WORKDIR"/*.deb "$SCRIPT_DIR/../"
