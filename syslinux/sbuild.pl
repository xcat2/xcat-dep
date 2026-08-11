#!/usr/bin/env perl
# syslinux/sbuild.pl -- per-package Ubuntu/Debian builder for syslinux-xcat; the apt/sbuild analogue
# of syslinux/mockbuild.pl. Builds the package inside the matching <codename>-<arch>-sbuild chroot from
# its MAINTAINED debian/ packaging and collects the .deb(s) into --result-dir. Invoked by sbuild-all.pl
# per (codename,arch); also runnable standalone. Out-of-tree: the build runs on a COPY of the package
# tree (the checkout is never mutated). The common chroot orchestration lives in
# BuildUtils::build_deb_in_chroot; only syslinux's source prep + patches + dpkg-buildpackage is below.
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
# syslinux 3.86 is old and needs source patches to build with modern gcc/glibc (it produces the x86
# boot components, so it is only built on amd64 -- see debs-manifest.conf).
my $build = <<'BUILD';
set -e
tar xvfj syslinux-3.86.tar.bz2
cd syslinux-3.86
cp -rL ../debian .
# GCC >= 10 defaults to -fno-common; syslinux 3.86 relies on common symbols. GCC 15 promotes several
# warnings to errors.
sed -i '/^GCCWARN := -W -Wall/s/$/ -fcommon -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion/' MCONFIG
sed -i "s|^GCCWARN := .*|& -fdebug-prefix-map=$(pwd)=.|" MCONFIG
# glibc >= 2.28 moved major()/minor() to sys/sysmacros.h; extlinux/main.c:843 calls them unconditionally.
sed -i '/#include <sys\/types.h>/a #include <sys/sysmacros.h>' extlinux/main.c
# com32/cmenu/Makefile uses python2 menugen.py for test .menu files -- not needed for the build.
rm -f com32/cmenu/*.menu
# vpd.c:67 passes &vpd->base_address (char(*)[6]) not char*; %X wrong for a char* arg.
sed -i 's/snprintf(&vpd->base_address, 5, "%X", q)/snprintf(vpd->base_address, sizeof(vpd->base_address), "%s", q)/' com32/gpllib/vpd/vpd.c
export NO_WERROR=1
dpkg-buildpackage -uc -us
BUILD

build_deb_in_chroot(
    pkg => $pkg, chroot => $chroot, pkg_dir => $pkg_dir, result_dir => $result_dir,
    build_timestamp => $build_timestamp, build => $build,
    extra_tools => [qw(nasm)],
);
