#!/usr/bin/perl
# XCAT::NFSLock: the NFS lock protocol at the top of lib/XCAT/NFSLock.pm.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use File::Temp qw(tempdir);
use File::Slurper qw(read_text write_text);
use POSIX ();
use Time::HiRes ();

my $renames = 0;
my @mkdirs;

BEGIN {
    no warnings 'once';
    *CORE::GLOBAL::rename = sub { $renames++; return CORE::rename($_[0], $_[1]) };
    *CORE::GLOBAL::mkdir  = sub { push(@mkdirs, $_[0]); return @_ > 1 ? CORE::mkdir($_[0], $_[1]) : CORE::mkdir($_[0]) };
}

use XCAT::NFSLock qw(this_process format_metadata parse_metadata owner_is_dead process_start);

# The lock logs to the selected handle. Keep the log out of the TAP stream, and read it back.
open(my $log_fh, '>', \my $logged) or die "Cannot capture the log: $!";
select($log_fh);

sub clear_log { $logged = ''; seek($log_fh, 0, 0) }

my $dir = tempdir(CLEANUP => 1);
my $me  = this_process();
is($me->{pid}, $$, 'the identity names this process');
is($me->{pstart}, process_start($$), 'the identity carries the start time of this process');
isnt(this_process()->{token}, $me->{token}, 'each identity has a fresh token');

# No process can have a pid above the kernel's pid_max (2**22 at most).
my $gone = 2**22 + 7;
is(process_start($gone), undef, 'a pid that names no process has no start time');

my $parent       = getppid();
my $parent_start = process_start($parent);

sub metadata {
    my (%f) = @_;
    return format_metadata({ %$me, token => 'ab' x 16, %f });
}

sub stage {
    my ($name, $text) = @_;
    my $path = "$dir/$name";
    mkdir($path) or die "Cannot stage $path: $!";
    write_text("$path/metadata", $text) if defined($text);
    return $path;
}

# Record the waits instead of sleeping. $on_sleep runs at each wait.
my @slept;
our $on_sleep;
{
    no warnings 'redefine';
    *XCAT::NFSLock::_sleep = sub { push(@slept, $_[0]); $on_sleep->() if $on_sleep };
}

# Metadata: fields, hash, validation.
{
    my $text = metadata();
    is_deeply(parse_metadata($text), { %$me, token => 'ab' x 16 }, 'valid metadata parses to its identity');
    like($text, qr/\Aboot-id=.*\nmachine-id=.*\npid=.*\npstart=.*\ntoken=.*\nhash=[0-9a-f]{64}\n\z/,
        'the fields are sorted and the hash comes last');
    is(parse_metadata(substr($text, 0, length($text) - 10)), undef, 'a partial read is invalid');
    is(parse_metadata($text =~ s/pid=\d+/pid=1/r), undef, 'a changed field no longer matches the hash');
    is(parse_metadata($text =~ s/^token=.*\n//mr), undef, 'a missing field is invalid');
    is(parse_metadata("extra=1\n$text"), undef, 'an unknown field is invalid');
    is(parse_metadata(undef), undef, 'missing metadata is invalid');
}

# A free lock is taken and released without leftovers.
{
    my $path = "$dir/free.lock";
    my $lock = XCAT::NFSLock->acquire($path);
    my $meta = parse_metadata(read_text("$path/metadata"));
    is($meta && $meta->{pid}, $$, 'a free lock is taken with the identity of this process');
    is($lock->release, 1, 'the owner releases its lock');
    ok(!-e $path, 'the released lock.d is gone');
    ok(!-e "$path.borrow", 'release removes lock.borrow');
    is($lock->release, 0, 'a second release does nothing');
}

for my $bad ('', "$dir/.", "$dir/..", "$dir/") {
    eval { XCAT::NFSLock->acquire($bad); 1 };
    like($@, qr/\AInvalid lock path/, "a lock path that names no entry is refused: '$bad'");
}

for my $case (
    [ { retries => 0 },                qr/\AInvalid retries 0 for lock/ ],
    [ { retries => 1.5 },              qr/\AInvalid retries 1\.5 for lock/ ],
    [ { delay => 2.9 },                qr/\AInvalid delay 2\.9 for lock: must be 3s or more/ ],
    [ { jitter => -1 },                qr/\AInvalid jitter -1 for lock: must be 0 or more/ ],
    [ { delay => 3, jitter => 1.5 },   qr/\AInvalid jitter 1\.5 for lock: must be less than half the delay/ ],
  )
{
    my ($opt, $error) = @$case;
    eval { XCAT::NFSLock->acquire("$dir/bad-option.lock", %$opt); 1 };
    like($@, $error, 'an invalid retry option is refused: ' . join(',', %$opt));
    ok(!-e "$dir/bad-option.lock", 'an invalid option creates no lock');
}

# Retry: R waits of T ± δ, then an error that names the lock.
{
    my $path = stage('retried.lock', metadata(pid => $parent, pstart => $parent_start));
    @slept = ();
    eval { XCAT::NFSLock->acquire($path, retries => 4, delay => 5, jitter => 2, label => 'cell lock'); 1 };
    like($@, qr/\ATrying to unlock \Q$path\E failed after 4 retries; cell lock owned by pid $parent on machine /,
        'the error names the lock, the retries and the owner');
    is(scalar(@slept), 4, 'acquire waits R times');
    is(scalar(grep { $_ >= 3 && $_ <= 7 } @slept), 4, 'each wait is within T ± δ');

    @slept = ();
    eval { XCAT::NFSLock->acquire($path, timeout => 10); 1 };
    like($@, qr/failed after 4 retries;/, 'a timeout of 10s with the default delay of 3s is 4 retries');
    @slept = ();
    eval { XCAT::NFSLock->acquire($path); 1 };
    like($@, qr/failed after 1 retry;/, 'a lock with no timeout still retries once');
}

# The lock stays with an owner that is not proven dead.
for my $case (
    [ 'live owner on this machine', metadata(pid => $parent, pstart => $parent_start) ],
    [ 'owner on another machine',   metadata('machine-id' => 'elsewhere', pid => $gone) ],
    [ 'partial metadata',           substr(metadata(pid => $gone), 0, 40) ],
    [ 'metadata with a bad hash',   metadata(pid => $gone) =~ s/hash=(.)/'hash=' . ($1 eq '0' ? '1' : '0')/er ],
    [ 'no metadata',                undef ],
  )
{
    my ($name, $text) = @$case;
    (my $file = "$name.lock") =~ s/\s+/-/g;
    my $path = stage($file, $text);
    @mkdirs = ();
    eval { XCAT::NFSLock->acquire($path, retries => 2); 1 };
    like($@, qr/\ATrying to unlock \Q$path\E failed after 2 retries;/, "$name: the lock is not taken");
    is(scalar(grep { $_ eq "$path.borrow" } @mkdirs), $name =~ /live owner/ ? 3 : 0,
        "$name: lock.borrow is tried only for an owner on this machine with valid metadata");
    is(-e "$path/metadata" ? read_text("$path/metadata") : undef, $text, "$name: the metadata is unchanged");
    ok(!-e "$path.borrow", "$name: lock.borrow is not left behind");
}

# A dead owner on this machine loses the lock.
for my $case (
    [ 'process gone',     metadata(pid => $gone) ],
    [ 'pid reused',       metadata(pid => $parent, pstart => $parent_start + 1) ],
    [ 'machine rebooted', metadata('boot-id' => 'an-earlier-boot', pid => $parent, pstart => $parent_start) ],
  )
{
    my ($name, $text) = @$case;
    (my $file = "$name.lock") =~ s/\s+/-/g;
    my $path = stage($file, $text);
    @slept = ();
    my $lock = eval { XCAT::NFSLock->acquire($path) };
    ok($lock, "$name: the lock of a dead owner is taken") or diag($@);
    is(scalar(@slept), 0, "$name: the lock is taken without a wait");
    my $meta = parse_metadata(read_text("$path/metadata"));
    is($meta && $meta->{pid}, $$, "$name: the metadata now names this process");
    isnt($meta && $meta->{token}, 'ab' x 16, "$name: the new metadata has a fresh token");
    ok(!-e "$path.borrow", "$name: lock.borrow is removed");
    is($lock->release, 1, "$name: the new owner releases the lock") if $lock;
}

# Another process holds lock.borrow: this one does not take the lock.
{
    my $dead = metadata(pid => $gone);
    my $path = stage('borrowed.lock', $dead);
    mkdir("$path.borrow") or die "Cannot stage $path.borrow: $!";
    eval { XCAT::NFSLock->acquire($path, retries => 2); 1 };
    like($@, qr/\ATrying to unlock /, 'a lock under another borrower is not taken');
    is(read_text("$path/metadata"), $dead, 'the metadata under another borrower is unchanged');
    ok(-d "$path.borrow", 'the other borrower keeps lock.borrow');
}

# The owner changed between step 2 and step 4: this attempt does not take the lock,
# even when the new owner is dead too.
{
    my $path = stage('changed.lock', metadata(pid => $gone));
    my $other = metadata(pid => $gone, token => 'cd' x 16);
    my $read = \&XCAT::NFSLock::_read_metadata;
    my $reads = 0;
    no warnings 'redefine';
    local *XCAT::NFSLock::_read_metadata = sub {
        write_text("$path/metadata", $other) if ++$reads == 2;
        return $read->(@_);
    };
    @slept = ();
    my $lock = eval { XCAT::NFSLock->acquire($path, retries => 1) };
    ok($lock, 'the lock is taken on the next attempt') or diag($@);
    is(scalar(@slept), 1, 'a changed owner costs one retry');
    ok(!-e "$path.borrow", 'lock.borrow is removed');
    $lock->release if $lock;
}

# release waits for a process that holds lock.borrow.
{
    my $path = "$dir/release-borrowed.lock";
    my $lock = XCAT::NFSLock->acquire($path);
    mkdir("$path.borrow") or die "Cannot stage $path.borrow: $!";
    @slept = ();
    local $on_sleep = sub { rmdir("$path.borrow") };
    is($lock->release, 1, 'release removes the lock once lock.borrow is free');
    is(scalar(@slept), 1, 'release waits while lock.borrow is held');
    ok(!-e $path && !-e "$path.borrow", 'lock.d and lock.borrow are gone');
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

# The metadata names another acquisition: release leaves the lock alone.
{
    my $path = "$dir/replaced.lock";
    my $lock = XCAT::NFSLock->acquire($path);
    my $other = metadata(pid => $parent, pstart => $parent_start);
    write_text("$path/metadata", $other);
    is($lock->release, 0, 'release does not remove a lock of another acquisition');
    is(read_text("$path/metadata"), $other, 'the other owner keeps its lock');
    ok(!-e "$path.borrow", 'release removes lock.borrow');
}

# One process takes the lock once: a second acquire is another owner.
{
    my $path = "$dir/twice.lock";
    my $first = XCAT::NFSLock->acquire($path);
    my $second = eval { XCAT::NFSLock->acquire($path) };
    ok(!$second, 'a second acquire in the same process does not take a held lock');
    is($first->release, 1, 'the first owner still holds and releases it');
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
    local $on_sleep = sub { waitpid($child, 0) };
    my $lock = eval { XCAT::NFSLock->acquire($path, retries => 1) };
    ok($lock, 'a waiter takes the lock after its owner releases it') or diag($@);
    $lock->release if $lock;
}

# owner_is_dead decides from facts only.
{
    my %here = ('machine-id' => 'm1', 'boot-id' => 'b1', start_of => sub { $_[0] == 10 ? 100 : undef });
    my %rec  = ('machine-id' => 'm1', 'boot-id' => 'b1', pid => 10, pstart => 100);
    is(owner_is_dead(undef, \%here), 0, 'invalid metadata is not proven dead');
    is(owner_is_dead({%rec}, \%here), 0, 'a live owner is not dead');
    is(owner_is_dead({ %rec, 'machine-id' => 'm2', pid => 11 }, \%here), 0,
        'another machine proves nothing, even for a pid that is free here');
    is(owner_is_dead({ %rec, 'boot-id' => 'b0' }, \%here), 1, 'an owner from an earlier boot is dead');
    is(owner_is_dead({ %rec, pid => 11 }, \%here), 1, 'an owner whose pid is gone is dead');
    is(owner_is_dead({ %rec, pstart => 99 }, \%here), 1, 'an owner whose pid was reused is dead');
}

# The log names each event, in the order it happened.
{
    my $stamp = qr/\[nfslock\] \d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z \S+ pid=$$/;
    my $path = "$dir/logged.lock";
    clear_log();
    my $lock = XCAT::NFSLock->acquire($path, label => 'cell lock');
    $lock->release;
    my @lines = split(/\n/, $logged);
    is(scalar(@lines), 2, 'a lock taken and released logs two lines');
    like($lines[0], qr/\A$stamp acquired cell lock \Q$path\E\z/, 'the first line is the acquisition');
    like($lines[1], qr/\A$stamp released cell lock \Q$path\E\z/, 'the second line is the release');

    my $held = stage('logged-wait.lock', metadata(pid => $parent, pstart => $parent_start));
    clear_log();
    eval { XCAT::NFSLock->acquire($held, retries => 2); 1 };
    my @waits = $logged =~ /^$stamp wait lock \Q$held\E (retry \d\/\d), owner pid $parent on machine /mg;
    is_deeply(\@waits, ['retry 1/2', 'retry 2/2'], 'each retry logs a wait that names the owner');

    my $dead = stage('logged-dead.lock', metadata(pid => $gone));
    clear_log();
    my $taken = XCAT::NFSLock->acquire($dead);
    like($logged, qr/^$stamp took-over lock \Q$dead\E from dead pid $gone$/m, 'a takeover names the dead owner');
    $taken->release;

    clear_log();
    my $quiet = XCAT::NFSLock->acquire("$dir/quiet.lock", quiet => 1);
    $quiet->release;
    eval { XCAT::NFSLock->acquire($held, retries => 1, quiet => 1); 1 };
    is($logged, '', 'quiet => 1 logs nothing');
}

is($renames, 0, 'the lock never renames');

done_testing();
