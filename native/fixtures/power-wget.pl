#!/usr/bin/env perl
use strict;
use warnings;
use File::Copy qw(copy);
use JSON::PP qw(decode_json encode_json);

open(my $input, '<', $ENV{NATIVE_DOWNLOADS}) or die $!;
my $downloads = decode_json(do { local $/; <$input> });
close($input) or die $!;
my ($output) = grep { $ARGV[$_] eq '-O' } 0 .. $#ARGV - 1;
die 'wget fixture requires -O' unless defined($output);
open(my $trace, '>>', $ENV{NATIVE_CALLS}) or die $!;
print {$trace} encode_json({wget => $ARGV[-1]}) . "\n" or die $!;
close($trace) or die $!;
copy($downloads->{$ARGV[-1]}, $ARGV[$output + 1]) or die $!;
