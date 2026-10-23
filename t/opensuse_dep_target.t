#!/usr/bin/env perl
# mockbuild-all.pl cannot build the openSUSE dep cell at all:
#
#   Could not parse EL release from target 'opensuse-leap-15.6-x86_64'
#
# target_profile tries openEuler, then the forcearch table, then falls through to /epel-(\d+)-/ and
# dies. a1ab393 removed target_osdir, which had mapped opensuse-leap-15.6-* to sles15, while the
# pipeline still runs mockbuild-all.pl --target opensuse-leap-15.6-x86_64. So
# xcat-dep-build-opensuse15-x86_64 has never completed a real build on this lineage.
#
# target_profile is pure, so this runs no mock and installs no /etc/mock configuration.
use strict;
use warnings;

use FindBin qw($RealBin);
use Test::More;

use lib $RealBin, "$RealBin/..", "$RealBin/../lib";
use MockBuildUtils ();

my $profile = MockBuildUtils->can('target_profile');
my $baseurl = MockBuildUtils->can('dep_repo_baseurl');
my $label   = MockBuildUtils->can('dep_repo_label');
ok($profile, 'MockBuildUtils decides what a target builds and which cell it publishes');
ok($baseurl, 'MockBuildUtils decides which channel a cell advertises');
ok($label,   'MockBuildUtils names a cell');

# The cell is sles<MAJOR>/<arch>: every 15.x publishes under sles15, which is the directory
# xcat.org serves and the one a SUSE conf's DEP_REPO points at.
my %cell = (
    'opensuse-leap-15.6-x86_64'  => 'sles15/x86_64',
    'opensuse-leap-15.6-ppc64le' => 'sles15/ppc64le',
);

subtest 'an openSUSE target yields a profile' => sub {
    plan skip_all => 'MockBuildUtils has no target_profile' unless $profile;
    for my $t (sort keys %cell) {
        my ($arch) = $t =~ /-([^-]+)\z/;
        my $p = eval { $profile->($t, $arch) };
        ok($p, "$t yields a profile") or do { diag($@); next };
        is($p->{cell}, $cell{$t}, "$t publishes into $cell{$t}");
        is($p->{arch}, $arch,     "$t builds for $arch");
        is($p->{epel}, 0,         "$t does not look for EPEL, which Leap has none of");
        is($p->{forcearch}, 0,    "$t builds natively, not through qemu-user-static");
        ok(scalar @{ $p->{dep_builders} }, "$t has something to build");
        ok(!(grep { $_ eq 'elilo-xcat' } @{ $p->{dep_builders} }),
            "$t does not build elilo-xcat, which packages an EL boot loader");
        ok(scalar @{ $p->{required} }, "$t asserts a required set");
    }
};

subtest 'the EL, openEuler and forcearch answers do not move' => sub {
    plan skip_all => 'MockBuildUtils has no target_profile' unless $profile;
    my $el = $profile->('alma+epel-10-x86_64', 'x86_64');
    is($el->{cell}, 'rh10/x86_64', 'an EL target still publishes into rh<N>/<arch>');
    is($el->{rel}, '10', '... and still parses its release');
    is($el->{epel}, 1, '... and still looks for EPEL');

    my $oe = $profile->('openeuler-24.03sp4-x86_64', 'x86_64');
    is($oe->{cell}, 'openeuler24.03sp4/x86_64', 'an openEuler target keeps its own layout');

    my $fa = $profile->('rocky-10-riscv64-xcat', 'x86_64');
    is($fa->{cell}, 'rh10/riscv64', 'a forcearch target publishes into the arch it cross-builds');
    is($fa->{forcearch}, 1, '... and is marked forcearch');
};

subtest 'a target that belongs to no family is refused' => sub {
    plan skip_all => 'MockBuildUtils has no target_profile' unless $profile;
    for my $bad ('opensuse-tumbleweed-x86_64', 'opensuse-leap-15-x86_64', 'debian-12-amd64') {
        my $p = eval { $profile->($bad, 'x86_64') };
        ok(!$p, "$bad is refused");
        like($@, qr/Could not parse EL release/, "... and says which parse failed for $bad");
    }
};

# xcat.org serves Leap from the sles channel. A cell that advertised the yum channel would hand
# every client a baseurl that does not hold it.
subtest 'a cell advertises its own channel' => sub {
    plan skip_all => 'MockBuildUtils has no dep_repo_baseurl' unless $baseurl && $label;
    is($baseurl->('sles15/x86_64'),
       'https://xcat.org/files/xcat/repos/sles/devel/xcat-dep/sles15/x86_64',
       'a Leap cell advertises the sles channel');
    is($baseurl->('rh10/x86_64'),
       'https://xcat.org/files/xcat/repos/yum/devel/xcat-dep/rh10/x86_64',
       'an EL cell advertises the yum channel');
    is($baseurl->('openeuler24.03sp4/x86_64'),
       'https://xcat.org/files/xcat/repos/yum/devel/xcat-dep/openeuler24.03sp4/x86_64',
       'an openEuler cell advertises the yum channel');
    is($label->('sles15/x86_64'), 'sles15 x86_64', 'a Leap cell names itself sles15, not rh15');
    is($label->('rh10/x86_64'), 'rh10 x86_64', 'an EL cell is unchanged');
};

# Every cell the build publishes must have a manifest section, or the completeness gate exits
# FATAL before the repository is indexed.
subtest 'every openSUSE cell has a manifest section' => sub {
    my %m = MockBuildUtils::read_manifest("$RealBin/../packages-manifest.conf");
    for my $t (sort keys %cell) {
        ok(exists $m{$t}, "packages-manifest.conf has a section for $t");
    }
};

done_testing();
