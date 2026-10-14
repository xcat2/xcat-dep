#!/usr/bin/env perl
# mock 6.8 reloads its uid manager from chrootuid, so it opens state.log, build.log and root.log in
# --resultdir as that uid. mockbuild-perl-packages.pl runs as root and creates the result
# directories itself, so each one must be writable by the uid mock builds as.
use strict;
use warnings;

use FindBin qw($RealBin);
use File::Basename qw(basename);
use File::Temp qw(tempdir);
use Test::More;

use lib $RealBin, "$RealBin/..", "$RealBin/lib";
use MockBuildUtils qw(mock_result_dirs);
use XCAT::MockResultTest qw(writable_as);

# Flush before the first fork below, or the child repeats this file's TAP output on exit.
$| = 1;

my $tmp = tempdir(CLEANUP => 1);
my $cfg = "$tmp/mock-deterministic.cfg";

# mock_chroot_uid runs mock's loader. native/mock-chroot-uid.t tests it against mock.
my @asked;
my $build_uid = $>;
no warnings 'redefine';
local *MockBuildUtils::mock_chroot_uid = sub { push @asked, $_[0]; return $build_uid };
use warnings 'redefine';

my @own = mock_result_dirs("$tmp/perl-IO-Stty", $cfg);
is_deeply(\@asked, [$cfg], 'the uid comes from the configuration mock builds with');
is_deeply([map { basename($_) } @own], [qw(srpm restamp-srpm rpm)],
    'a package build gets the three directories it gives mock as --resultdir');
ok(-d $_, basename($_) . ' is created') for @own;

SKIP: {
    skip 'a directory owned by another uid needs root', 7 if $> != 0;
    # tempdir gives 0700. A run reaches a result directory through /tmp and the work directory,
    # which the builder creates with the umask root starts with, so make the scratch tree match.
    chmod 0755, $tmp or die "Cannot make $tmp traversable: $!\n";
    $build_uid = 1000;
    my @dirs = mock_result_dirs("$tmp/perl-Net-DNS", $cfg);
    is(scalar @dirs, 3, 'uid 1000 gets the same three directories');
    for my $dir (@dirs) {
        my $name = basename($dir);
        is((stat $dir)[4], 1000, "$name is owned by the uid mock builds as");
        ok(writable_as(1000, $dir), "$name takes a state.log written by that uid");
    }
}

# A first build under umask 077: mock_result_dirs creates the work and package directories too.
my $fresh = tempdir(CLEANUP => 1);
my $fresh_mode = (stat $fresh)[2] & 07777;
my $umask = umask 077;
my @fresh = mock_result_dirs("$fresh/work/perl-Net-DNS", $cfg);
umask $umask;
is((stat $_)[2] & 07777, 0755, "the new parent $_ is traversable")
    for "$fresh/work", "$fresh/work/perl-Net-DNS";
is((stat $fresh)[2] & 07777, $fresh_mode, 'the existing directory keeps its mode');

SKIP: {
    skip 'a directory owned by another uid needs root', 3 if $> != 0;
    # /tmp, where the work directory goes, is traversable. Only the new directories are under test.
    my $tree = tempdir(CLEANUP => 1);
    chmod 0755, $tree or die "Cannot make $tree traversable: $!\n";
    $build_uid = 1000;
    my $umask = umask 077;
    my @dirs = mock_result_dirs("$tree/work/perl-Net-DNS", $cfg);
    umask $umask;
    ok(writable_as(1000, $_), basename($_) . ' in a fresh tree takes a state.log from uid 1000') for @dirs;
}

done_testing();
