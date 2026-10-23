#!/usr/bin/env perl
# The build plan of every target, held down package by package.
#
# target_profile moved out of mockbuild-all.pl and into MockBuildUtils, and the move carried the
# dep_builders lists with it. A list that travels can lose an entry in silence, and a lost entry is
# not a build error: mockbuild-all.pl builds what dep_builders names and then asserts what
# packages-manifest.conf pins, so the build skips the package and the completeness gate fails
# afterwards, naming the manifest rather than the plan. openEuler lost uftp exactly that way.
#
# The values below are the ones mockbuild-all.pl held before the move. target_profile is pure, so
# this runs no mock.
use strict;
use warnings;

use FindBin qw($RealBin);
use Test::More;

use lib $RealBin, "$RealBin/..", "$RealBin/../lib";
use MockBuildUtils ();

my $profile = MockBuildUtils->can('target_profile');
ok($profile, 'MockBuildUtils decides what a target builds');

# Every dep xCAT requires, on every architecture.
my @REQUIRED = qw(ipmitool-xcat syslinux-xcat grub2-xcat xnba-undi ipxe-xcat
                  perl-IO-Stty perl-HTTP-Async perl-Net-HTTPS-NB);
my @EL = qw(elilo-xcat grub2-xcat ipmitool-xcat syslinux-xcat goconserver conserver-xcat
            xnba-undi ipxe-xcat uftp);

my %PLAN = (
    # EL, native and cross-built, builds the whole set.
    'alma+epel-8-x86_64'       => [@EL],
    'alma+epel-9-ppc64le'      => [@EL],
    'alma+epel-10-x86_64'      => [@EL],
    'rocky-10-riscv64-xcat'    => [@EL],
    # openEuler packages its own boot loader, so elilo-xcat is out, and it adds python3-scp.
    # uftp stays: neither openEuler nor SLES ships UFTP 5, and every openEuler manifest pins it.
    'openeuler-22.03sp4-x86_64' => [qw(grub2-xcat ipmitool-xcat syslinux-xcat goconserver
                                       conserver-xcat xnba-undi ipxe-xcat uftp python3-scp)],
    'openeuler-24.03-ppc64le'   => [qw(grub2-xcat ipmitool-xcat syslinux-xcat goconserver
                                       conserver-xcat xnba-undi ipxe-xcat uftp python3-scp)],
    # openSUSE: the EL set without elilo-xcat, which packages an EL boot loader, and without
    # uftp, which needs a uftp.spec change this tree does not carry.
    'opensuse-leap-15.6-x86_64' => [qw(grub2-xcat ipmitool-xcat syslinux-xcat goconserver
                                       conserver-xcat xnba-undi ipxe-xcat)],
    'opensuse-leap-42.3-x86_64' => [qw(grub2-xcat ipmitool-xcat syslinux-xcat goconserver
                                       conserver-xcat xnba-undi ipxe-xcat)],
);

subtest 'every target builds the packages its manifest pins' => sub {
    plan skip_all => 'MockBuildUtils has no target_profile' unless $profile;
    for my $t (sort keys %PLAN) {
        my ($arch) = $t eq 'rocky-10-riscv64-xcat' ? ('x86_64') : $t =~ /-([^-]+)\z/;
        my $p = eval { $profile->($t, $arch) };
        ok($p, "$t yields a profile") or do { diag($@); next };
        is_deeply([sort @{ $p->{dep_builders} }], [sort @{ $PLAN{$t} }],
            "$t builds exactly its own dep set")
            or diag("got: @{[ sort @{ $p->{dep_builders} } ]}");
        is_deeply([sort @{ $p->{required} }], [sort @REQUIRED],
            "$t requires the packages xCAT needs on every architecture");
    }
};

# The manifest is the other half: a package a target builds and does not pin is published and
# never verified, and a package it pins and does not build fails the completeness gate.
subtest 'the plan and the manifest agree on uftp' => sub {
    plan skip_all => 'MockBuildUtils has no target_profile' unless $profile;
    my %m = MockBuildUtils::read_manifest("$RealBin/../packages-manifest.conf");
    for my $t (sort keys %PLAN) {
        next unless exists $m{$t};
        my $builds = grep { $_ eq 'uftp' } @{ $PLAN{$t} };
        is(exists $m{$t}{uftp} ? 1 : 0, $builds ? 1 : 0,
            "$t pins uftp exactly when it builds it");
    }
};

done_testing();
