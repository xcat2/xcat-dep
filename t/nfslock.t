#!/usr/bin/perl
# XCAT::NFSLock: a directory lock that only its owner, or a process that proves
# the owner dead on the owner's machine, removes.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use File::Temp qw(tempdir);
use File::Slurper qw(read_text write_text);
use Errno qw(ENOENT);
use POSIX ();
use Time::HiRes ();

my $retransmit;

BEGIN {
    no warnings 'once';
    # An NFS retransmit: the first rename succeeded, the reply said ENOENT.
    *CORE::GLOBAL::rename = sub {
        my ($from, $to) = @_;
        if (defined($retransmit) && $to eq $retransmit) {
            CORE::rename($from, $to) or die "Cannot stage $to: $!";
            $! = ENOENT;
            return 0;
        }
        return CORE::rename($from, $to);
    };
}

use XCAT::NFSLock qw(owner_record parse_owner owner_is_dead process_start);

my $dir = tempdir(CLEANUP => 1);
my $me  = parse_owner(owner_record());
ok($me, 'the owner record of this process parses');
is($me->{pid}, $$, 'the owner record names this process');
is($me->{start}, process_start($$), 'the owner record carries the start time of this process');

# No process can have a pid above the kernel's pid_max (2**22 at most).
my $gone = 2**22 + 7;
is(process_start($gone), undef, 'a pid that names no process has no start time');

my $parent       = getppid();
my $parent_start = process_start($parent);

sub record {
    my (%f) = @_;
    my %r = (%$me, host => 'peer', created => 1, %f);
    return join('', map { "$_\n" } 'nfslock2', map { "$_=$r{$_}" } qw(machine boot pid start token host created));
}

sub stage {
    my ($name, $record) = @_;
    my $path = "$dir/$name";
    mkdir($path) or die "Cannot stage $path: $!";
    write_text("$path/owner", $record) if defined($record);
    return $path;
}

sub leftovers {
    my ($path) = @_;
    return [ map { s{\A\Q$dir\E/}{}r } glob("$path.*") ];
}

# A free lock is taken with its metadata and released without leftovers.
{
    my $path = "$dir/free.lock";
    my $lock = XCAT::NFSLock->acquire($path, meta => { job => "xcat-dep-build-el10\n" });
    is(read_text("$path/owner"), $lock->{record}, 'a free lock is taken with this owner record');
    is(read_text("$path/job"), "xcat-dep-build-el10\n", 'the metadata is in the lock');
    is($lock->release, 1, 'the owner releases its lock');
    ok(!-e $path, 'the released lock is gone');
    is_deeply(leftovers($path), [], 'release leaves nothing beside the lock');
    is($lock->release, 0, 'a second release does nothing');
}

for my $bad ('', "$dir/.", "$dir/..", "$dir/") {
    eval { XCAT::NFSLock->acquire($bad); 1 };
    like($@, qr/\AInvalid lock path/, "a lock path that names no entry is refused: '$bad'");
}

for my $retry (0, 0.5, -1) {
    eval { XCAT::NFSLock->acquire("$dir/bad-retry.lock", retry => $retry); 1 };
    like($@, qr/\AInvalid retry interval $retry for lock: must be more than 0\.5s/,
        "a retry interval of ${retry}s is refused");
}

# A waiter takes the lock once its live owner releases it.
{
    my $path = "$dir/handover.lock";
    pipe(my $ready_r, my $ready_w) or die "Cannot pipe: $!";
    my $child = fork() // die "Cannot fork: $!";
    if ($child == 0) {
        close($ready_r);
        my $held = XCAT::NFSLock->acquire($path);
        syswrite($ready_w, "x");
        Time::HiRes::sleep(0.5);
        $held->release;
        POSIX::_exit(0);
    }
    close($ready_w);
    sysread($ready_r, my $byte, 1);
    my $start = Time::HiRes::time();
    my $lock  = eval { XCAT::NFSLock->acquire($path, timeout => 10, retry => 0.6) };
    my $spent = Time::HiRes::time() - $start;
    waitpid($child, 0);
    ok($lock, 'a waiter takes the lock after its owner releases it') or diag($@);
    cmp_ok($spent, '<', 3, 'the waiter retries at its interval, not at the timeout');
    $lock->release if $lock;
}

eval { XCAT::NFSLock->acquire("$dir/bad-meta.lock", meta => { owner => 'x' }); 1 };
like($@, qr/\AInvalid metadata name 'owner'/, 'metadata cannot replace the owner record');
eval { XCAT::NFSLock->acquire("$dir/bad-meta.lock", meta => { '../x' => 'x' }); 1 };
like($@, qr/\AInvalid metadata name '\.\.\/x'/, 'metadata names stay inside the lock');

# Live owners and owners that cannot be proven dead keep their lock.
for my $case (
    [ 'live owner on this machine', record(pid => $parent, start => $parent_start) ],
    [ 'owner on another machine',   record(machine => 'elsewhere', pid => $gone) ],
    [ 'record in another format',   "somebody-else\n" ],
    [ 'lock with no owner file',    undef ],
  )
{
    my ($name, $record) = @$case;
    (my $file = "$name.lock") =~ s/\s+/-/g;
    my $path = stage($file, $record);
    write_text("$path/data", 'kept');
    eval { XCAT::NFSLock->acquire($path, timeout => 0.3, label => 'repository lock'); 1 };
    like($@, qr/\ATrying to unlock \Q$path\E failed after 0\.3s; repository lock owned by /,
        "$name: the wait ends with an error that names the lock");
    is(read_text("$path/data"), 'kept', "$name: the lock is left in place");
    is_deeply(leftovers($path), [], "$name: no breaker or private tree is left behind");
}

# Owners proven dead on this machine lose their lock.
for my $case (
    [ 'process gone',     record(pid => $gone) ],
    [ 'pid reused',       record(pid => $parent, start => $parent_start + 1) ],
    [ 'machine rebooted', record(boot => 'an-earlier-boot', pid => $parent, start => $parent_start) ],
  )
{
    my ($name, $record) = @$case;
    (my $file = "$name.lock") =~ s/\s+/-/g;
    my $path = stage($file, $record);
    my $lock = eval { XCAT::NFSLock->acquire($path) };
    ok($lock, "$name: the lock of a dead owner is taken") or diag($@);
    is(read_text("$path/owner"), $lock && $lock->{record}, "$name: the lock now names this process");
    is_deeply(leftovers($path), [], "$name: the breaker and the old lock are gone");
    $lock->release if $lock;
}

# Another process is breaking the lock: this one does not remove it.
{
    my $dead = record(pid => $gone);
    my $path = stage('breaking.lock', $dead);
    my $busy = record(pid => $parent, start => $parent_start);
    stage('breaking.lock.break', $busy);
    eval { XCAT::NFSLock->acquire($path, timeout => 0.3); 1 };
    like($@, qr/\ATrying to unlock /, 'a lock under another breaker is not taken');
    is(read_text("$path/owner"), $dead, 'the lock under another breaker is left in place');
    is(read_text("$path.break/owner"), $busy, 'the other breaker is left in place');
}

# The owner is alive by the time of the break: the breaker does not remove the lock.
{
    my $live = record(pid => $parent, start => $parent_start);
    my $path = stage('changed.lock', $live);
    is(XCAT::NFSLock::_break($path), 0, 'a lock whose owner is alive at the break is not removed');
    is(read_text("$path/owner"), $live, 'the owner keeps its lock');
    is_deeply(leftovers($path), [], 'the breaker is released');
}

# A forked child of the owner does not release the lock.
{
    my $path = "$dir/forked.lock";
    my $lock = XCAT::NFSLock->acquire($path);
    my $child = fork() // die "Cannot fork: $!";
    POSIX::_exit($lock->release ? 1 : 0) if $child == 0;
    waitpid($child, 0);
    is($? >> 8, 0, 'the child reports that it released nothing');
    ok(-d $path, 'the lock survives the child');
    is($lock->release, 1, 'the owner still releases it');
}

# A delete that NFS holds back (a file still open is renamed to .nfsXXXX and
# stays) does not keep the lock: release takes it away first.
{
    my $path = "$dir/held-open.lock";
    my $lock = XCAT::NFSLock->acquire($path);
    {
        no warnings 'redefine';
        local *XCAT::NFSLock::remove_tree = sub { return 0 };
        is($lock->release, 1, 'release succeeds while the delete is held back');
    }
    ok(!-e $path, 'the lock is gone while its old tree still exists');
    my $next = eval { XCAT::NFSLock->acquire($path) };
    ok($next, 'the next owner takes the lock at once') or diag($@);
    $next->release if $next;
}

# One process takes the lock once: a second acquire is another owner.
{
    my $path = "$dir/twice.lock";
    my $first = XCAT::NFSLock->acquire($path);
    my $second = eval { XCAT::NFSLock->acquire($path) };
    ok(!$second, 'a second acquire in the same process does not take a held lock');
    is($first->release, 1, 'the first owner still holds and releases it');
}

# The lock was replaced: release leaves the other owner's lock alone.
{
    my $path = "$dir/replaced.lock";
    my $lock = XCAT::NFSLock->acquire($path);
    my $other = record(pid => $parent, start => $parent_start);
    write_text("$path/owner", $other);
    is($lock->release, 0, 'release does not remove a lock with another record');
    is(read_text("$path/owner"), $other, 'the other owner keeps its lock');
}

# NFS answered with an error to a rename that had succeeded.
{
    my $path = $retransmit = "$dir/retransmit.lock";
    my $lock = eval { XCAT::NFSLock->acquire($path) };
    ok($lock, 'a retransmitted rename that placed this record takes the lock') or diag($@);
    undef $retransmit;
}

# Leftovers: detached trees go, a private build goes only when its creator is dead.
{
    my $path = "$dir/swept.lock";
    stage('swept.lock.dead.1.00000001', record(pid => $parent, start => $parent_start));
    stage('swept.lock.tmp.2.00000002',  record(pid => $gone));
    stage('swept.lock.tmp.3.00000003',  record(pid => $parent, start => $parent_start));
    my $lock = XCAT::NFSLock->acquire($path);
    is_deeply(leftovers($path), ['swept.lock.tmp.3.00000003'],
        'the sweep removes detached trees and dead builds, and keeps a live build');
    $lock->release;
}

# owner_is_dead decides from facts only.
{
    my %here = (machine => 'm1', boot => 'b1', start_of => sub { $_[0] == 10 ? 100 : undef });
    my %rec  = (machine => 'm1', boot => 'b1', pid => 10, start => 100);
    is(owner_is_dead(undef, \%here), 0, 'an unreadable record is not proven dead');
    is(owner_is_dead({ %rec }, \%here), 0, 'a live owner is not dead');
    is(owner_is_dead({ %rec, machine => 'm2' }, \%here), 0, 'another machine proves nothing');
    is(owner_is_dead({ %rec, machine => 'm2', pid => 11 }, \%here), 0,
        'another machine proves nothing, even for a pid that is free here');
    is(owner_is_dead({ %rec, boot => 'b0' }, \%here), 1, 'an owner from an earlier boot is dead');
    is(owner_is_dead({ %rec, pid => 11 }, \%here), 1, 'an owner whose pid is gone is dead');
    is(owner_is_dead({ %rec, start => 99 }, \%here), 1, 'an owner whose pid was reused is dead');
}

is(parse_owner("nfslock2\nmachine=m\nboot=b\npid=0\nstart=1\n"), undef, 'a record with pid 0 is rejected');
is(parse_owner("nfslock2\nmachine=m\nboot=b\npid=5\n"), undef, 'a record without a start time is rejected');
is(parse_owner("nfslock1\nmachine=m\nboot=b\npid=5\nstart=1\n"), undef, 'a record in another format is rejected');

done_testing();
