#!/usr/bin/env perl
# The sles12 cell cannot install xCAT. zypper reaches package 120 of 138 and then:
#
#   (120/138) Installing: xnba-undi-1.21.1-1.el10.noarch [...error]
#   error: unpacking of archive failed: cpio: Bad magic
#   error: xnba-undi-1.21.1-1.el10.noarch: install failed
#
# xnba/mockbuild.pl runs rpmbuild on the BUILD HOST rather than in the target chroot, because the
# package only repackages two pre-built iPXE binaries. The host is EL10, whose rpm defaults to a
# zstd payload. The sles12 management node is openSUSE 42.3 and its rpm is 4.11, which predates
# zstd and reports the payload as a bad cpio archive.
#
# Measured in the published sles12 dep repository: 13 of the 14 rpms are built by rpm 4.11.2 with
# an lzma payload, and xnba-undi alone is built by rpm 4.19.1.1 with zstd. As a positive control,
# five xz-payload core rpms installed on that same node at steps 106 to 110 of the same
# transaction, so xz is readable there and the payload format is the whole difference.
#
# The decision is pure, so this builds nothing and runs no rpmbuild.
use strict;
use warnings;

use FindBin qw($RealBin);
use Test::More;

use lib $RealBin, "$RealBin/..", "$RealBin/../lib";
use MockBuildUtils ();

my $payload = MockBuildUtils->can('host_build_payload_compressor');
ok($payload, 'MockBuildUtils decides the payload a host-built rpm must use')
  or do { done_testing(); exit 0 };

# rpm gained zstd in 4.14. Leap 42.3 ships 4.11 and cannot read it; Leap 15.6 ships 4.14.3 and
# can. Every EL and openEuler target this project builds for is 4.14 or newer.
my %want = (
    'opensuse-leap-42.3-x86_64'  => 'w9.xzdio',
    'opensuse-leap-15.6-x86_64'  => undef,
    'opensuse-leap-15.6-ppc64le' => undef,
    'alma+epel-8-x86_64'         => undef,
    'alma+epel-9-x86_64'         => undef,
    'alma+epel-10-x86_64'        => undef,
    'openeuler-24.03sp4-x86_64'  => undef,
);

for my $target (sort keys %want) {
    my $got = $payload->($target);
    if (defined $want{$target}) {
        is($got, $want{$target},
            "$target gets a payload its rpm can read, because rpm 4.11 cannot read zstd");
    } else {
        is($got, undef, "$target keeps the host default, its rpm reads zstd");
    }
}

# An unknown or empty target must not silently change the payload for every build.
is($payload->(undef), undef, 'an undefined target keeps the host default');
is($payload->(''),    undef, 'an empty target keeps the host default');

done_testing();
