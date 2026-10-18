#!/usr/bin/env perl
# uftp/sbuild.pl -- per-package Ubuntu/Debian builder for uftp; the apt/sbuild analogue of
# uftp/mockbuild.pl. Builds the package inside the matching <codename>-<arch>-sbuild chroot from the
# committed release archive and the maintained debian/ packaging, and collects the .deb into
# --result-dir. Invoked by sbuild-all.pl per (codename,arch); also runnable standalone. The common
# chroot orchestration lives in BuildUtils::build_deb_in_chroot.
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
# --log-dir and --build-number keep the CLI of the other builders, which sbuild-all.pl passes to
# every builder. --skip-install drops the post-build smoke.
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

# The archive is checked before it is used, and debian/patches applies the fixes that the RPM
# carries too. The source format 3.0 (quilt) needs the archive under its orig name.
my $version = '5.0.4';
my $build = <<"BUILD";
set -e
VERSION=$version
sha256sum --check --strict SHA256SUMS
tar xzf uftp-\$VERSION.tar.gz
cp uftp-\$VERSION.tar.gz uftp_\$VERSION.orig.tar.gz
cd uftp-\$VERSION
cp -rL ../debian .
dpkg-buildpackage -uc -us
BUILD

# The chroot holds the target's loader and libraries, so it can run a cross-built binary. Key
# generation runs the OpenSSL code of the key exchange, and the receiver must be the UFTP 5 build
# with the xCAT fixes.
my $smoke = {
    deb    => qr/^uftp_/,
    run    => 'uftp_keymgt -g ec:secp256r1 /tmp/uftp-smoke.key && uftp_keymgt /tmp/uftp-smoke.key'
            . ' && grep -a -o "UFTP version [0-9.]* (xCAT build [0-9]*)" /usr/bin/uftpd | head -n 1',
    expect => qr/ECDSA, curve.*UFTP version \Q$version\E \(xCAT build \d+\)/s,
};

build_deb_in_chroot(
    pkg => $pkg, chroot => $chroot, pkg_dir => $pkg_dir, result_dir => $result_dir,
    build_timestamp => $build_timestamp, build => $build,
    ($skip_install ? () : (smoke => $smoke)),
);
