#!/usr/bin/perl
# A process killed during an ownership transition leaves lock.borrow behind. Under the CI that
# happens: Jenkins sends SIGTERM and the OOM-killer sends SIGKILL. Step 3 used to be
# mkdir(lock.borrow), so a stranded borrow made the lock PERMANENTLY unacquirable -- acquire
# skipped steps 4 to 7 for ever and told the operator to remove the lock by hand.
#
# A transition whose taker is provably dead is now ended by SUPERSEDING it: the borrow is
# numbered, and a contender creates the next generation rather than removing the one it
# validated. Removing it by path was unsafe, because rmdir names a path and not the inode that
# was validated -- a reaper could delete a LIVE taker's borrow and two processes then took over
# one lock. The concurrent checks below hold that down at the exact interleaving.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use File::Temp qw(tempdir);
use File::Slurper qw(read_text write_text);
use POSIX ();
use Time::HiRes ();
use XCAT::NFSLock qw(this_process format_metadata parse_metadata process_start);

# A child killed at its barrier leaves a closed pipe behind. Without this, writing to it ends
# this process by signal, and a signal death names no check.
$SIG{PIPE} = 'IGNORE';

my $dir = tempdir(CLEANUP => 1);
my $me  = this_process();

# No process can have a pid above the kernel's pid_max, which is 2**22 at most. Asserted rather
# than assumed: every recovery check below depends on this pid really being dead.
my $gone = 2**22 + 7;
is(process_start($gone), undef, 'control: a pid above pid_max names no process');

my $live       = getppid();
my $live_start = process_start($live);
ok(defined($live_start), 'control: the parent pid does name a live process');

sub metadata { return format_metadata({ %$me, token => 'ab' x 16, @_ }) }

# Stage a lock and, optionally, a borrow beside it. $borrow is the metadata text for the borrow,
# or the string 'none' to stage a borrow with no metadata at all, as the old protocol left.
sub stage {
    my ($name, %o) = @_;
    my $path = "$dir/$name";
    mkdir($path) or die "Cannot stage $path: $!";
    write_text("$path/metadata", $o{lock}) if defined($o{lock});
    if (defined($o{borrow})) {
        mkdir("$path.borrow") or die "Cannot stage $path.borrow: $!";
        write_text("$path.borrow/metadata", $o{borrow}) if $o{borrow} ne 'none';
    }
    return $path;
}

# Record the waits instead of sleeping, so a lock that cannot be recovered fails at once. The
# cap matters: a retry loop that lost its bound would otherwise spin here for ever, and a test
# that hangs reads as one still running rather than as a defect caught.
my @slept;
{
    no warnings 'redefine';
    *XCAT::NFSLock::_sleep = sub {
        push(@slept, $_[0]);
        die "SLEEP CAP: a retry loop ran " . scalar(@slept) . " times\n" if @slept > 200;
    };
}

# Keep the lock's own log out of the TAP stream.
open(my $log_fh, '>', \my $logged) or die "Cannot capture the log: $!";
select($log_fh);

sub take {
    my ($path) = @_;
    @slept   = ();
    $logged  = '';
    my $lock = eval { XCAT::NFSLock->acquire($path, retries => 2, label => 'probe') };
    return ($lock, $@, $logged);
}

# A bounded read, so a child that never reaches its barrier fails the test instead of hanging it.
sub read_bounded {
    my ($fh, $want, $seconds) = @_;
    my $buf      = '';
    my $deadline = Time::HiRes::time() + $seconds;
    while (length($buf) < $want) {
        my $left = $deadline - Time::HiRes::time();
        return undef if $left <= 0;
        my $mask = '';
        vec($mask, fileno($fh), 1) = 1;
        return undef unless select(my $ready = $mask, undef, undef, $left);
        my $got = sysread($fh, my $chunk, $want - length($buf));
        return undef unless defined($got) && $got > 0;
        $buf .= $chunk;
    }
    return $buf;
}

# one_shot: an _at override that reports its arrival and blocks, the FIRST time it reaches
# $point. acquire passes that point once per attempt, and a contender that blocks on every
# attempt would never report its result.
sub one_shot {
    my ($point, $arrive, $gate) = @_;
    my $fired = 0;
    return sub {
        return if $fired || $_[0] ne $point;
        $fired = 1;
        syswrite($arrive, 'a');
        sysread($gate, my $go, 1);
        return;
    };
}

# contend: run $n acquires of $path in forked children, each stopped at $point until this
# process releases them all together. The interleaving is a barrier and not a delay, so the
# result does not depend on how fast the machine is. A child holds its lock until it is killed,
# so one winner cannot hide another by releasing first. Returns the number that acquired the
# lock, or undef when a child did not reach the barrier or report in time.
sub contend {
    my ($path, $n, $point) = @_;
    pipe(my $arrive_r, my $arrive_w) or die "pipe: $!";
    pipe(my $gate_r,   my $gate_w)   or die "pipe: $!";
    pipe(my $result_r, my $result_w) or die "pipe: $!";
    my @child;
    for my $i (1 .. $n) {
        my $pid = fork();
        die "fork: $!" unless defined $pid;
        if ($pid) { push @child, $pid; next }
        close($arrive_r); close($gate_w); close($result_r);
        # Detached, so a child writes no TAP and flushes none of this process's buffers.
        open(STDOUT, '>', '/dev/null');
        open(STDERR, '>', '/dev/null');
        no warnings 'redefine';
        *XCAT::NFSLock::_at = one_shot($point, $arrive_w, $gate_r);
        my $lock = eval { XCAT::NFSLock->acquire($path, retries => 3, label => 'race', quiet => 1) };
        syswrite($result_w, $lock ? '1' : '0');
        # Block until killed, holding whatever was acquired. _exit runs no END block.
        sysread($gate_r, my $hold, 1);
        POSIX::_exit(0);
    }
    close($arrive_w);
    close($gate_r);
    close($result_w);
    my $arrived = read_bounded($arrive_r, $n, 20);
    my $results;
    if (defined($arrived)) {
        syswrite($gate_w, 'g' x $n);
        $results = read_bounded($result_r, $n, 20);
    }
    kill('KILL', $_) for @child;
    waitpid($_, 0) for @child;
    close($_) for ($arrive_r, $gate_w, $result_r);
    return undef unless defined($arrived) && defined($results);
    return scalar(() = $results =~ /1/g);
}

# spawn: one acquire in a child, stopped the first time it reaches $point. The caller releases
# each child itself, so a test can order two contenders instead of starting them together. That
# order is what reproduces the defect below: releasing both at once has them race one mkdir,
# which is exclusive either way.
sub spawn {
    my ($path, $point, %o) = @_;
    pipe(my $arrive_r, my $arrive_w) or die "pipe: $!";
    pipe(my $gate_r,   my $gate_w)   or die "pipe: $!";
    pipe(my $result_r, my $result_w) or die "pipe: $!";
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    unless ($pid) {
        close($arrive_r); close($gate_w); close($result_r);
        open(STDOUT, '>', '/dev/null');
        open(STDERR, '>', '/dev/null');
        no warnings 'redefine';
        *XCAT::NFSLock::_at = one_shot($point, $arrive_w, $gate_r);
        my $lock = eval {
            XCAT::NFSLock->acquire($path, retries => $o{retries} // 3, label => 'race', quiet => 1);
        };
        syswrite($result_w, $lock ? '1' : '0');
        sysread($gate_r, my $hold, 1);    # hold what was acquired until killed
        POSIX::_exit(0);
    }
    close($arrive_w); close($gate_r); close($result_w);
    return { pid => $pid, arrive => $arrive_r, gate => $gate_w, result => $result_r };
}

sub arrived { return read_bounded($_[0]{arrive}, 1, 20) }
sub go      { return syswrite($_[0]{gate}, 'g') }
sub won     { return read_bounded($_[0]{result}, 1, 20) // 'no result' }
sub reap    {
    my ($h) = @_;
    kill('KILL', $h->{pid});
    waitpid($h->{pid}, 0);
    close($h->{$_}) for qw(arrive gate result);
    return;
}

# ---- 1. a contender that validated a borrow cannot unseat the one that holds it ---------
# THE DEFECT, at the interleaving that reaches it. _reap_borrow validated a borrow and then
# removed it BY PATH, so a contender stopped between those two steps removed whatever was at
# the path when it resumed -- which is a live taker's borrow, not the one it validated.
#
# A is stopped having validated the dead taker. B then takes the borrow and stops before it
# writes the lock. Releasing A makes A act on its stale decision while B is live.
{
    my $path = stage('unseat.lock.d',
                     lock   => metadata(pid => $gone, pstart => '1'),
                     borrow => metadata(pid => $gone, pstart => '2'));
    my $a = spawn($path, 'before-supersede');
    is(arrived($a), 'a', 'control: A validated the dead taker and holds no borrow yet');
    my $b = spawn($path, 'before-commit');
    is(arrived($b), 'a', 'control: B holds the borrow and has not written the lock yet');

    go($a);
    my $first = won($a);
    go($b);
    my $second = won($b);
    is("$first$second", '01', 'A cannot take over as well: only the holder of the borrow does');
    reap($a);
    reap($b);
}

# ---- 1a. two contenders released together still produce one winner ---------------------
# THE DEFECT. _reap_borrow validated a borrow and then removed it by path, so two contenders
# that both validated the same dead taker both reached mkdir(lock.borrow) and both took over.
# Superseding is a single mkdir of generation N+1, which is exclusive, so one contender wins and
# the other finds a live taker.
{
    my $path = stage('supersede.lock.d',
                     lock   => metadata(pid => $gone, pstart => '1'),
                     borrow => metadata(pid => $gone, pstart => '2'));
    my $won = contend($path, 2, 'before-supersede');
    is($won, 1, 'exactly one of two contenders takes over a lock whose owner and taker are dead');
}

# ---- 2. a contender that has not written its metadata yet is never superseded ----------
# The reviewer's case, and the one an "unchanged for T seconds" rule cannot cover: a live taker
# can pause for any length of time between its mkdir and its first write. Superseding it would
# put two processes in the transition.
{
    my $path = stage('paused.lock.d', lock => metadata(pid => $gone, pstart => '1'));
    pipe(my $arrive_r, my $arrive_w) or die "pipe: $!";
    pipe(my $gate_r,   my $gate_w)   or die "pipe: $!";
    my $paused = fork();
    die "fork: $!" unless defined $paused;
    unless ($paused) {
        close($arrive_r); close($gate_w);
        open(STDOUT, '>', '/dev/null'); open(STDERR, '>', '/dev/null');
        no warnings 'redefine';
        *XCAT::NFSLock::_at = one_shot('borrow-created', $arrive_w, $gate_r);
        eval { XCAT::NFSLock->acquire($path, retries => 3, label => 'paused', quiet => 1) };
        POSIX::_exit(0);
    }
    close($arrive_w); close($gate_r);
    my $reached = read_bounded($arrive_r, 1, 20);
    is($reached, 'a', 'control: a contender holds generation 0 with no metadata written yet');
    ok(-d "$path.borrow", 'control: generation 0 exists');
    ok(!-e "$path.borrow/metadata", 'control: and it holds no metadata');

    my ($lock, $err) = take($path);
    ok(!$lock, 'a generation whose taker has written no metadata is not superseded');
    like($err, qr/still held after 2 retries/, 'the second contender waits out its retries');
    ok(-d "$path.borrow", 'and the paused contender keeps its generation');
    ok(!-d "$path.borrow.1", 'no later generation was created');

    syswrite($gate_w, 'g');
    waitpid($paused, 0);
    close($arrive_r); close($gate_w);
}

# ---- 3. a dead taker's generation is superseded, not removed ---------------------------
# The fix, stated as what is on disk afterwards: generation 0 survives, because nothing removes
# a generation it did not create, and the take-over ran in generation 1.
{
    my $path = stage('keep-generation.lock.d',
                     lock   => metadata(pid => $gone, pstart => '1'),
                     borrow => metadata(pid => $gone, pstart => '2'));
    my ($lock, $err, $log) = take($path);
    ok($lock, 'a lock whose owner and taker are both dead is taken over') or diag "acquire died: $err";
    ok(-d "$path.borrow", 'the dead taker generation is left in place, never removed');
    ok(!-d "$path.borrow.1", 'and the generation this process created is gone');
    like($log, qr/took-borrow .*superseded generation 0/, 'the log names the generation it superseded');
    undef $lock;
}

# ---- 3a. a generation with no valid metadata blocks, and only the sweeper clears it -----
# WITHDRAWN RULE. An earlier revision reclaimed a metadata-less borrow when two attempts found
# it unchanged. Scenario 2 is why that is wrong. The disposition is the one a metadata-less
# lock.d already has: acquire refuses, and sweep_stranded removes it under an exclusive claim.
{
    my $root = "$dir/legacy";
    mkdir $root or die $!;
    my $path = "$root/legacy.lock.d";
    mkdir $path or die $!;
    write_text("$path/metadata", metadata(pid => $gone, pstart => '1'));
    mkdir "$path.borrow" or die $!;

    my ($lock, $err) = take($path);
    ok(!$lock, 'a borrow with no metadata is not reclaimed by acquire');
    like($err, qr/still held after 2 retries/, 'it waits out its retries instead');
    ok(-d "$path.borrow", 'and the borrow is left for the sweeper');

    my %kept = map { $_->{path} => $_ } XCAT::NFSLock::sweep_stranded($root, undef);
    is($kept{"$path.borrow"}{action}, 'kept', 'the sweeper keeps it without an exclusive claim');
    my %swept = map { $_->{path} => $_ } XCAT::NFSLock::sweep_stranded($root, undef, exclusive => 1);
    is($swept{"$path.borrow"}{action}, 'removed', 'and removes it under one');
    ok(!-d "$path.borrow", 'so the lock can be taken over again');
}

# ---- 3b. a borrow whose metadata does not validate is never assumed stale --------------
# A metadata file that exists but does not hash may be a half-finished write.
{
    my $path = stage('junk-borrow.lock.d',
                     lock   => metadata(pid => $gone, pstart => '1'),
                     borrow => "pid=1\n");
    my ($lock, $err) = take($path);
    ok(!$lock, 'a borrow with invalid metadata is not superseded');
    like($err, qr/still held after 2 retries/, 'it waits out its retries instead');
    ok(-d "$path.borrow", 'and the borrow is left alone');
}

# ---- 4. a borrow this module creates carries metadata -----------------------------------
# Scenario 1 can only work if the taker records who it is. Without this the next acquirer has
# nothing to validate and falls into scenario 3.
{
    my $path = stage('records-taker.lock', lock => metadata(pid => $gone, pstart => '1'));
    my $seen;
    {
        no warnings 'redefine';
        my $real = \&XCAT::NFSLock::owner_is_dead;
        # Read the borrow's metadata at the moment the take-over holds it.
        local *XCAT::NFSLock::owner_is_dead = sub {
            $seen //= eval { read_text("$path.borrow/metadata") };
            return $real->(@_);
        };
        my $lock = eval { XCAT::NFSLock->acquire($path, retries => 2, label => 'probe') };
        undef $lock;
    }
    ok(defined($seen) && length($seen), 'the borrow holds metadata while the take-over runs');
    my $id = parse_metadata($seen);
    ok($id, 'that metadata is valid and hashes correctly');
    is($id && $id->{pid}, $$, 'and it names the process doing the take-over');
}

# ---- 5. the sweeper covers the lock names this project actually uses --------------------
# sweep_stranded removes state a killed process left under one root. Its matcher read '.lock'
# and '.lock.borrow' only, so it swept mockbuild-all.pl's cell locks and silently missed
# cluster-test.pl's <repo>/.build.lock.d and sbuild-all.pl's .sbuild-all.<arch>.nfslock -- which
# is where the permanent strand this file is about would land.
{
    my $root = "$dir/sweep";
    mkdir $root or die $!;
    my %made;
    for my $n (qw(.x86_64.lock .build.lock.d .sbuild-all.amd64.nfslock)) {
        mkdir "$root/$n" or die $!;
        write_text("$root/$n/metadata", metadata(pid => $gone, pstart => '1'));
        $made{$n} = "$root/$n";
    }
    mkdir "$root/.build.lock.d.borrow" or die $!;
    $made{'.build.lock.d.borrow'} = "$root/.build.lock.d.borrow";
    # A superseded transition leaves numbered generations, which the matcher must also see.
    mkdir "$root/.x86_64.lock.borrow.2" or die $!;
    $made{'.x86_64.lock.borrow.2'} = "$root/.x86_64.lock.borrow.2";
    # A live owner and another machine must survive the sweep, so the matcher widening cannot be
    # read as "remove more".
    mkdir "$root/.live.lock.d" or die $!;
    write_text("$root/.live.lock.d/metadata", metadata(pid => $live, pstart => $live_start));
    mkdir "$root/.other.lock.d" or die $!;
    write_text("$root/.other.lock.d/metadata",
               metadata(pid => $gone, pstart => '1', 'machine-id' => 'f' x 32));

    my %act = map { $_->{path} => $_->{action} }
              XCAT::NFSLock::sweep_stranded($root, undef, exclusive => 1);
    is($act{$made{'.x86_64.lock'}}, 'removed', 'a stale .lock is swept, as before');
    is($act{$made{'.build.lock.d'}}, 'removed', 'a stale .lock.d is swept');
    is($act{$made{'.build.lock.d.borrow'}}, 'removed', 'a stranded .lock.d.borrow is swept');
    is($act{$made{'.x86_64.lock.borrow.2'}}, 'removed', 'a stranded numbered generation is swept');
    is($act{$made{'.sbuild-all.amd64.nfslock'}}, 'removed', 'a stale .nfslock is swept');
    is($act{"$root/.live.lock.d"}, 'kept', 'a lock whose owner is alive is kept');
    is($act{"$root/.other.lock.d"}, 'kept', 'a lock owned by another machine is kept');
}

# ---- 6. a lock.d with no metadata is refused, and only the sweeper removes it ----------
# The build lock in xcat-core wrote no metadata and held lock.d for the whole build, so a
# metadata-less lock.d can be a live build of the earlier code. acquire must refuse it: no fact
# on disk tells that holder from a dead one. Only a caller that claims the root exclusively may
# call it abandoned, which is the one condition under which the sweeper removes it.
{
    my $root = "$dir/no-metadata";
    mkdir $root or die $!;
    my $path = "$root/buildrpms.openeuler-20.03sp4-x86_64.lock.d";
    mkdir $path or die $!;

    my ($lock, $err) = take($path);
    ok(!$lock, 'a lock.d with no metadata is not taken over');
    like($err, qr/still held after 2 retries/, 'acquire waits out its retries and names the lock');
    ok(-d $path, 'and the directory is left for the sweeper');

    my %kept = map { $_->{path} => $_ } XCAT::NFSLock::sweep_stranded($root, undef);
    is($kept{$path}{action}, 'kept', 'the sweeper keeps it without an exclusive claim');
    like($kept{$path}{why}, qr/no exclusive claim/, 'and names the rule that kept it');

    my %swept = map { $_->{path} => $_ } XCAT::NFSLock::sweep_stranded($root, undef, exclusive => 1);
    is($swept{$path}{action}, 'removed', 'with the exclusive claim it is removed');
    ok(!-d $path, 'so a later build can take the lock');
}

# ---- 7. a forked child cannot release its parent's lock --------------------------------
# DESTROY calls release, so a child that inherits a guard and exits would otherwise remove a
# lock its parent still holds. The pid test in release is the only thing that stops it.
{
    my $path = "$dir/forked.lock.d";
    my $lock = XCAT::NFSLock->acquire($path, retries => 1, label => 'forked', quiet => 1);
    pipe(my $reader, my $writer) or die "pipe: $!";
    my $child = fork();
    die "fork: $!" unless defined $child;
    unless ($child) {
        close $reader;
        my $freed = $lock->release;
        syswrite($writer, $freed ? "freed\n" : "kept\n");
        # _exit, so the child runs no END block and flushes none of the parent's buffers.
        POSIX::_exit(0);
    }
    close $writer;
    my $said = <$reader> // '';
    close $reader;
    waitpid($child, 0);
    is($said, "kept\n", 'release in a forked child frees nothing');
    ok(-d $path, 'and the parent still holds its lock');
    ok($lock->release, 'which the owning process can then release itself');
}

# ---- 8. a take-over whose commit fails returns that error, and cleans up nothing --------
# acquire set identity before writing the lock metadata, so a write that left partial metadata
# and threw gave DESTROY a lock to release. release then retried for ever, because lock.d
# existed and its metadata could not be validated, and the caller never saw the write error.
#
# The sleep is capped so an unbounded release reports a different error instead of hanging. The
# check is on the error TEXT: anything that merely dies would pass a check for "it died".
{
    my $path = stage('commit-fails.lock.d', lock => metadata(pid => $gone, pstart => '1'));
    my $capped = 0;
    my $lock;
    my $err;
    {
        no warnings 'redefine';
        local *XCAT::NFSLock::_sleep = sub { die "SLEEP CAP\n" if ++$capped > 30 };
        my $real = \&XCAT::NFSLock::_write_metadata;
        # The lock's own metadata write truncates and then fails, as ENOSPC and EIO do.
        local *XCAT::NFSLock::_write_metadata = sub {
            return $real->(@_) unless $_[0] eq $path;
            write_text("$path/metadata", 'pid=');
            die "Cannot write $path/metadata: No space left on device\n";
        };
        $lock = eval { XCAT::NFSLock->acquire($path, retries => 2, label => 'commit', quiet => 1) };
        $err = $@;
    }
    ok(!$lock, 'the take-over fails');
    is($err, "Cannot write $path/metadata: No space left on device\n",
        'and the write error reaches the caller unchanged');
    is($capped, 0, 'and the destructor did not try to clean up at all');
    ok(!-d "$path.borrow", 'the borrow generation it took is given back');
}

# ---- 9. release is bounded --------------------------------------------------------------
# release is reached from DESTROY, where an unbounded wait stops the process instead of
# returning. A lock whose metadata cannot be validated is the case that never resolves.
{
    my $path = "$dir/bounded.lock.d";
    my $lock = XCAT::NFSLock->acquire($path, retries => 4, label => 'bounded', quiet => 1);
    write_text("$path/metadata", 'pid=');          # no longer validates, and never will
    @slept = ();
    my $freed = eval { $lock->release };
    is($freed, 0, 'release gives up rather than waiting for metadata that cannot validate')
        or diag "release died: $@";
    cmp_ok(scalar(@slept), '<=', 5, 'and it waits R times at most, not for ever');
    is(eval { $lock->release }, 0, 'a second call does not start again');
    unlink "$path/metadata"; rmdir $path;
}

# ---- 10. a guard releases when the caller stops holding it -----------------------------
# Without DESTROY the lock is held to the end of the process, and no take-over recovers it
# either, because its owner is alive. Every caller here keeps its guards in an array for that
# reason, so the leak was invisible.
{
    my $path = "$dir/scope.lock.d";
    {
        my $l = XCAT::NFSLock->acquire($path, retries => 1, label => 'scope', quiet => 1);
        ok(-d $path, 'control: the lock directory exists while the guard is held');
    }
    ok(!-d $path, 'the lock is released when the guard goes out of scope');
    my $again = eval { XCAT::NFSLock->acquire($path, retries => 1, label => 'scope', quiet => 1) };
    ok($again, 'so the same process can take it again') or diag "acquire died: $@";
}

select(STDOUT);
done_testing();
