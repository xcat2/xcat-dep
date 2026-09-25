package XCAT::NFSLock;

# A lock L on a shared, possibly re-exported, NFS tree. P0 is the process that
# owns L, and M0 is the machine P0 runs on.
#
# Safety: nothing bad ever happens. A violation shows in a finite run.
#   1. Single ownership. At any time, at most one live process holds L.
#   2. No cross-host borrowing. Only P0 removes L, or a process on M0 that
#      proves P0 dead. A process on another machine never removes L.
#
# Liveness: something good eventually happens.
#   3. No deadlock. Every acquire ends: it takes L, or it fails after its
#      timeout with the command that removes L.
#   4. Disjoint progress. Owners of disjoint resources do not wait on each
#      other: an acquire of a lock nobody holds succeeds without waiting.
#
# The caller keeps 4, with one lock per resource, and takes several locks in
# one fixed order.
#
# L is a directory that holds the owner record and the caller's metadata. It is
# built under a private name and renamed into place, and it is removed by a
# rename away, so both steps are atomic at the origin server. flock and fcntl
# locks are not reliable through an NFS re-export. rename replaces an empty
# directory, so an empty directory at L is not a lock.

use strict;
use warnings;
use Cwd qw(abs_path);
use Errno qw(EEXIST ENOENT ENOTEMPTY ESTALE);
use Exporter 'import';
use File::Basename qw(dirname basename);
use File::Glob qw(bsd_glob);
use File::Path qw(remove_tree);
use Sys::Hostname qw(hostname);
use Time::HiRes ();

our @EXPORT_OK = qw(owner_record parse_owner owner_is_dead process_start);

my $FORMAT = 'nfslock2';

#--------------------------------------------------------------------------------

=head3 acquire

    Descriptions:
        Take the lock at $path. Waits while another live process owns it, and
        removes it when the owner is provably dead on this machine.
    Arguments:
        $path: path of the lock directory
        %opt:
            timeout => seconds to wait for a live owner (default 0: try once)
            label   => word for messages (default "lock")
            meta    => hash ref of file name => content, written into the lock
                       before it appears
    Returns:
        A lock object. Dies when the wait ends, naming the owner and the mv
        command that moves the lock away. The next acquire deletes a lock moved
        to <path>.dead.*.

=cut

#--------------------------------------------------------------------------------
sub acquire {
    my ($class, $path, %opt) = @_;
    my $timeout = $opt{timeout} // 0;
    my $label   = $opt{label}   // 'lock';
    my $meta    = $opt{meta}    // {};
    for my $name (keys %$meta) {
        die "Invalid metadata name '$name' for $label\n"
          if $name eq 'owner' || $name !~ /\A[A-Za-z0-9_][A-Za-z0-9_.-]*\z/;
    }
    # The last component names the lock itself. basename would turn '' into './' and drop a
    # trailing slash, so the raw path is checked.
    my ($name) = ($path // '') =~ m{(?:\A|/)([^/]+)\z};
    die "Invalid $label path '" . ($path // '') . "'\n"
      if !defined($name) || $name eq '.' || $name eq '..';
    my $abs  = _absolute($path);
    my $self = bless { path => $abs, label => $label, pid => $$ }, $class;
    $self->{record} = owner_record();
    my $deadline = Time::HiRes::time() + $timeout;
    my $owner;

    _sweep($abs);
    while (1) {
        return $self if _create($abs, $self->{record}, $meta);
        my $error = $!;
        die "Cannot create $label $abs: $error\n"
          unless grep { $error == $_ } (EEXIST, ENOTEMPTY, ENOENT, ESTALE);

        my $current = _read_owner($abs);
        $owner = $current if defined($current);
        next if owner_is_dead(parse_owner($current), _here()) && _break($abs);
        last if Time::HiRes::time() >= $deadline;
        # Randomise the wait. Two waiters that back off by the same amount keep colliding.
        Time::HiRes::sleep(0.05 + rand(0.25));
    }

    my $who = _describe(parse_owner($owner));
    die "Trying to unlock $abs failed after ${timeout}s; $label owned by $who.\n"
      . "If you are sure it is safe, move the lock away: mv $abs $abs.dead.manual\n";
}

#--------------------------------------------------------------------------------

=head3 release

    Descriptions:
        Remove the lock if this process owns it. A forked child of the owner does
        nothing, and a lock that no longer carries this owner's record is left
        alone.
    Arguments:
        none
    Returns:
        1 when the lock was removed, 0 otherwise.

=cut

#--------------------------------------------------------------------------------
sub release {
    my ($self) = @_;
    return 0 if $self->{released} || $$ != $self->{pid};
    my $current = _read_owner($self->{path});
    return 0 unless defined($current) && $current eq $self->{record};
    $self->{released} = 1;
    return _remove($self->{path});
}

sub path { return $_[0]{path} }

#--------------------------------------------------------------------------------

=head3 owner_record

    Descriptions:
        The content of the owner file: the machine, its boot, the pid and the
        start time of the process, a random token, and, for messages only, the
        host name and the creation time. The token tells two acquisitions of one
        process apart, so a record names one acquisition.
    Arguments:
        none
    Returns:
        The record string.

=cut

#--------------------------------------------------------------------------------
sub owner_record {
    my %here = %{ _here() };
    return join('', map { "$_\n" } $FORMAT,
        "machine=$here{machine}", "boot=$here{boot}", "pid=$$",
        'start=' . (process_start($$) // 0),
        sprintf('token=%08x%08x', int(rand(2**32)), int(rand(2**32))),
        'host=' . (hostname() || 'unknown'), 'created=' . time());
}

#--------------------------------------------------------------------------------

=head3 parse_owner

    Descriptions:
        Split a record written by owner_record into its fields.
    Arguments:
        $record: the content of an owner file
    Returns:
        A hash ref of the fields, or undef when $record is not such a record.

=cut

#--------------------------------------------------------------------------------
sub parse_owner {
    my ($record) = @_;
    return undef unless defined($record);
    my ($format, @lines) = split(/\n/, $record);
    return undef unless defined($format) && $format eq $FORMAT;
    my %field;
    for my $line (@lines) {
        my ($key, $value) = split(/=/, $line, 2);
        return undef unless defined($value);
        $field{$key} = $value;
    }
    for my $key (qw(machine boot pid start)) {
        return undef unless defined($field{$key}) && length($field{$key});
    }
    return undef unless $field{pid} =~ /\A[1-9][0-9]*\z/ && $field{start} =~ /\A[0-9]+\z/;
    return \%field;
}

#--------------------------------------------------------------------------------

=head3 owner_is_dead

    Descriptions:
        Decide from facts alone whether a recorded owner is dead. Only the owner's
        machine can know: any other machine answers "not proven". An unreadable
        record is never proven dead.
    Arguments:
        $owner: a hash ref from parse_owner, or undef
        $here: hash ref with machine, boot and start_of, a code ref that returns
               the start time of a pid on this machine, or undef when no such
               process exists
    Returns:
        1 when the owner is provably dead, 0 otherwise.

=cut

#--------------------------------------------------------------------------------
sub owner_is_dead {
    my ($owner, $here) = @_;
    return 0 unless defined($owner);
    return 0 unless $owner->{machine} eq $here->{machine};
    return 1 unless $owner->{boot} eq $here->{boot};
    my $start = $here->{start_of}->($owner->{pid});
    return 1 unless defined($start);
    return $start eq $owner->{start} ? 0 : 1;
}

#--------------------------------------------------------------------------------

=head3 process_start

    Descriptions:
        The start time of a process, field 22 of /proc/<pid>/stat, in clock ticks
        since boot. A reused pid has a later start time.
    Arguments:
        $pid: the process id
    Returns:
        The start time, or undef when no such process exists.

=cut

#--------------------------------------------------------------------------------
sub process_start {
    my ($pid) = @_;
    open(my $fh, '<', "/proc/$pid/stat") or return undef;
    my $stat = <$fh>;
    close($fh);
    return undef unless defined($stat);
    # The command name, field 2, may contain spaces and parentheses.
    $stat =~ s/\A.*\)\s+//s or return undef;
    my @field = split(/\s+/, $stat);
    return $field[19];
}

# Build the lock under a private name, then rename it into place: the owner
# record and the metadata appear with the lock. rename fails when the target is
# a directory that is not empty, so one creator wins.
sub _create {
    my ($path, $record, $meta) = @_;
    my $tmp = _private_name($path, 'tmp');
    mkdir($tmp) or return 0;
    my %files = (%{ $meta // {} }, owner => $record);
    for my $name (sort keys %files) {
        my $fh;
        unless (open($fh, '>', "$tmp/$name") && print({$fh} $files{$name}) && close($fh)) {
            my $error = $!;
            remove_tree($tmp);
            die "Cannot write $tmp/$name: $error\n";
        }
    }
    return 1 if rename($tmp, $path);
    my $error = $!;
    remove_tree($tmp);
    # NFS can retransmit a rename that already succeeded, and the reply is then
    # an error. The owner file says whether the lock in place is this one.
    my $current = _read_owner($path);
    return 1 if defined($current) && $current eq $record;
    $! = $error;
    return 0;
}

# Two processes can find the same dead owner. Only the one holding the breaker
# removes the lock, and only after it proves the current owner dead again: only
# the owner or the breaker removes the lock, so that owner is the one removed.
sub _break {
    my ($path) = @_;
    my $breaker = "$path.break";
    my $mine    = owner_record();
    return 0 unless _create($breaker, $mine, {});
    my $removed = 0;
    if (owner_is_dead(parse_owner(_read_owner($path)), _here())) {
        $removed = _remove($path);
    }
    my $held = _read_owner($breaker);
    _remove($breaker) if defined($held) && $held eq $mine;
    return $removed;
}

# One rename takes the lock away. The detached tree is deleted afterwards: an
# NFS client keeps a file open by renaming it to .nfsXXXX, which only delays
# that delete.
sub _remove {
    my ($path) = @_;
    my $dead = _private_name($path, 'dead');
    return 0 unless rename($path, $dead);
    remove_tree($dead);
    return 1;
}

# Leftovers of earlier runs. A detached tree belongs to nobody. A private build
# belongs to its creator until that creator is proven dead.
sub _sweep {
    my ($path) = @_;
    for my $dead (bsd_glob("$path.dead.*")) {
        remove_tree($dead) if -d $dead && !-l $dead;
    }
    for my $tmp (bsd_glob("$path.tmp.*")) {
        next unless -d $tmp && !-l $tmp;
        remove_tree($tmp) if owner_is_dead(parse_owner(_read_owner($tmp)), _here());
    }
}

sub _private_name {
    my ($path, $kind) = @_;
    return sprintf('%s.%s.%d.%08x', $path, $kind, $$, int(rand(2**32)));
}

sub _read_owner {
    my ($path) = @_;
    open(my $fh, '<', "$path/owner") or return undef;
    local $/;
    my $record = <$fh>;
    close($fh);
    return $record;
}

sub _here {
    return {
        machine  => _first_line('/etc/machine-id') // (hostname() || 'unknown'),
        boot     => _first_line('/proc/sys/kernel/random/boot_id') // 'unknown',
        start_of => \&process_start,
    };
}

sub _first_line {
    my ($file) = @_;
    open(my $fh, '<', $file) or return undef;
    my $line = <$fh>;
    close($fh);
    return undef unless defined($line);
    chomp($line);
    return length($line) ? $line : undef;
}

sub _describe {
    my ($owner) = @_;
    return 'an unknown owner' unless defined($owner);
    return sprintf('pid %s on %s since %s', $owner->{pid}, $owner->{host} // $owner->{machine},
        scalar(localtime($owner->{created} // 0)));
}

# An absolute path in the message, without resolving the lock itself.
sub _absolute {
    my ($path) = @_;
    my $dir = abs_path(dirname($path)) // dirname($path);
    return "$dir/" . basename($path);
}

1;
