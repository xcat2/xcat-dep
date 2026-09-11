#!/usr/bin/perl
# Behaviour test for the wall-clock bound on emulated build steps. It DRIVES run_bounded with a
# command that hangs and asserts that the call returns, fails, and prints the evidence -- it never
# reads the source of the thing it tests.
#
# Every call under test runs in a forked child whose stdio is detached to a file, and the parent
# bounds that child itself. Without the bound in run_bounded the child would block forever; a child
# holding this test's stdout would block prove instead of failing it, so the failure of the code
# under test must show up as a FAILED assertion here, never as a hung suite.
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin;
use POSIX ();
use Test::More;

use lib "$FindBin::Bin/../lib", "$FindBin::Bin/..";
use XCAT::BuildUtils qw(run_bounded emulated_build_timeout block_handled_signals restore_signal_mask exit_status);
use BuildUtils qw(chroot_build_timeout);

my $tmp = tempdir(CLEANUP => 1);
my @strays;
# waitpid on an already-gone child sets $? to -1, and Test::Builder's END reads $? as the exit
# status. Save it, or a clean run reports "exited with -1".
END { local $?; for my $p (@strays) { kill('KILL', $p); waitpid($p, 0); } }

# drive(): run one run_bounded call in a detached child and wait at most {deadline} seconds for it.
# Returns the child's result plus whether it finished on its own -- "did not finish" is the assertion
# that catches an unbounded run_bounded, which would otherwise hang this test.
sub drive {
    my (%a) = @_;
    my $out = "$tmp/$a{name}.out";
    my $res = "$tmp/$a{name}.res";
    my $t0  = time;

    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if ($pid == 0) {
        open(STDIN,  '<',  '/dev/null');
        open(STDOUT, '>',  $out) or POSIX::_exit(90);
        open(STDERR, '>&', \*STDOUT);
        POSIX::setpgid(0, 0);
        my $r = eval {
            run_bounded(cmd => $a{cmd}, timeout => $a{timeout},
                        sample => $a{sample}, label => $a{name}, out => \*STDOUT);
        } || { ec => -99, timed_out => 0, elapsed => -1 };
        if (open(my $fh, '>', $res)) { print {$fh} "$r->{ec} $r->{timed_out} $r->{elapsed}\n"; close($fh); }
        POSIX::_exit(0);
    }
    POSIX::setpgid($pid, $pid);

    my $deadline = $t0 + $a{deadline};
    my $finished = 0;
    while (time < $deadline) {
        if (waitpid($pid, POSIX::WNOHANG()) == $pid) { $finished = 1; last; }
        select(undef, undef, undef, 0.2);
    }
    # Reap unconditionally: an unreaped child keeps its group alive and the next test inherits it.
    unless ($finished) { kill('KILL', -$pid); waitpid($pid, 0); }

    my ($ec, $timed_out, $elapsed) = (-1, 0, -1);
    if (open(my $fh, '<', $res)) { ($ec, $timed_out, $elapsed) = split(' ', <$fh> // ''); close($fh); }
    my $text = '';
    if (open(my $fh, '<', $out)) { local $/; $text = <$fh> // ''; close($fh); }
    return { finished => $finished, ec => $ec, timed_out => $timed_out,
             elapsed => $elapsed, out => $text, wall => time - $t0 };
}

# --- the budget itself -----------------------------------------------------------------------
is(emulated_build_timeout('amd64', 'amd64'), 900, 'a native build gets the native budget');
is(emulated_build_timeout('riscv64', 'amd64'), 9000,
    'an emulated build gets ten times the native budget');
{
    local $ENV{XCAT_DEP_BUILD_TIMEOUT} = 42;
    is(chroot_build_timeout('noble-riscv64-sbuild'), 42, 'XCAT_DEP_BUILD_TIMEOUT overrides the budget');
}
{
    local %ENV = %ENV; delete $ENV{XCAT_DEP_BUILD_TIMEOUT};
    is(chroot_build_timeout('noble-riscv64-sbuild'), 9000,
        'a riscv64 chroot on this host derives the emulated budget');
}

# --- a command that exits normally is not touched --------------------------------------------
my $ok = drive(name => 'exit0', cmd => 'exit 0', timeout => 60, sample => 1, deadline => 30);
ok($ok->{finished}, 'a fast command returns');
is($ok->{ec}, 0, 'its exit status is 0');
is($ok->{timed_out}, 0, 'it is not reported as timed out');

my $bad = drive(name => 'exit3', cmd => 'exit 3', timeout => 60, sample => 1, deadline => 30);
is($bad->{ec}, 3, 'a failing command keeps its exit status');

# --- THE DEFECT: a build that hangs must fail, within the budget, with evidence ---------------
my $hang = drive(name => 'hang', cmd => 'exec sleep 600 >/dev/null 2>&1',
                 timeout => 4, sample => 2, deadline => 90);
ok($hang->{finished}, 'a hanging command does NOT hang the caller')
    or BAIL_OUT('run_bounded never returned: the bound is missing, so a hung build has no failure');
is($hang->{timed_out}, 1, 'the hang is reported as a timeout');
is($hang->{ec}, 124, 'the timeout exit status is 124, as timeout(1) uses');
cmp_ok($hang->{wall}, '<', 60, 'it fails soon after the budget, not later');
like($hang->{out}, qr/exceeded its 4s budget/, 'the failure names the budget it exceeded');
like($hang->{out}, qr/stall report: process group \d+/, 'it prints the process group');
like($hang->{out}, qr/PID\s+PPID\s+STAT\s+TICKS\s+DELTA\s+WCHAN\s+CMD/, 'it prints the process tree');
like($hang->{out}, qr/sockets: \d+/, 'it prints the open socket count');
like($hang->{out}, qr/CPU ticks consumed by the whole group during the sample: 0/,
    'it samples CPU ticks and finds none');
like($hang->{out}, qr/DEADLOCKED, not slow/, 'it says the build was deadlocked rather than slow');

# --- a busy build is reported differently, so the sample means something ----------------------
my $busy = drive(name => 'busy', cmd => 'exec bash -c "while :; do :; done" >/dev/null 2>&1',
                 timeout => 4, sample => 2, deadline => 90);
ok($busy->{finished}, 'a spinning command is also bounded');
is($busy->{timed_out}, 1, 'the spin is reported as a timeout');
like($busy->{out}, qr/still consumes CPU/, 'a spinning build is NOT called deadlocked');
unlike($busy->{out}, qr/DEADLOCKED/, 'the CPU sample distinguishes a slow build from a deadlock');

# --- the whole process group dies, not just the shell ----------------------------------------
my $pidfile = "$tmp/grandchild.pid";
my $tree = drive(name => 'tree',
                 cmd => "sleep 600 >/dev/null 2>&1 & echo \$! > $pidfile; wait",
                 timeout => 4, sample => 1, deadline => 90);
ok($tree->{finished}, 'a command with a child of its own is bounded too');
my $gpid = 0;
if (open(my $fh, '<', $pidfile)) { chomp($gpid = <$fh> // 0); close($fh); }
ok($gpid > 0, 'the grandchild recorded its pid');
push @strays, $gpid if $gpid > 0;
my $alive = 1;
for (1 .. 50) { $alive = (-d "/proc/$gpid") ? 1 : 0; last unless $alive; select(undef, undef, undef, 0.2); }
is($alive, 0, 'the grandchild is killed with the group, so nothing survives holding the pipe');

# A signal to the orchestrator must reach the build. Without forwarding, the wrapper dies and
# releases its locks while the build keeps running and writing into staging, so the next run races
# an orphan it cannot see. The child records its own pid, the wrapper is terminated, and the pid is
# probed afterwards.
{
    my $dir = tempdir( CLEANUP => 1 );
    my $pidfile = "$dir/child.pid";

    my $wrapper = fork();
    die "fork failed: $!" unless defined $wrapper;
    if ( $wrapper == 0 ) {
        # long budget: the bound must NOT be what ends this run -- the signal must be
        run_bounded(
            cmd     => "echo \$\$ > '$pidfile'; exec sleep 300",
            timeout => 600,
            label   => 'cancellation probe',
            out     => \*STDERR,
        );
        POSIX::_exit(0);
    }

    my $child;
    for ( 1 .. 100 ) {
        if ( -s $pidfile ) {
            open my $fh, '<', $pidfile or last;
            chomp( $child = <$fh> // '' );
            close $fh;
            last if $child;
        }
        select( undef, undef, undef, 0.1 );
    }

  SKIP: {
        skip 'child never reported its pid', 2 unless $child;
        ok( kill( 0, $child ), 'the build is running before the wrapper is signalled' );

        kill 'TERM', $wrapper;
        waitpid( $wrapper, 0 );

        my $alive = 1;
        for ( 1 .. 100 ) {
            $alive = kill( 0, $child );
            last unless $alive;
            select( undef, undef, undef, 0.1 );
        }
        ok( !$alive, 'terminating the wrapper reaps the build it started' );
        kill 'KILL', $child if $alive;
    }
}

# The same must hold with no deadline. An unbounded run used to call system(), which leaves the
# build in the orchestrator's own process group: a directed signal then killed the orchestrator and
# left the build writing into staging.
{
    my $dir     = tempdir( CLEANUP => 1 );
    my $pidfile = "$dir/child.pid";

    my $wrapper = fork();
    die "fork failed: $!" unless defined $wrapper;
    if ( $wrapper == 0 ) {
        run_bounded(
            cmd     => "echo \$\$ > '$pidfile'; exec sleep 300",
            timeout => 0,
            label   => 'unbounded cancellation probe',
            out     => \*STDERR,
        );
        POSIX::_exit(0);
    }

    my $child;
    for ( 1 .. 100 ) {
        if ( -s $pidfile ) {
            open my $fh, '<', $pidfile or last;
            chomp( $child = <$fh> // '' );
            close $fh;
            last if $child;
        }
        select( undef, undef, undef, 0.1 );
    }

  SKIP: {
        skip 'child never reported its pid', 2 unless $child;
        ok( kill( 0, $child ), 'the unbounded build is running before the wrapper is signalled' );

        kill 'TERM', $wrapper;
        waitpid( $wrapper, 0 );

        my $alive = 1;
        for ( 1 .. 100 ) {
            $alive = kill( 0, $child );
            last unless $alive;
            select( undef, undef, undef, 0.1 );
        }
        ok( !$alive, 'terminating the wrapper reaps an unbounded build too' );
        kill 'KILL', $child if $alive;
    }
}

# forward_signals_to_workers: the orchestrator forks its own workers, so run_bounded's forwarding
# never sees a signal sent to it. Two real processes stand in for a worker and the build it runs.
{
    my $dir     = tempdir( CLEANUP => 1 );
    my $pidfile = "$dir/worker.pid";

    my $wrapper = fork();
    die "fork failed: $!" unless defined $wrapper;
    if ( $wrapper == 0 ) {
        my %kids;
        my $worker = fork();
        if ( defined $worker && $worker == 0 ) {
            open my $fh, '>', $pidfile or POSIX::_exit(1);
            print {$fh} "$$\n";
            close $fh;
            sleep 300;
            POSIX::_exit(0);
        }
        $kids{$worker} = 1;
        my $forward = XCAT::BuildUtils::forward_signals_to_workers(
            pids => \%kids,
            reap => sub { waitpid( $_, 0 ) for keys %kids },
        );
        local $SIG{TERM} = $forward;
        sleep 300;
        POSIX::_exit(0);
    }

    my $worker;
    for ( 1 .. 100 ) {
        if ( -s $pidfile ) {
            open my $fh, '<', $pidfile or last;
            chomp( $worker = <$fh> // '' );
            close $fh;
            last if $worker;
        }
        select( undef, undef, undef, 0.1 );
    }

  SKIP: {
        skip 'worker never reported its pid', 2 unless $worker;
        ok( kill( 0, $worker ), 'the worker is running before the orchestrator is signalled' );

        kill 'TERM', $wrapper;
        waitpid( $wrapper, 0 );

        my $alive = 1;
        for ( 1 .. 100 ) {
            $alive = kill( 0, $worker );
            last unless $alive;
            select( undef, undef, undef, 0.1 );
        }
        ok( !$alive, 'signalling the orchestrator reaps its forked workers' );
        kill 'KILL', $worker if $alive;
    }
}

# The build must not inherit a blocked signal mask: run_bounded blocks INT, TERM and HUP across
# the fork so a cancellation cannot land before its handler exists, and a child that kept that mask
# would ignore the very signal the forwarding relies on.
{
    my $dir = tempdir( CLEANUP => 1 );
    my $out = "$dir/mask";
    my $r = run_bounded(
        cmd     => "grep ^SigBlk /proc/self/status > '$out'",
        timeout => 30,
        label   => 'signal mask probe',
        out     => \*STDERR,
    );
    is( $r->{ec}, 0, 'the probe ran' );
  SKIP: {
        skip 'no /proc/self/status on this host', 1 unless -s $out;
        open my $fh, '<', $out or die $!;
        my $line = <$fh>;
        close $fh;
        my ($mask) = $line =~ /SigBlk:\s*([0-9a-f]+)/;
        my $blocked = hex( $mask // 'ffffffffffffffff' );
        # bit n-1 is signal n: INT 2, TERM 15, HUP 1
        my $handled = ( 1 << 1 ) | ( 1 << 14 ) | ( 1 << 0 );
        is( $blocked & $handled, 0, 'the build starts with INT, TERM and HUP unblocked' );
    }
}

# The caller's own mask must be restored: run_bounded blocks INT, TERM and HUP around the fork, and
# leaving them blocked would make the orchestrator ignore a cancellation for the rest of the run.
{
    my $dir = tempdir( CLEANUP => 1 );
    my $out = "$dir/caller-mask";
    run_bounded( cmd => 'true', timeout => 30, label => 'mask restore probe', out => \*STDERR );
    system("grep ^SigBlk /proc/self/status > '$out' 2>/dev/null");
  SKIP: {
        skip 'no /proc/self/status on this host', 1 unless -s $out;
        open my $fh, '<', $out or die $!;
        my $line = <$fh>;
        close $fh;
        my ($mask) = $line =~ /SigBlk:\s*([0-9a-f]+)/;
        my $blocked = hex( $mask // 'ffffffffffffffff' );
        my $handled = ( 1 << 1 ) | ( 1 << 14 ) | ( 1 << 0 );
        is( $blocked & $handled, 0, 'the caller keeps INT, TERM and HUP unblocked afterwards' );
    }
}

# block_handled_signals holds a cancellation until the caller can act on it. This is the window
# between forking a worker and being able to signal it: delivered there, the signal kills the parent
# under a handler that does not know the child, and the child keeps building.
{
    my @caught;
    local $SIG{TERM} = sub { push @caught, 'TERM' };

    my $previous = block_handled_signals();
    kill 'TERM', $$;
    select( undef, undef, undef, 0.2 );
    is_deeply( \@caught, [], 'a signal sent while blocked is not delivered' );

    restore_signal_mask($previous);
    select( undef, undef, undef, 0.2 );
    is_deeply( \@caught, ['TERM'], '... and arrives once the mask is restored' );
}

# A child the kernel kills leaves 0 in the high byte of its wait status. Reading only that byte
# reports a cancelled or OOM-killed build as one that succeeded, which is what the orchestrators do
# with the status wait() gives them.
{
    is( exit_status(0),    0,   'a child that exited 0 reports 0' );
    is( exit_status(256),  1,   'a child that exited 1 reports 1' );
    is( exit_status(65280), 255, 'a child that exited 255 reports 255' );
    is( exit_status(15),   143, 'a child killed by TERM reports 128 plus the signal' );
    is( exit_status(9),    137, 'a child killed by KILL reports 128 plus the signal' );
    is( exit_status(139),  139, 'a segfault with a core dump still reports the signal' );

    # The same status through the bounded path, so the helper and its caller agree.
    my $r = run_bounded( cmd => 'kill -TERM $$', timeout => 30, label => 'signal exit',
                         out => \*STDERR );
    is( $r->{ec}, 143, 'run_bounded reports a signalled command the same way' );
    is( $r->{timed_out}, 0, '... and does not call it a timeout' );
}

# The leader of the build's process group can die without its descendants: a SIGKILL or the OOM
# killer takes the shell and leaves schroot and qemu behind, still holding the chroot. They are not
# children of this process, so nothing waits for them and nothing reported them.
{
    my $dir     = tempdir( CLEANUP => 1 );
    my $pidfile = "$dir/descendant.pid";
    my $r = run_bounded(
        cmd     => "sleep 300 & echo \$! > '$pidfile'; kill -KILL \$\$",
        timeout => 60,
        label   => 'leader killed while a descendant runs',
        out     => \*STDERR,
    );
    is( $r->{ec}, 137, 'the leader is reported as killed by SIGKILL' );

    my $descendant;
    for ( 1 .. 30 ) {
        if ( -s $pidfile ) {
            open my $fh, '<', $pidfile or last;
            chomp( $descendant = <$fh> // '' );
            close $fh;
            last if $descendant;
        }
        select( undef, undef, undef, 0.1 );
    }
  SKIP: {
        skip 'the descendant never reported its pid', 1 unless $descendant;
        my $alive = 1;
        for ( 1 .. 50 ) {
            $alive = kill( 0, $descendant );
            last unless $alive;
            select( undef, undef, undef, 0.1 );
        }
        ok( !$alive, 'the descendant does not outlive the call' );
        kill 'KILL', $descendant if $alive;
    }
}

done_testing;
