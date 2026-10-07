#!/usr/bin/env perl
# mock 6.8 reloads its uid manager from chrootuid, so it opens state.log, build.log and root.log in
# --resultdir as that uid. mockbuild-perl-packages.pl runs as root and creates the result
# directories itself, so each one must be writable by the uid the mock configuration names.
use strict;
use warnings;

use FindBin qw($RealBin);
use File::Basename qw(basename);
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use POSIX ();
use Test::More;

use lib $RealBin, "$RealBin/..";
use MockBuildUtils qw(mock_chroot_uid mock_result_dirs);

# Flush before the first fork below, or the child repeats this file's TAP output on exit.
$| = 1;

my $tmp = tempdir(CLEANUP => 1);
make_path("$tmp/etc", "$tmp/run");

write_text("$tmp/etc/openeuler-24.03-ppc64le.cfg", <<'CFG');
config_opts['root'] = 'openeuler-24.03-ppc64le'
config_opts['chrootuid'] = 1000
config_opts['chrootgid'] = 1000
include('templates/openeuler-lts-xcat.tpl')
CFG
write_text("$tmp/etc/alma+epel-10-x86_64.cfg", "config_opts['root'] = 'alma+epel-10-x86_64'\n");
write_text("$tmp/run/mock-deterministic.cfg",
    "include('$tmp/etc/openeuler-24.03-ppc64le.cfg')\n"
  . "config_opts['environment']['SOURCE_DATE_EPOCH'] = '1757000000'\n");

is(mock_chroot_uid("$tmp/etc/openeuler-24.03-ppc64le.cfg"), 1000,
    'the openEuler ppc64le configuration builds as uid 1000');
is(mock_chroot_uid("$tmp/run/mock-deterministic.cfg"), 1000,
    'the deterministic wrapper carries the uid of the configuration it includes');
is(mock_chroot_uid("$tmp/etc/alma+epel-10-x86_64.cfg"), $>,
    'a configuration that names no chrootuid keeps the uid mock defaults to');

my @own = mock_result_dirs("$tmp/run/perl-IO-Stty", $>);
is_deeply([map { basename($_) } @own], [qw(srpm restamp-srpm rpm)],
    'a package build gets the three directories it gives mock as --resultdir');
ok(-d $_, basename($_) . ' is created') for @own;

SKIP: {
    skip 'a directory owned by another uid needs root', 7 if $> != 0;
    # tempdir gives 0700. A run reaches a result directory through /tmp and the work directory,
    # which the builder creates with the umask root starts with, so make the scratch tree match.
    chmod 0755, $tmp or die "Cannot make $tmp traversable: $!\n";
    my @dirs = mock_result_dirs("$tmp/run/perl-Net-DNS", 1000);
    is(scalar @dirs, 3, 'uid 1000 gets the same three directories');
    for my $dir (@dirs) {
        my $name = basename($dir);
        is((stat $dir)[4], 1000, "$name is owned by the build uid");
        ok(writable_as(1000, $dir), "$name takes a state.log written by the build uid");
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
