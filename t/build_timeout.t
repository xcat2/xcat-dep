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
use XCAT::BuildUtils qw(run_bounded emulated_build_timeout);
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

done_testing();
