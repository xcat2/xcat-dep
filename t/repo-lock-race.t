#!/usr/bin/perl
# The per-arch runs of one build share a single --repo-dep tree and all pass --force-unlock, so
# they remove and recreate <repo-dep>/.lock at the same time. Over NFS the loser of that race sees
# the directory disappear between its failed mkdir and the -d test that follows, and
# acquire_named_lock ended the whole build with "Cannot create lock ...: Stale file handle"
# (xcat-dep-el-cd build 141, ppc64le branch, two seconds into the build stage).
#
# mockbuild-all.pl is a program and cannot be loaded, so the two lock routines are extracted and
# run in a scratch package. The race is produced exactly and without timing: mkdir is replaced for
# one call, and that call removes the directory the peer holds and reports ESTALE.
use strict;
use warnings;
use Test::More tests => 7;
use FindBin qw($RealBin);
use File::Temp qw(tempdir);
use Errno qw(EEXIST ESTALE);

my $script = "$RealBin/../mockbuild-all.pl";
open my $in, '<', $script or die "Cannot read $script: $!";
my $source = do { local $/; <$in> };
close $in;

my %routine;
for my $name (qw(_rmdir_lock acquire_named_lock)) {
    my ($body) = $source =~ /^(sub \Q$name\E \{.*?^\})/ms;
    die "$script no longer defines sub $name; this test covers nothing\n" unless $body;
    $routine{$name} = $body;
}

my $peer_base = tempdir(CLEANUP => 1);
my $peer_lock = "$peer_base/.lock";
mkdir $peer_lock or die "Cannot stage the peer lock $peer_lock: $!";

my $held_base = tempdir(CLEANUP => 1);
mkdir "$held_base/.lock" or die "Cannot stage the held lock $held_base/.lock: $!";

# A peer that keeps winning the race: every mkdir under this base reports EEXIST.
my $busy_base = tempdir(CLEANUP => 1);
my $busy_lock = "$busy_base/.lock";

# One stale-handle failure, on the peer lock only. Installed before the routines are compiled so
# the override reaches them; the mkdir calls above are already compiled and use the real one.
my $stale_left = 1;
{
    no warnings 'once';
    *CORE::GLOBAL::mkdir = sub {
        my ($path, @mode) = @_;
        if ($path eq $busy_lock) {
            $! = EEXIST;
            return 0;
        }
        if ($stale_left && $path eq $peer_lock) {
            $stale_left = 0;
            rmdir $path;
            $! = ESTALE;
            return 0;
        }
        return @mode ? CORE::mkdir($path, $mode[0]) : CORE::mkdir($path);
    };
}

my $package = join("\n",
    'package LockUnderTest;',
    'use strict; use warnings;',
    'use Errno qw(EEXIST ESTALE);',
    'our @HELD_LOCKS; our $LOCK_OWNER_PID;',
    'sub capture_command { return "test-host" }',
    $routine{_rmdir_lock},
    $routine{acquire_named_lock},
    '1;',
);
ok(eval($package), 'the extracted lock routines compile') or die "$@\n";

my $acquired = eval { LockUnderTest::acquire_named_lock($peer_base, 'repository', 1); 1 };
my $error = $@;
ok($acquired, 'a lost mkdir race under --force-unlock does not end the build') or diag($error);
is($stale_left, 0, 'the staged stale handle was consumed, so the race did happen');
ok(-d $peer_lock, 'the caller holds the lock after the retry');

# A peer that keeps the lock must not end the build either. --force-unlock says the lock cannot
# stop the run, and the per-arch runs write different architectures of the shared tree.
my $gave_up = eval { LockUnderTest::acquire_named_lock($busy_base, 'repository', 1) };
my $busy_error = $@;
ok(defined($gave_up), 'a peer that keeps the lock does not end the build') or diag($busy_error);
is($gave_up, 0, 'the run reports it does not hold the lock');

# A real conflict must still stop the run: without --force-unlock a lock another run owns is fatal.
eval { LockUnderTest::acquire_named_lock($held_base, 'repository', 0); 1 };
like($@, qr/is locked/, 'without --force-unlock a lock another run owns still stops the build');
