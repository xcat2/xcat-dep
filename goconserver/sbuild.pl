#!/usr/bin/env perl
# <dep>/sbuild.pl -- per-package Ubuntu/Debian builder; the apt/sbuild analogue of <dep>/mockbuild.pl.
#
# It drives THIS package's MAINTAINED debian/ packaging (via the package's make_deb.sh, which copies
# debian/ into an extracted/cloned source tree and runs dpkg-buildpackage) INSIDE the matching
# <codename>-<arch>-sbuild chroot, then collects the produced .deb(s) into --result-dir. Invoked by
# sbuild-all.pl once per (codename,arch); also runnable standalone.
#
# This file is intentionally GENERIC and identical across every dep dir -- the package identity is
# derived from its own directory, and the per-package build specifics live in that package's
# maintained make_deb.sh + debian/ (so the maintained packaging is reused, never re-implemented:
# review concern #2). A package that ever needs bespoke handling can diverge its own copy.
#
# Out-of-tree guarantee: the checkout is never mutated -- the package tree is copied to a temp work
# dir in the chroot session and make_deb.sh stamps the COPY's debian/changelog from SOURCE_DATE_EPOCH.
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(basename);
use File::Path qw(make_path);
use Getopt::Long qw(GetOptions);
use FindBin qw($RealBin);
use lib "$RealBin/..";
use BuildUtils qw(sh_quote chroot_name);

my $pkg_dir = abs_path($RealBin);
my $pkg     = basename($pkg_dir);

my ($codename, $arch, $chroot, $result_dir, $log_dir) = ('', '', '', '', '');
my ($build_timestamp, $build_number, $skip_install) = (undef, undef, 0);
GetOptions(
    'codename=s'        => \$codename,
    'arch=s'            => \$arch,
    'chroot=s'          => \$chroot,
    'result-dir=s'      => \$result_dir,
    'log-dir=s'         => \$log_dir,
    'build-timestamp=i' => \$build_timestamp,
    'build-number=i'    => \$build_number,
    'skip-install!'     => \$skip_install,
) or die "bad options\n";

$arch ||= `dpkg --print-architecture 2>/dev/null`; chomp $arch;
$arch ||= 'amd64';
die "FATAL: --codename required\n" unless $codename;
$chroot     ||= chroot_name($codename, $arch);
$result_dir ||= "$pkg_dir/../build-output/sbuild/$codename";
$log_dir    ||= $result_dir;
make_path($result_dir, $log_dir);
$build_timestamp = time() unless defined $build_timestamp;

die "FATAL: $pkg has no make_deb.sh (maintained deb packaging expected)\n" unless -f "$pkg_dir/make_deb.sh";
die "FATAL: chroot $chroot missing (run sbuild-all.pl to auto-init it)\n"
    if system("schroot -l 2>/dev/null | grep -qx chroot:$chroot") != 0;

# The whole per-package build runs in ONE schroot session (ephemeral overlay). schroot SANITIZES the
# environment, so the package dir / out dir / epoch are passed as POSITIONAL ARGS to the inner bash.
# The 'INNER' heredoc is single-quoted so inner shell vars do not expand out here.
my $inner = <<'INNER';
set -uo pipefail
PKGSRC="$1"; OUT="$2"; SDE="$3"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=nocheck
export SOURCE_DATE_EPOCH="$SDE"
for t in 1 2 3; do apt-get update -q && break; sleep 5; done
# common tooling the make_deb.sh scripts use beyond debian/control Build-Depends (goconserver
# git-clones + go-builds; others extract an upstream tarball).
apt-get install -y --no-install-recommends git wget curl ca-certificates golang-go devscripts quilt fakeroot >/dev/null 2>&1 || true
W=$(mktemp -d); cp -a "$PKGSRC" "$W/pkg"; cd "$W/pkg"
if [ -f debian/control ]; then
  BD=$(sed -n '/^Build-Depends:/,/^\S/p' debian/control | tr ',' '\n' \
       | sed -E 's/^Build-Depends://; s/\(.*\)//; s/\[.*\]//; s/[[:space:]]//g' \
       | grep -E '^[a-z0-9]' | grep -v '^debhelper-compat' | sort -u | tr '\n' ' ')
  [ -n "$BD" ] && { apt-get install -y $BD >/dev/null 2>&1 || echo "[warn] some build-deps failed to install"; }
fi
chmod +x make_deb.sh
./make_deb.sh || { echo "make_deb.sh FAILED"; exit 1; }
# make_deb.sh drops the .deb(s) beside the package dir; collect from the work tree.
found=$(find "$W" -maxdepth 2 -name '*.deb' ! -name '*-dbgsym_*' -print)
[ -n "$found" ] || { echo "build produced no .deb"; exit 1; }
mkdir -p "$OUT"; echo "$found" | while read -r d; do cp -v "$d" "$OUT/"; done
INNER

my $cmd = 'schroot -c ' . sh_quote($chroot) . ' -u root -d / -- '
        . 'bash -c ' . sh_quote($inner) . ' bash '
        . sh_quote($pkg_dir) . ' ' . sh_quote($result_dir) . ' ' . sh_quote($build_timestamp);
print "[$pkg] building in chroot $chroot -> $result_dir (SOURCE_DATE_EPOCH=$build_timestamp)\n";
print "+ $cmd\n";
my $rc = system('bash', '-c', $cmd);
my $ec = $rc == -1 ? -1 : ($rc >> 8);
die "[$pkg] build failed (rc=$ec)\n" if $ec != 0;
# The debs were copied to --result-dir from INSIDE the chroot session, which only reaches the host if
# --result-dir is on a path bind-mounted into the chroot (the shared /opt/xcat-ci-shared tree). Verify
# host-side that they actually landed, so a mis-configured (chroot-local, e.g. /tmp) result-dir fails
# LOUD instead of silently producing nothing.
my @debs = glob("$result_dir/*.deb");
die "[$pkg] build succeeded in the chroot but no .deb is visible at $result_dir on the host\n"
  . "  (is --result-dir on a path bind-mounted into the chroot, e.g. under /opt/xcat-ci-shared?)\n"
  unless @debs;
print "[$pkg] OK (" . scalar(@debs) . " deb(s) in $result_dir)\n";
