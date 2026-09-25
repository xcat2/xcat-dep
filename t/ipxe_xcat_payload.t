#!/usr/bin/perl
# Behaviour test for ipxe-xcat/verify-payload.pl, the check between a built ipxe-xcat package and the
# release tree that the package must carry byte for byte.
#
# A manifest is written for a small fixture tree with the checker's own --generate mode. Each case
# damages a copy of the tree in one way and runs the check as a subprocess: the check must fail and
# name the path. A check that compared only names would pass every damage case below. The last block
# holds the committed payload.sha256 and SHA256SUMS to the committed release archives.
use strict;
use warnings;
use Test::More;
use Digest::SHA ();
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use IPC::Open3 qw(open3);

my $pkg_dir = "$RealBin/../ipxe-xcat";
my $checker = "$pkg_dir/verify-payload.pl";
plan skip_all => 'ipxe-xcat/verify-payload.pl not found' unless -f $checker;

my $tmp = tempdir(CLEANUP => 1);

# Runs the checker; returns its exit code and its merged stdout and stderr.
sub run_checker {
    my (@args) = @_;
    my $pid = open3(my $in, my $out, undef, $^X, $checker, @args);
    close($in);
    my $text = do { local $/; <$out> } // '';
    waitpid($pid, 0);
    return ($? >> 8, $text);
}

sub write_file {
    my ($path, $content) = @_;
    make_path(dirname($path));
    open(my $fh, '>:raw', $path) or die "write $path: $!";
    print {$fh} $content;
    close($fh) or die "close $path: $!";
}

sub make_tree {
    my ($root) = @_;
    write_file("$root/i386/undionly.kpxe", "undi\x00\x01");
    write_file("$root/x86_64-sb/snponly.efi", "MZ signed snponly");
    write_file("$root/x86_64-sb/shimx64.efi", "MZ signed shim");
    symlink('shimx64.efi', "$root/x86_64-sb/ipxe-shim.efi") or die "symlink: $!";
    symlink('x86_64-sb', "$root/sb") or die "symlink: $!";
    symlink('i386/undionly.kpxe', "$root/undionly.kpxe") or die "symlink: $!";
}

sub copy_tree {
    my ($name) = @_;
    my $copy = "$tmp/$name";
    system('cp', '-a', "$tmp/pristine", $copy) == 0 or die "cp -a to $copy failed";
    return $copy;
}

make_tree("$tmp/pristine");
my ($code, $manifest_text) = run_checker('--generate', "$tmp/pristine");
is($code, 0, '--generate succeeds on a tree of files, directories and symlinks');
my $manifest = "$tmp/payload.sha256";
write_file($manifest, $manifest_text);
my @entries = grep { !/^#/ } split(/\n/, $manifest_text);
is(scalar(@entries), 8, 'the manifest has one entry for each directory, file and symlink');
like($manifest_text, qr/^link\tx86_64-sb\tsb$/m, 'a symlink is recorded with its target, not followed');

($code, my $output) = run_checker("$tmp/pristine", $manifest);
is($code, 0, 'the unchanged tree passes') or diag($output);
like($output, qr/payload matches .*: 8 entries/, 'the check reports the number of entries');
($code, $output) = run_checker("$tmp/pristine/", $manifest);
is($code, 0, 'a trailing slash on the tree path does not change the result') or diag($output);

my @damage = (
    ['one changed byte',
     sub { write_file("$_[0]/i386/undionly.kpxe", "undi\x00\x02") },
     qr{^content changed: i386/undionly\.kpxe$}m],
    ['a missing file',
     sub { unlink("$_[0]/x86_64-sb/snponly.efi") or die $! },
     qr{^missing: x86_64-sb/snponly\.efi$}m],
    ['an extra file',
     sub { write_file("$_[0]/x86_64-sb/extra.efi", 'extra') },
     qr{^unexpected: x86_64-sb/extra\.efi$}m],
    ['an extra directory',
     sub { make_path("$_[0]/arm64") },
     qr{^unexpected: arm64$}m],
    ['a symlink with another target',
     sub { unlink("$_[0]/sb") or die $!; symlink('i386', "$_[0]/sb") or die $! },
     qr{^link target changed: sb \(expected x86_64-sb, found i386\)$}m],
    ['a symlink replaced by a copy of its target',
     sub { unlink("$_[0]/x86_64-sb/ipxe-shim.efi") or die $!;
           write_file("$_[0]/x86_64-sb/ipxe-shim.efi", "MZ signed shim") },
     qr{^type changed: x86_64-sb/ipxe-shim\.efi \(expected link, found file\)$}m],
);
my $n = 0;
for my $case (@damage) {
    my ($name, $apply, $message) = @{$case};
    my $copy = copy_tree('damaged-' . ++$n);
    $apply->($copy);
    ($code, $output) = run_checker($copy, $manifest);
    is($code, 1, "$name fails the check");
    like($output, $message, "$name is reported by path") or diag($output);
}

write_file("$tmp/malformed.sha256", "file\tnot-a-digest\ti386/undionly.kpxe\n");
($code) = run_checker("$tmp/pristine", "$tmp/malformed.sha256");
is($code, 2, 'a malformed manifest line is an error, not a mismatch');
write_file("$tmp/duplicate.sha256", "dir\t-\ti386\ndir\t-\ti386\n");
($code) = run_checker("$tmp/pristine", "$tmp/duplicate.sha256");
is($code, 2, 'a duplicate manifest path is an error');
($code) = run_checker("$tmp/pristine/sb", $manifest);
is($code, 2, 'a tree path that is a symlink is refused');

# The committed manifest and checksums must describe the committed archives.
my @releases = glob("$pkg_dir/ipxeboot-*.tar.gz");
is(scalar(@releases), 1, 'the package directory holds one release archive');
SKIP: {
    skip 'no release archive', 3 if @releases != 1;
    my $release = "$tmp/release";
    make_path($release);
    is(system('tar', '-xzf', $releases[0], '--strip-components=1', '-C', $release), 0,
        'the release archive unpacks');
    ($code, $output) = run_checker($release, "$pkg_dir/payload.sha256");
    is($code, 0, 'payload.sha256 matches the committed release archive') or diag($output);

    open(my $fh, '<', "$pkg_dir/SHA256SUMS") or die "read SHA256SUMS: $!";
    my %sums = map { /^([0-9a-f]{64})  (\S+)$/ ? ($2, $1) : () } <$fh>;
    close($fh);
    my %actual = map { ($_, Digest::SHA->new(256)->addfile("$pkg_dir/$_", 'b')->hexdigest) }
        grep { -f "$pkg_dir/$_" } keys %sums;
    is_deeply(\%actual, \%sums, 'SHA256SUMS matches both committed archives');
}

done_testing();
