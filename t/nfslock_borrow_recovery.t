#!/usr/bin/perl
# Assumption 5 of the protocol at the top of lib/XCAT/NFSLock.pm says a process cannot die while
# it holds lock.borrow. Under the CI it does: Jenkins sends SIGTERM and the OOM-killer sends
# SIGKILL. Step 3 is mkdir(lock.borrow), so a borrow left by a killed take-over made the lock
# PERMANENTLY unacquirable -- acquire skipped steps 4 to 7 for ever and told the operator to
# remove the lock by hand. A dead owner recovered in milliseconds while a dead TAKER never did.
#
# The borrow now carries the same metadata as the lock, so the same rule recovers both: a borrow
# whose owner is provably dead is removed, and one that cannot be proven dead is left alone.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use File::Temp qw(tempdir);
use File::Slurper qw(read_text write_text);
use POSIX ();
use XCAT::NFSLock qw(this_process format_metadata parse_metadata process_start);

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

# Record the waits instead of sleeping, so a lock that cannot be recovered fails at once. A
# scenario can set $on_wait to act between two attempts, which is what a live taker does.
my @slept;
my $on_wait;
{
    no warnings 'redefine';
    *XCAT::NFSLock::_sleep = sub { push(@slept, $_[0]); $on_wait->() if $on_wait };
}

# Keep the lock's own log out of the TAP stream.
open(my $log_fh, '>', \my $logged) or die "Cannot capture the log: $!";
select($log_fh);

sub take {
    my ($path) = @_;
    @slept   = ();
    $logged  = '';
    $on_wait = undef;
    my $lock = eval { XCAT::NFSLock->acquire($path, retries => 2, label => 'probe') };
    return ($lock, $@, $logged);
}

# ---- 1. the taker died, so the borrow is stale -------------------------------------------
# The defect. Both the owner and the taker are dead, and before this fix acquire never recovered.
{
    my $path = stage('dead-taker.lock',
                     lock   => metadata(pid => $gone, pstart => '1'),
                     borrow => metadata(pid => $gone, pstart => '2'));
    my ($lock, $err, $log) = take($path);
    ok($lock, 'a borrow whose owner is provably dead is recovered')
        or diag "acquire died: $err";
    ok(!-d "$path.borrow", 'the stale borrow is gone once the lock is held');
    like($log, qr/took-over/, 'and the lock reports a take-over, not a fresh acquisition');
    undef $lock;
}

# ---- 2. the taker is alive, so the borrow is a real transition ---------------------------
# Removing this borrow would let two takers rewrite one metadata file. Asserting WHICH outcome:
# a refusal naming the owner, not merely that something died.
{
    my $path = stage('live-taker.lock',
                     lock   => metadata(pid => $gone, pstart => '1'),
                     borrow => metadata(pid => $live, pstart => $live_start));
    my ($lock, $err) = take($path);
    ok(!$lock, 'a borrow held by a live process is left alone');
    like($err, qr/still held after 2 retries/, 'acquire waits out its retries rather than stealing it');
    ok(-d "$path.borrow", 'the live borrow still exists');
}

# ---- 3. a borrow with no metadata, unchanged over two attempts, is reaped ---------------
# What the earlier protocol left behind. It wrote no metadata into the borrow, and it held one
# for the time of two file reads, so a metadata-less borrow that two attempts find unchanged is
# held by nobody. Before this rule the lock was unacquirable for ever.
{
    my $path = stage('legacy-borrow.lock',
                     lock   => metadata(pid => $gone, pstart => '1'),
                     borrow => 'none');
    my ($lock, $err, $log) = take($path);
    ok($lock, 'a metadata-less borrow is reaped and the dead owner is then evicted')
        or diag "acquire died: $err";
    ok(!-d "$path.borrow", 'the stranded borrow is gone');
    like($log, qr/reaped-borrow .*no metadata/, 'and the log says which rule removed it');
    undef $lock;
}

# ---- 3a. ONE attempt is not enough -----------------------------------------------------
# The rule is "two attempts found it unchanged". Asserted on its own, because the stubbed sleep
# makes scenario 3 pass either way: here the borrow is written to between the attempts, exactly
# as a live taker writing its metadata would, so an unchanged test is the only thing that can
# refuse it.
{
    my $path = stage('touched-borrow.lock',
                     lock   => metadata(pid => $gone, pstart => '1'),
                     borrow => 'none');
    @slept = (); $logged = '';
    my $turn = 0;
    $on_wait = sub { mkdir("$path.borrow/busy-" . $turn++) };
    my $lock = eval { XCAT::NFSLock->acquire($path, retries => 2, label => 'probe') };
    ok(!$lock, 'a borrow that changes between two attempts is left alone');
    ok(-d "$path.borrow", 'so the borrow survives');
    cmp_ok($turn, '>', 1, 'control: the borrow really was touched between the attempts');
}

# ---- 3b. a borrow whose metadata does not validate is never assumed stale --------------
# A metadata file that exists but does not hash may be a half-finished write. The rule above
# covers an ABSENT file only, so this must still refuse.
{
    my $path = stage('junk-borrow.lock',
                     lock   => metadata(pid => $gone, pstart => '1'),
                     borrow => "pid=1\n");
    my ($lock, $err) = take($path);
    ok(!$lock, 'a borrow with invalid metadata is not treated as stale');
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

# ---- 8. a guard releases when the caller stops holding it ------------------------------
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
