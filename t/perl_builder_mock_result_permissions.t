#!/usr/bin/env perl
# mock 6.8 reloads its uid manager from chrootuid, so it opens state.log, build.log and root.log in
# --resultdir as that uid. mockbuild-perl-packages.pl runs as root and creates the result
# directories itself, so each one must be writable by the uid mock builds as.
use strict;
use warnings;

use FindBin qw($RealBin);
use File::Basename qw(basename);
use File::Temp qw(tempdir);
use POSIX ();
use Test::More;

use lib $RealBin, "$RealBin/..";
use MockBuildUtils qw(mock_result_dirs);

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

done_testing();

# writable_as($uid, $dir): true when a process running as $uid can create a log in $dir. The child
# exits 2 rather than reporting a write it made as root, so a failed setuid cannot read as a pass.
sub writable_as {
    my ($uid, $dir) = @_;
    my $probe = "$dir/state.log";
    unlink $probe;
    my $pid = fork() // die "fork: $!\n";
    if (!$pid) {
        $) = "$uid $uid";
        $( = $uid;
        POSIX::setuid($uid);
        POSIX::_exit(2) if $> != $uid || $< != $uid;
        my $fh;
        my $ok = open($fh, '>', $probe) ? 1 : 0;
        close $fh if $ok;
        POSIX::_exit($ok ? 0 : 1);
    }
    waitpid $pid, 0;
    my $status = $?;
    unlink $probe;
    return $status == 0;
}
