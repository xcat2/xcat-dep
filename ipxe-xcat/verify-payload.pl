#!/usr/bin/perl
# verify-payload.pl -- compare an unpacked ipxe-xcat tree with payload.sha256.
#
#   verify-payload.pl --generate <tree> > payload.sha256
#   verify-payload.pl <tree> <payload.sha256>
#
# Each manifest line is "<type>\t<value>\t<path>", sorted by path: "file" with the SHA-256 of the
# content, "link" with the symlink target, "dir" with "-". Paths are relative to <tree>, and
# symlinks are never followed. The check exits 0 when the tree matches the manifest entry for
# entry, 1 when it differs, and 2 on a usage or read error.
use strict;
use warnings;
use Digest::SHA ();
use File::Find ();
use Getopt::Long qw(GetOptions);

my $generate = 0;
GetOptions('generate' => \$generate) or usage();

if ($generate) {
    usage() if @ARGV != 1;
    my $tree = scan_tree($ARGV[0]);
    print "# ipxe-xcat payload manifest, written by verify-payload.pl --generate\n";
    for my $path (sort keys %{$tree}) {
        print join("\t", @{ $tree->{$path} }, $path), "\n";
    }
    exit 0;
}

usage() if @ARGV != 2;
my ($root, $manifest_file) = @ARGV;
my $expected = read_manifest($manifest_file);
my $found    = scan_tree($root);

my @problems;
for my $path (sort keys %{$expected}) {
    my ($type, $value) = @{ $expected->{$path} };
    if (!exists $found->{$path}) {
        push @problems, "missing: $path";
        next;
    }
    my ($found_type, $found_value) = @{ $found->{$path} };
    if ($found_type ne $type) {
        push @problems, "type changed: $path (expected $type, found $found_type)";
    } elsif ($type eq 'file' && $found_value ne $value) {
        push @problems, "content changed: $path";
    } elsif ($type eq 'link' && $found_value ne $value) {
        push @problems, "link target changed: $path (expected $value, found $found_value)";
    }
}
push @problems, map { "unexpected: $_" } grep { !exists $expected->{$_} } sort keys %{$found};

if (@problems) {
    print STDERR "$_\n" for @problems;
    print STDERR "payload does not match $manifest_file: " . scalar(@problems) . " difference(s)\n";
    exit 1;
}
print "payload matches $manifest_file: " . scalar(keys %{$expected}) . " entries\n";
exit 0;

sub usage {
    print STDERR "Usage: $0 --generate <tree>\n       $0 <tree> <payload.sha256>\n";
    exit 2;
}

sub fail {
    my ($message) = @_;
    print STDERR "$0: $message\n";
    exit 2;
}

sub scan_tree {
    my ($dir) = @_;
    $dir =~ s{/+\z}{} if $dir ne '/';
    fail("not a directory: $dir") if -l $dir || !-d $dir;
    my %entries;
    File::Find::find({
        no_chdir => 1,
        wanted   => sub {
            my $path = $File::Find::name;
            return if $path eq $dir;
            my $relative = substr($path, length($dir) + 1);
            lstat($path) or fail("cannot stat $path: $!");
            if (-l _) {
                my $target = readlink($path);
                fail("cannot read link $path: $!") if !defined $target;
                $entries{$relative} = ['link', $target];
            } elsif (-d _) {
                $entries{$relative} = ['dir', '-'];
            } elsif (-f _) {
                my $sha = Digest::SHA->new(256);
                eval { $sha->addfile($path, 'b'); 1 } or fail("cannot read $path: $@");
                $entries{$relative} = ['file', $sha->hexdigest];
            } else {
                $entries{$relative} = ['other', '-'];
            }
        },
    }, $dir);
    return \%entries;
}

sub read_manifest {
    my ($file) = @_;
    open(my $fh, '<', $file) or fail("cannot read $file: $!");
    my %entries;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /^\s*(?:#|$)/;
        my ($type, $value, $path) = split(/\t/, $line, 3);
        fail("$file line $.: malformed entry")
            if !defined $path || $path eq '' || $type !~ /^(?:file|link|dir)$/
            || ($type eq 'file' && $value !~ /^[0-9a-f]{64}$/);
        fail("$file line $.: duplicate path $path") if exists $entries{$path};
        $entries{$path} = [$type, $value];
    }
    close($fh);
    return \%entries;
}
