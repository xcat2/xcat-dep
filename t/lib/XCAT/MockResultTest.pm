package XCAT::MockResultTest;

use strict;
use warnings;

use Exporter qw(import);
use POSIX ();

our @EXPORT_OK = qw(writable_as);

# writable_as($uid, $dir): true when a process running as $uid can create a log in $dir. The child
# exits 2 rather than reporting a write it made as root, so a failed setuid cannot read as a pass.
# Flush the caller's output before the fork. The child ends with _exit and flushes nothing.
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

1;
