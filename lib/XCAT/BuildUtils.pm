package XCAT::BuildUtils;

use strict;
use warnings;

use Digest::MD5 ();
use Digest::SHA ();
use Exporter qw(import);
use File::Find qw(find);
use File::Slurper qw(read_binary write_binary);
use File::Spec;
use IPC::Cmd qw(can_run);
use POSIX ();
use Time::HiRes ();

our @EXPORT_OK = qw(
  capture_command
  command_exists
  digest_file
  digest_manifest
  display_quote
  every_step_failed
  forward_signals_to_workers
  block_handled_signals
  exit_status
  restore_signal_mask
  hashes_equal
  print_step
  read_binary
  read_first_line
  read_lines
  relative_files
  require_command
  run_bounded
  run_command
  shell_quote
  stall_report
  emulated_build_timeout
  write_binary
);

sub command_exists {
    my ($command) = @_;
    return defined(can_run($command));
}

sub require_command {
    my ($command) = @_;
    return can_run($command)
      // die "Required command not found: $command\n";
}

sub capture_command {
    my (@command) = @_;
    open(my $fh, '-|', @command) or die "Cannot run $command[0]: $!\n";
    local $/;
    my $output = <$fh> // '';
    close($fh) or die "Command failed: $command[0]\n";
    $output =~ s/\s+\z//;
    return $output;
}

sub run_command {
    my (@command) = @_;
    print '+ ', join(' ', map { display_quote($_) } @command), "\n";
    my $status = system(@command);
    return 1 if $status == 0;

    my $exit = $status == -1
      ? 255
      : ($status & 127) ? 128 + ($status & 127) : $status >> 8;
    die "Command failed (rc=$exit): "
      . join(' ', map { display_quote($_) } @command) . "\n";
}

# ---------------------------------------------------------------------------------------------------
# Bounded command execution (build steps that can run under emulation)
# ---------------------------------------------------------------------------------------------------

# NATIVE_BUILD_TIMEOUT: the per-package wall-clock budget for a build on the host architecture.
# EMULATION_FACTOR: qemu-user under TCG runs at roughly a tenth of native speed, so a foreign-arch
# target gets ten times the budget. Both numbers come from measured runs of this tree, not a guess:
# on xcat-master-ub the slowest native (amd64) package took 3 minutes, and the slowest emulated
# (riscv64) package -- ipmitool-xcat on resolute -- took 26 minutes with four codenames building at
# once. 900s and 9000s therefore sit about five times above the worst build ever measured, which is
# the margin that keeps a busy host from producing a false failure.
our $NATIVE_BUILD_TIMEOUT = 900;
our $EMULATION_FACTOR     = 10;

# emulated_build_timeout($target_arch, $host_arch): the budget for a build of $target_arch on
# $host_arch. Equal arches are native. Any other pair is emulated through qemu-user.
sub emulated_build_timeout {
    my ($target_arch, $host_arch) = @_;
    return $NATIVE_BUILD_TIMEOUT
      if !defined($target_arch) || !defined($host_arch) || $target_arch eq $host_arch;
    return $NATIVE_BUILD_TIMEOUT * $EMULATION_FACTOR;
}

# proc_pgid_pids($pgid): every live pid in process group $pgid, read from /proc rather than matched
# against a command line. `pgrep -af X | grep -c Y` counts its own command line, and bracketing the
# pattern still self-matches when the surrounding command carries the bare word, so this code never
# matches text at all.
sub proc_pgid_pids {
    my ($pgid) = @_;
    my @pids;
    opendir(my $dh, '/proc') or return ();
    for my $e (sort { $a <=> $b } grep { /^\d+$/ } readdir($dh)) {
        my $f = _proc_stat_fields($e) or next;
        push @pids, $e if defined($f->{pgrp}) && $f->{pgrp} == $pgid;
    }
    closedir($dh);
    return @pids;
}

# _proc_stat_fields($pid): the /proc/<pid>/stat fields this module reads. The comm field is wrapped
# in parentheses and may itself contain a space or a parenthesis, so the split starts after the LAST
# ')'.
sub _proc_stat_fields {
    my ($pid) = @_;
    open(my $fh, q{<}, "/proc/$pid/stat") or return;
    my $line = <$fh>;
    close($fh);
    return unless defined $line;
    my $close = rindex($line, ')');
    return if $close < 0;
    my $comm = substr($line, index($line, '(') + 1, $close - index($line, '(') - 1);
    my @f = split(' ', substr($line, $close + 2));
    return {
        comm  => $comm,
        state => $f[0],
        ppid  => $f[1],
        pgrp  => $f[2],
        ticks => (($f[11] // 0) + ($f[12] // 0)),
    };
}

sub _proc_read {
    my ($path) = @_;
    open(my $fh, '<', $path) or return '';
    local $/;
    my $t = <$fh> // '';
    close($fh);
    $t =~ s/\0/ /g;
    $t =~ s/\s+\z//;
    return $t;
}

# _proc_socket_count($pid): how many of the pid's descriptors are sockets. A build that is waiting on
# the network holds one; the deadlock this bound exists for held none.
sub _proc_socket_count {
    my ($pid) = @_;
    opendir(my $dh, "/proc/$pid/fd") or return -1;
    my $n = 0;
    for my $fd (grep { /^\d+$/ } readdir($dh)) {
        my $l = readlink("/proc/$pid/fd/$fd") // '';
        $n++ if $l =~ /^socket:/;
    }
    closedir($dh);
    return $n;
}

# stall_report($pgid, %opt): the evidence a hung build needs, gathered before the kill. For every pid
# in the process group it prints the parent, the state, the kernel wchan and stack, the socket count,
# and the CPU ticks the pid consumed across a sample window. The tick delta is what separates a
# deadlock from a slow build: a package that is merely slow keeps accumulating ticks, and the
# goconserver deadlock this bound exists for accumulated none over twenty seconds.
#   %opt: sample (seconds, default 20), out (filehandle, default STDERR)
sub stall_report {
    my ($pgid, %opt) = @_;
    my $sample = defined $opt{sample} ? $opt{sample} : 20;
    my $out    = $opt{out} || \*STDERR;

    my @pids = proc_pgid_pids($pgid);
    my %before = map { $_ => (_proc_stat_fields($_) || {})->{ticks} } @pids;
    sleep($sample) if $sample > 0;
    my @after_pids = proc_pgid_pids($pgid);
    my %seen = map { $_ => 1 } @pids;
    push @pids, grep { !$seen{$_} } @after_pids;

    my $total = 0;
    print {$out} "--- stall report: process group $pgid, ${sample}s CPU sample ---\n";
    printf {$out} "%-8s %-8s %-5s %-10s %-10s %-24s %s\n",
        'PID', 'PPID', 'STAT', 'TICKS', 'DELTA', 'WCHAN', 'CMD';
    for my $pid (@pids) {
        my $f = _proc_stat_fields($pid) or next;
        my $delta = ($f->{ticks} // 0) - ($before{$pid} // 0);
        $delta = 0 if $delta < 0;
        $total += $delta;
        my $cmd = _proc_read("/proc/$pid/cmdline") || "[$f->{comm}]";
        $cmd = substr($cmd, 0, 120);
        printf {$out} "%-8s %-8s %-5s %-10s %-10s %-24s %s\n",
            $pid, $f->{ppid}, $f->{state}, $f->{ticks}, $delta,
            (_proc_read("/proc/$pid/wchan") || '?'), $cmd;
        my $stack = _proc_read("/proc/$pid/stack");
        print {$out} "    stack: $_\n" for grep { length } split(/\n/, $stack);
        my $socks = _proc_socket_count($pid);
        print {$out} "    sockets: $socks\n" if $socks >= 0;
    }
    print {$out} "--- CPU ticks consumed by the whole group during the sample: $total\n";
    print {$out} $total == 0
        ? "--- no CPU ticks: the build is DEADLOCKED, not slow.\n"
        : "--- the build still consumes CPU: it exceeded the budget rather than deadlocking.\n";
    return $total;
}

# exit_status($status): the exit code of a waited-for child, or 128 plus the signal that killed it.
# A child killed by a signal has 0 in the high byte, so reading only that byte reports a build the
# kernel terminated as a build that succeeded.
sub exit_status {
    my ($status) = @_;
    return 0 unless defined $status;
    return ($status & 127) ? 128 + ($status & 127) : $status >> 8;
}

# block_handled_signals(): block INT, TERM and HUP and return the previous mask, for the window
# between forking a child and being able to signal it. A cancellation arriving in that window would
# otherwise kill the parent under a handler that does not know the child yet, and the child would
# keep running. A blocked signal stays pending and is delivered by restore_signal_mask().
sub block_handled_signals {
    my $handled  = POSIX::SigSet->new(POSIX::SIGINT(), POSIX::SIGTERM(), POSIX::SIGHUP());
    my $previous = POSIX::SigSet->new();
    POSIX::sigprocmask(POSIX::SIG_BLOCK(), $handled, $previous);
    return $previous;
}

# restore_signal_mask($previous): put the mask back, delivering anything that arrived meanwhile.
sub restore_signal_mask {
    my ($previous) = @_;
    POSIX::sigprocmask(POSIX::SIG_SETMASK(), $previous) if $previous;
    return;
}

# forward_signals_to_workers(%a): return an INT/TERM/HUP handler that passes the signal on to the
# forked workers, waits for them, then re-raises it. An orchestrator that dies without this releases
# its locks while its workers keep building and writing into staging, and the next run races
# processes it cannot see. run_bounded covers the build inside ONE worker; this covers the workers.
#   %a: pids (hashref keyed by live worker pid), reap (coderef that waits for them)
sub forward_signals_to_workers {
    my (%a) = @_;
    my $pids = $a{pids} or die "forward_signals_to_workers: missing 'pids'\n";
    my $reap = $a{reap} or die "forward_signals_to_workers: missing 'reap'\n";
    return sub {
        my ($sig) = @_;
        kill($sig, keys %{$pids});
        $reap->();
        # die by the same signal, so the caller's exit status says what happened
        $SIG{$sig} = 'DEFAULT';
        kill($sig, $$);
    };
}

# run_bounded(%a): run a shell command with a wall-clock budget. On expiry it prints a stall report
# and kills the whole process group, so a build that deadlocks fails LOUDLY instead of hanging a
# pipeline forever -- an unbounded hang reads as "still running", never as a defect.
# The command runs in its own process group: a build spawns schroot, mock, qemu and make, and only a
# group signal reaches all of them. Signalling the group also means no child survives holding the
# caller's stdout open, which would turn the timeout back into a hang one level up.
#   %a: cmd (required), timeout (seconds; <=0 runs without a deadline), label, sample, out
# Returns { ec, timed_out, elapsed }. ec is 124 on a timeout, matching timeout(1).
sub run_bounded {
    my (%a) = @_;
    my $cmd     = defined $a{cmd} ? $a{cmd} : die "run_bounded: missing 'cmd'\n";
    my $timeout = $a{timeout} || 0;
    my $label   = defined $a{label} ? $a{label} : 'command';
    my $out     = $a{out} || \*STDERR;
    my $t0      = time;

    # Block the handled signals across the fork. A cancellation landing between fork() and the
    # handler below would kill this process under the inherited handler and leave the new process
    # group running. A blocked signal stays pending and is delivered once the handler is in place.
    # The child restores the mask before exec, or the build would inherit a blocked TERM.
    my $previous = block_handled_signals();

    my $pid = fork();
    unless (defined $pid) {
        restore_signal_mask($previous);
        die "run_bounded: fork failed: $!\n";
    }
    if ($pid == 0) {
        POSIX::setpgid(0, 0);
        restore_signal_mask($previous);
        exec('bash', '-c', $cmd) or POSIX::_exit(127);
    }
    # setpgid from BOTH sides: whichever runs first wins, so the group exists before the first signal
    # whatever the scheduler does.
    POSIX::setpgid($pid, $pid);

    # A signal to this process must reach the build too. Without this the orchestrator dies and
    # releases its locks while schroot, mock and qemu keep writing into staging, so the next run
    # races an orphan it cannot see.
    my $reap_group = sub {
        kill('TERM', -$pid);
        for (1 .. 40) {
            last if waitpid($pid, POSIX::WNOHANG()) == $pid;
            Time::HiRes::sleep(0.5);
        }
        kill('KILL', -$pid);
        waitpid($pid, 0);
    };
    my $forward = sub {
        my ($sig) = @_;
        $reap_group->();
        # die by the same signal, so the caller's exit status says what happened
        $SIG{$sig} = 'DEFAULT';
        kill($sig, $$);
    };
    local $SIG{INT}  = $forward;
    local $SIG{TERM} = $forward;
    local $SIG{HUP}  = $forward;
    restore_signal_mask($previous);

    # An unbounded run still forks: it is the process group, not the deadline, that lets a signal
    # to the orchestrator reach the build.
    my $deadline = $timeout > 0 ? $t0 + $timeout : undef;
    my $timed_out = 0;
    my $status;
    while (1) {
        my $r = waitpid($pid, POSIX::WNOHANG());
        if ($r == $pid) { $status = $?; last; }
        if ($r == -1)   { $status = 0;  last; }
        if (defined $deadline and time >= $deadline) { $timed_out = 1; last; }
        Time::HiRes::sleep(0.5);
    }

    if ($timed_out) {
        my $el = time - $t0;
        print {$out} "\nFATAL: $label exceeded its ${timeout}s budget (ran ${el}s).\n";
        eval { stall_report($pid, sample => (defined $a{sample} ? $a{sample} : 20), out => $out); 1 }
          or print {$out} "stall report failed: $@";
        # Unconditional final reap: a child left unreaped keeps the group alive and the caller
        # blocks on output that never ends.
        $reap_group->();
        return { ec => 124, timed_out => 1, elapsed => time - $t0 };
    }

    my $ec = exit_status($status);
    # The leader can die without its descendants. A SIGKILL, or the OOM killer, takes the shell but
    # leaves schroot and qemu in its process group, still holding the chroot and writing into
    # staging after this call reports the build finished. They are not children of this process, so
    # there is nothing to wait for: signal the group and move on.
    kill('TERM', -$pid);
    Time::HiRes::sleep(0.2);
    kill('KILL', -$pid);
    return { ec => $ec, timed_out => 0, elapsed => time - $t0 };
}

sub display_quote {
    my ($value) = @_;
    return $value if $value =~ /^[A-Za-z0-9_.,+\/:=@~-]+$/;
    return shell_quote($value);
}

sub shell_quote {
    my ($value) = @_;
    $value = '' unless defined($value);
    $value =~ s/'/'"'"'/g;
    return "'$value'";
}

sub print_step {
    my ($message) = @_;
    print "\n== $message ==\n";
}

sub read_lines {
    my ($path) = @_;
    my $content = read_binary($path);
    return () if $content eq '';

    my @lines = split(/\n/, $content, -1);
    pop(@lines) if @lines && $lines[-1] eq '';
    s/\r\z// for @lines;
    return @lines;
}

sub read_first_line {
    my ($path) = @_;
    my @lines = read_lines($path);
    die "Empty file: $path\n" unless @lines;
    return $lines[0];
}

sub relative_files {
    my ($root) = @_;
    die "Invalid directory: $root\n" unless -d $root && !-l $root;

    my $absolute = File::Spec->rel2abs($root);
    my @files;
    find(
        {
            no_chdir => 1,
            wanted   => sub {
                my $path = $File::Find::name;
                return if $path eq $absolute;
                die "Symbolic links are not allowed: $path\n" if -l $path;
                return if -d $path;
                die "Non-regular entry: $path\n" unless -f $path;
                my $relative = File::Spec->abs2rel($path, $absolute);
                $relative =~ tr{\\}{/};
                push(@files, $relative);
            },
        },
        $absolute,
    );
    my @sorted = sort @files;
    return @sorted;
}

sub digest_file {
    my ($path, $algorithm) = @_;
    $algorithm //= 'sha256';

    my $digest = $algorithm eq 'sha256' ? Digest::SHA->new(256)
      : $algorithm eq 'md5'              ? Digest::MD5->new
      : die "Unsupported digest algorithm: $algorithm\n";
    open(my $fh, '<:raw', $path) or die "Cannot read $path: $!\n";
    my $value = $digest->addfile($fh)->hexdigest;
    close($fh) or die "Cannot close $path: $!\n";
    return $value;
}

sub digest_manifest {
    my ($root, $algorithm, @files) = @_;
    return join(
        '',
        map { digest_file("$root/$_", $algorithm) . "  $_\n" }
          sort @files,
    );
}

# True when a set of steps was attempted and none of them survived. Callers tolerate
# individual failures; losing every step means the builder itself did not work.
sub every_step_failed {
    my ($attempted, $failures) = @_;
    return 0 unless $attempted;
    return $failures >= $attempted ? 1 : 0;
}

sub hashes_equal {
    my ($left, $right) = @_;
    return 0 unless keys(%{$left}) == keys(%{$right});
    for my $name (keys %{$left}) {
        return 0 unless exists($right->{$name})
          && $left->{$name} eq $right->{$name};
    }
    return 1;
}

1;
