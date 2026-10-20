#!/usr/bin/env perl
# An EPEL target names the architecture of the rpms it produces, and that architecture decides
# the repository cell the build deploys to. A build host whose own architecture differs
# cross-builds the target through mock's --forcearch and qemu-user; the rpms are still the
# target's architecture.
#
# alma+epel-10-aarch64 built on an x86_64 host reported arch=x86_64, so target_cell resolved to
# rh10/x86_64 and the aarch64 build would have replaced the x86_64 cell of the published
# repository with aarch64 rpms. It also reported forcearch=0, which left the emulated build with
# the native step timeout.
use strict;
use warnings;

use FindBin qw($RealBin);
use Test::More;

use lib $RealBin, "$RealBin/..";
use MockBuildUtils qw(epel_target_profile epel_cell_path cell_lock_path);

# A cross-built target: the rpms and the cell are the target's architecture, not the host's.
{
    my $p = epel_target_profile('alma+epel-10-aarch64', 'x86_64');
    ok($p, 'alma+epel-10-aarch64 is an EPEL target') or done_testing, exit;
    is($p->{rel},   '10',      'EL release 10');
    is($p->{arch},  'aarch64', 'the rpm architecture is the target architecture, not the host one');
    is($p->{forcearch}, 1,     'an x86_64 host cross-builds it');
}

# The same target on its own architecture is a native build.
{
    my $p = epel_target_profile('alma+epel-10-aarch64', 'aarch64');
    is($p->{arch},      'aarch64', 'a native aarch64 build still produces aarch64 rpms');
    is($p->{forcearch}, 0,         'and does not cross-build');
}

# Every target that builds today keeps the answer it has today: same arch, no cross-build.
for my $case (['alma+epel-10-x86_64',  'x86_64',  '10'],
              ['alma+epel-9-x86_64',   'x86_64',  '9'],
              ['alma+epel-8-x86_64',   'x86_64',  '8'],
              ['alma+epel-10-ppc64le', 'ppc64le', '10'],
              ['alma+epel-9-ppc64le',  'ppc64le', '9'],
              ['alma+epel-8-ppc64le',  'ppc64le', '8'])
{
    my ($target, $host, $rel) = @$case;
    my $p = epel_target_profile($target, $host);
    is($p->{rel},       $rel,  "$target on $host: EL release $rel");
    is($p->{arch},      $host, "$target on $host: builds natively for $host");
    is($p->{forcearch}, 0,     "$target on $host: no cross-build");
}

# The two EL10 targets deploy to different cells, so they take different cell locks. With the
# architecture taken from the host, both resolved to rh10/x86_64 and to one lock: the aarch64 build
# on xcat-master held .x86_64.lock, and the x86_64 build of the same run waited out its 100 retries
# and exited before it built anything (xcat-dep-build-el10-x86_64 builds 92 and 93).
{
    my $repo = '/repo/yum/xcat-dep';
    my %cell = map { $_ => epel_cell_path($repo, epel_target_profile("alma+epel-10-$_", 'x86_64')) }
      qw(x86_64 aarch64);
    is($cell{aarch64}, "$repo/rh10/aarch64", 'the aarch64 target deploys to the aarch64 cell');
    is($cell{x86_64},  "$repo/rh10/x86_64",  'the x86_64 target deploys to the x86_64 cell');
    isnt(cell_lock_path($cell{aarch64}), cell_lock_path($cell{x86_64}),
        'the two EL10 targets of one host take different cell locks');
    is(cell_lock_path($cell{aarch64}), "$repo/rh10/.aarch64.lock",
        'a cell lock sits beside its cell');
}

# A name that is not an EPEL target is refused, so the caller can keep its own error. The
# forcearch and openEuler targets are resolved before this sub is reached.
for my $not (qw(rocky-10-riscv64-xcat openeuler-24.03sp4-x86_64 noble)) {
    is(epel_target_profile($not, 'x86_64'), undef, "'$not' is not an EPEL target");
}

done_testing;
