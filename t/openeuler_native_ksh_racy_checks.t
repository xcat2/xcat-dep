#!/usr/bin/perl
# The openEuler ppc64le repository publishes the ksh that the native build makes, so its %check
# suite stays on. Four timing checks in that suite race on a loaded ppc64le build host and fail the
# cell at random. The ksh spec patch turns only those four err_exit calls into no-ops in %prep.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use File::Slurper qw(read_text);
use XCAT::NativeInputs qw(load_inputs);

my $plan    = load_inputs("$RealBin/..", {ksh => 1});
my $patches = $plan->{nodes}{ksh}{patches} // [];
is(scalar(@$patches), 1, 'the ksh native input carries one spec patch');

my $text    = @$patches ? read_text($patches->[0]{absolute_path}) : '';
my @removed = grep { /^-(?!--)/ } split /\n/, $text;
my $added   = join "\n", map { substr($_, 1) } grep { /^\+(?!\+\+)/ } split /\n/, $text;

is_deeply(\@removed, [], 'the patch removes no spec line, so %check still runs bin/package test');
unlike($added, qr/nocheck|_without_check/, 'the patch does not turn %check off');
like($text, qr/^ %autosetup -p1$/m, 'the patch edits %prep, after the sources are unpacked');

for my $check ("parent does not wait for child to complete before handling signal",
               "parent completes early", "process has hung",
               "SIGCHLD trap queueing failed -- expected '") {
    like($added, qr/\Q$check\E/, "the patch neutralizes the racy check: $check");
}
my %files = map { $_ => 1 } $added =~ /\b(\w+\.sh)\b/g;
is_deeply([sort keys %files], [qw(sigchld.sh signal.sh subshell.sh)],
    'the patch touches only signal.sh, subshell.sh and sigchld.sh');

done_testing();
