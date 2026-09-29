#!/usr/bin/env perl
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use File::Basename qw(basename);
use File::Copy qw(copy);
use File::Path qw(make_path);
use JSON::PP qw(encode_json);

sub option {
    my ($name) = @_;
    for my $i (0 .. $#ARGV - 1) { return $ARGV[$i + 1] if $ARGV[$i] eq $name; }
    return;
}
sub contents {
    open(my $file, '<', $_[0]) or die $!;
    binmode($file);
    return do { local $/; <$file> };
}
my %entry = (argv => \@ARGV);
my $config = option('-r');
$entry{config} = contents($config) if defined($config) && -f $config;
$entry{spec} = contents(option('--spec')) if defined(option('--spec'));
if (my $source = option('--rebuild')) {
    $entry{source} = $source;
    $entry{sha256} = sha256_hex(contents($source));
}
open(my $trace, '>>', $ENV{SCP_CALLS}) or die $!;
print {$trace} encode_json(\%entry) . "\n" or die $!;
close($trace) or die $!;
exit 0 if grep { /^--scrub=/ } @ARGV;
if (grep { $_ eq '--buildsrpm' } @ARGV) {
    my $dest = option('--resultdir');
    make_path($dest);
    copy($ENV{SCP_FIXTURE_SOURCE}, "$dest/python3-scp-0.14.5-1.src.rpm") or die $!;
    exit 0;
}
if ($ENV{SCP_MUTATE_SOURCE}) {
    open(my $source, '>>', $ENV{SCP_MUTATE_SOURCE}) or die $!;
    print {$source} 'changed after staging' or die $!;
    close($source) or die $!;
}
exit 43 if ($ENV{SCP_BUILD_STATUS} // '43') ne '0';
if (($ENV{SCP_EMPTY_OUTPUT} // '') ne '1') {
    my $dest = option('--resultdir');
    make_path($dest);
    for my $key (qw(SCP_FIXTURE_BINARY SCP_FIXTURE_SOURCE)) {
        copy($ENV{$key}, "$dest/" . basename($ENV{$key})) or die $!;
    }
}
