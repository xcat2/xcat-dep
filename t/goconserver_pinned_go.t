#!/usr/bin/env perl
# The sles12 dep cell cannot build goconserver:
#
#   No matching package to install: 'golang'
#   Error: Some packages could not be found.
#
# goconserver's spec takes Go from "BuildRequires: golang". Leap 42.3, which builds the sles12
# cell, has no package of that name and nothing that provides it: it names the compiler 'go', and
# its newest is go1.11 against a go.mod directive that asks for 1.25, which GOTOOLCHAIN=local will
# not step above. So renaming the dependency cannot work either -- the target has to bring the
# pinned toolchain archive, the way openEuler already does.
#
# The decision is pure, so this runs no mock and downloads nothing.
use strict;
use warnings;

use FindBin qw($RealBin);
use Test::More;

use lib $RealBin, "$RealBin/..", "$RealBin/../lib";
use MockBuildUtils ();

my $needs = MockBuildUtils->can('goconserver_needs_pinned_go');
ok($needs, 'MockBuildUtils decides where goconserver gets its Go')
  or do { done_testing(); exit 0 };

# A target is in this table because of what its repositories carry, so each entry says which.
my %pinned = (
    # Leap 42.3 (the sles12 cell): newest Go is go1.11, under the name 'go'.
    'opensuse-leap-42.3-x86_64'  => 1,
    # openEuler packages no Go under any name.
    'openeuler-24.03sp4-x86_64'  => 1,
    'openeuler-22.03sp4-x86_64'  => 1,
    'openeuler-24.03-ppc64le'    => 1,
    # Leap 15.6 (the sles15 cell) resolves 'golang' to go1.25.
    'opensuse-leap-15.6-x86_64'  => 0,
    'opensuse-leap-15.6-ppc64le' => 0,
    # EL carries golang at or above the directive.
    'alma+epel-10-x86_64'        => 0,
    'alma+epel-9-x86_64'         => 0,
    'alma+epel-8-ppc64le'        => 0,
);

for my $target (sort keys %pinned) {
    my $got = $needs->($target) ? 1 : 0;
    is($got, $pinned{$target},
        $pinned{$target}
          ? "$target brings the pinned Go toolchain"
          : "$target takes Go from the chroot");
}

# An empty or undefined target must not silently select the pinned toolchain: the archive is
# fetched over the network, and a run that does that for every target pays for it on every build.
is($needs->(undef) ? 1 : 0, 0, 'an undefined target does not ask for the toolchain archive');
is($needs->('')    ? 1 : 0, 0, 'an empty target does not ask for the toolchain archive');

done_testing();
