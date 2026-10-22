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

# Record the waits instead of sleeping, so a lock that cannot be recovered fails at once.
my @slept;
{
    no warnings 'redefine';
    *XCAT::NFSLock::_sleep = sub { push(@slept, $_[0]) };
}

# Keep the lock's own log out of the TAP stream.
open(my $log_fh, '>', \my $logged) or die "Cannot capture the log: $!";
select($log_fh);

sub take {
    my ($path) = @_;
    @slept = ();
    $logged = '';
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
    like($err, qr/failed after 2 retries/, 'acquire waits out its retries rather than stealing it');
    ok(-d "$path.borrow", 'the live borrow still exists');
}

# ---- 3. a borrow with no metadata is never assumed stale --------------------------------
# What the old protocol left behind, and what the sweeper exists for. The module's own rule is
# that staleness is never inferred from metadata it cannot validate, so this must NOT recover.
{
    my $path = stage('legacy-borrow.lock',
                     lock   => metadata(pid => $gone, pstart => '1'),
                     borrow => 'none');
    my ($lock, $err) = take($path);
    ok(!$lock, 'a borrow with no metadata is not treated as stale');
    like($err, qr/failed after 2 retries/, 'it waits out its retries instead');
    ok(-d "$path.borrow", 'and the borrow is left for the sweeper');
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

# ---- 6. a guard releases when the caller stops holding it ------------------------------
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
