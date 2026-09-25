#!/usr/bin/env perl
# ipxe-xcat/sbuild.pl -- per-package Ubuntu/Debian builder for ipxe-xcat, the apt analogue of
# ipxe-xcat/mockbuild.pl. Invoked by sbuild-all.pl per (codename,arch); also runnable standalone.
# The build runs on a copy of the package tree inside the <codename>-<arch>-sbuild chroot, and it
# checks the archives before dpkg-buildpackage and the built payload after it, so a deb that
# differs from the release never reaches --result-dir.
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
# --log-dir, --build-number and --skip-install keep the command line sbuild-all.pl passes to every
# builder; this package has no use for them.
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

# ipxe-xcat is Architecture:all and is built once on amd64 (see debs-manifest.conf).
my $build = <<'BUILD';
set -e
sha256sum --check --strict SHA256SUMS
dpkg-buildpackage -uc -us -b
version=$(dpkg-parsechangelog -S Version)
payload=$(mktemp -d)
dpkg-deb -x "../ipxe-xcat_${version}_all.deb" "$payload"
perl ./verify-payload.pl "$payload/tftpboot/xcat/ipxe" payload.sha256
source_archive="ipxe-${version%-*}-source.tar.gz"
grep -F "  $source_archive" SHA256SUMS \
    | (cd "$payload/usr/share/doc/ipxe-xcat" && sha256sum --check --strict -)
for licence in $(cd licenses && find . -type f); do
    cmp "licenses/$licence" "$payload/usr/share/doc/ipxe-xcat/licenses/$licence"
done
rm -rf "$payload"
BUILD

build_deb_in_chroot(
    pkg => $pkg, chroot => $chroot, pkg_dir => $pkg_dir, result_dir => $result_dir,
    build_timestamp => $build_timestamp, build => $build,
);
