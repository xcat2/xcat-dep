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

our @EXPORT_OK = qw(
  capture_command
  command_exists
  digest_file
  digest_manifest
  display_quote
  hashes_equal
  print_step
  read_binary
  read_first_line
  read_lines
  relative_files
  require_command
  run_command
  shell_quote
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
