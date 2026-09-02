#!/usr/bin/env perl
# goconserver/sbuild.pl -- per-package Ubuntu/Debian builder for goconserver; the apt/sbuild analogue
# of goconserver/mockbuild.pl. Builds the package inside the matching <codename>-<arch>-sbuild chroot
# from its MAINTAINED debian/ packaging and collects the .deb(s) into --result-dir. Invoked by
# sbuild-all.pl per (codename,arch); also runnable standalone. Out-of-tree: the build runs on a COPY of
# the package tree (the checkout is never mutated). The common chroot orchestration lives in
# BuildUtils::build_deb_in_chroot; goconserver's source clone + Go toolchain + build is below.
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(basename);
use Getopt::Long qw(GetOptions);
use FindBin qw($RealBin);
use lib "$RealBin/..";
use BuildUtils qw(chroot_name build_deb_in_chroot);

my $pkg_dir = abs_path($RealBin);
my $pkg     = basename($pkg_dir);
my ($codename, $arch, $chroot, $result_dir, $log_dir) = ('', '', '', '', '');
my ($build_timestamp, $build_number, $skip_install) = (undef, undef, 0);
# --log-dir / --build-number / --skip-install are accepted for CLI-compat with sbuild-all.pl (which
# passes them uniformly to every per-package builder) but are intentionally UNUSED here: sbuild-all
# does its own per-package logging and there is no deb install-smoke. They are parsed and ignored.
GetOptions(
    'codename=s' => \$codename, 'arch=s' => \$arch, 'chroot=s' => \$chroot,
    'result-dir=s' => \$result_dir, 'log-dir=s' => \$log_dir,
    'build-timestamp=i' => \$build_timestamp, 'build-number=i' => \$build_number,
    'skip-install!' => \$skip_install,
) or die "bad options\n";
$arch ||= `dpkg --print-architecture 2>/dev/null`; chomp $arch; $arch ||= 'amd64';
die "FATAL: --codename required\n" unless $codename;
$chroot     ||= chroot_name($codename, $arch);
$result_dir ||= "$pkg_dir/../build-output/sbuild/$codename/$arch";
$build_timestamp = time() unless defined $build_timestamp;

# goconserver's pinned SHA + Go toolchain (see the shell below). goconserver 0.3.3 is UNRELEASED so it
# lives only on master -- pin an immutable SHA so every matrix cell builds the SAME source (reproducible,
# matching the EL GOCONSERVER_REF in mockbuild-all.pl). Its modules require Go >= 1.25, but the Ubuntu
# codenames ship older toolchains (focal=go1.13 ... noble=go1.22) and the pre-1.21 ones cannot even
# auto-switch toolchains; goconserver is a static CGO-free binary, so a pinned Go downloaded into the
# build works in ANY codename chroot and keeps the compiler reproducible. Bump these two deliberately.

# ---- package-specific build (absorbed from the former make_deb.sh); CWD = the copied package dir ----
# The maintained debian/ is at ./debian in the copied package dir; the upstream source is cloned fresh
# at the pinned SHA into ./gcsrc, the maintained debian/ copied in, and dpkg-buildpackage run there
# (its .deb(s) land in the copied package dir, which the collector picks up).
my $build = <<'BUILD';
set -e
VERSION=0.3.3
REPO=https://github.com/xcat2/goconserver.git
REF=6166fe5ec1c5b3c20475e322a9f0e8e93c87e45f
GO_PIN=1.25.12

# pinned modern Go toolchain (static CGO-free build, portable across codenames; reproducible compiler)
go_arch=$(dpkg --print-architecture); [ "$go_arch" = ppc64el ] && go_arch=ppc64le
echo "installing pinned go${GO_PIN} (${go_arch}) for the goconserver build"
rm -rf /usr/local/go
curl -fsSL "https://go.dev/dl/go${GO_PIN}.linux-${go_arch}.tar.gz" | tar -C /usr/local -xz
export PATH=/usr/local/go/bin:$PATH
export GOTOOLCHAIN=local     # use exactly the pinned toolchain; never auto-download another
go version

if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    SNAP_TS=$(date -d "@$SOURCE_DATE_EPOCH" --utc '+%Y%m%d%H%M')
else
    SNAP_TS=$(date '+%Y%m%d%H%M')
fi
FULL_VERSION="${VERSION}-snap${SNAP_TS}"

# shallow-fetch the pinned commit by object id (GitHub allows reachable-SHA fetches)
gc=gcsrc
git init -q "$gc"
git -C "$gc" remote add origin "$REPO"
git -C "$gc" fetch -q --depth 1 origin "$REF"
git -C "$gc" checkout -q FETCH_HEAD

# etcd storage backend has broken deps with modern Go modules
rm -rf "$gc/storage/etcd.go" "$gc/storage/etcd/"
cp -rL debian "$gc/debian"
cd "$gc"

export GOPATH="$PWD/.gopath" GOCACHE="$PWD/.gocache" GOMODCACHE="$PWD/.gomodcache" CGO_ENABLED=0
# Overlay the committed, PINNED go.mod/go.sum for this exact upstream SHA (generated with this same
# GO_PIN toolchain -- see ../gomod/README.md). go.mod replaces the abandoned github.com/kr/pty with
# creack/pty (pty.Start sets Ctty in a way Go >=1.15 rejects); go.sum integrity-checks every module.
# Build with -mod=mod: modules are downloaded from the proxy but PINNED + verified by go.sum, so the
# build is reproducible -- NO `go mod tidy` floating transitive versions from the network at build time.
# (The etcd backend removed above is why the pinned graph omits github.com/coreos/bbolt, which now
# declares its path as go.etcd.io/bbolt and breaks a fresh `go mod tidy`.)
if [ ! -f ../gomod/go.mod ] || [ ! -f ../gomod/go.sum ]; then
    echo "FATAL: pinned ../gomod/go.{mod,sum} missing -- regenerate per goconserver/gomod/README.md" >&2
    exit 1
fi
cp ../gomod/go.mod go.mod
cp ../gomod/go.sum go.sum
export GOFLAGS=-mod=mod

# stamp the maintained debian/ to the snapshot version, OUT-OF-TREE (this is the cloned copy)
sed -i "s/Version=${VERSION}/Version=${FULL_VERSION}/g" debian/rules
export DEBEMAIL="${DEBEMAIL:-xcat-build@xcat.org}" DEBFULLNAME="${DEBFULLNAME:-xCAT Build}"
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    deterministic_date=$(date -R -d "@$SOURCE_DATE_EPOCH" --utc)
    sed -i "1s/(.*)/(${FULL_VERSION})/" debian/changelog
    sed -i "s/^ -- .*/ -- $DEBFULLNAME <$DEBEMAIL>  $deterministic_date/" debian/changelog
else
    dch -v "$FULL_VERSION" -b -D unstable "Snap build for xCAT"
fi

dpkg-buildpackage -uc -us
BUILD

build_deb_in_chroot(
    pkg => $pkg, chroot => $chroot, pkg_dir => $pkg_dir, result_dir => $result_dir,
    build_timestamp => $build_timestamp, build => $build,
);
