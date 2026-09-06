#!/usr/bin/env perl
# ipmitool/sbuild.pl -- per-package Ubuntu/Debian builder for ipmitool-xcat; the apt/sbuild analogue
# of ipmitool/mockbuild.pl. Builds the package inside the matching <codename>-<arch>-sbuild chroot from
# its MAINTAINED debian/ packaging and collects the .deb(s) into --result-dir. Invoked by sbuild-all.pl
# per (codename,arch); also runnable standalone. Out-of-tree: the build runs on a COPY of the package
# tree (the checkout is never mutated). The common chroot orchestration lives in
# BuildUtils::build_deb_in_chroot; only ipmitool's source prep + dpkg-buildpackage is below.
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
# --log-dir / --build-number are accepted for CLI-compat with sbuild-all.pl (which passes them
# uniformly to every per-package builder) but are intentionally UNUSED here: sbuild-all does its own
# per-package logging. --skip-install drops the post-build smoke.
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

# ---- package-specific build (absorbed from the former make_deb.sh); CWD = the copied package dir ----
# ipmitool is a compiled C package, so it is built per-codename against
# that release's libc/toolchain. Extract the upstream tarball, drop in the maintained debian/, build.
my $version = '1.8.18';
my $build = <<"BUILD";
set -e
VERSION=$version
tar xvfz ipmitool-\$VERSION.tar.gz
cd ipmitool-\$VERSION
cp -rL ../debian .
HOST_ARCH=\$(dpkg --print-architecture)
TARGET_ARCH=\$HOST_ARCH dpkg-buildpackage -uc -us
BUILD

# The chroot is the only place a cross-built binary can run: it holds the target's loader and
# libraries. Without this an unrunnable ipmitool-xcat ships as a green build.
my $smoke = {
    deb    => qr/^ipmitool-xcat_/,
    run    => '/opt/xcat/bin/ipmitool-xcat -V',
    expect => qr/ipmitool-xcat version \Q$version\E/i,
};

build_deb_in_chroot(
    pkg => $pkg, chroot => $chroot, pkg_dir => $pkg_dir, result_dir => $result_dir,
    build_timestamp => $build_timestamp, build => $build,
    ($skip_install ? () : (smoke => $smoke)),
);
