#!/usr/bin/env perl
# xnba/sbuild.pl -- per-package Ubuntu/Debian builder for xnba-undi; the apt/sbuild analogue of
# xnba/mockbuild.pl. Builds the package inside the matching <codename>-<arch>-sbuild chroot from its
# MAINTAINED debian/ packaging and collects the .deb(s) into --result-dir. Invoked by sbuild-all.pl
# per (codename,arch); also runnable standalone. Out-of-tree: the build runs on a COPY of the package
# tree (the checkout is never mutated). The common chroot orchestration lives in
# BuildUtils::build_deb_in_chroot; only xnba's build is below.
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
# xnba-undi is Architecture:all (x86 iPXE/gPXE network boot) built in place with a custom rules file.
# Built once on amd64 (see debs-manifest.conf).
my $build = <<'BUILD';
set -e
dpkg-buildpackage -uc -us -R./build/rules.fromBIN
BUILD

build_deb_in_chroot(
    pkg => $pkg, chroot => $chroot, pkg_dir => $pkg_dir, result_dir => $result_dir,
    build_timestamp => $build_timestamp, build => $build,
);
