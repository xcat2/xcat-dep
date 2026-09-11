#!/usr/bin/perl
# packages-manifest.conf decides which packages xcat-dep builds for a target. An EPEL-fed target
# lists a perl module only where neither the base OS nor EPEL provides it. A riscv64 target has no
# EPEL, so it has strictly fewer providers and needs at least the union of what the EPEL-fed
# targets need. perl-HTML-Form was listed for el8 alone, so `dnf install xCAT` on a riscv64
# management node found nothing providing perl(HTML::Form) and refused the whole transaction.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/..";

use MockBuildUtils qw(read_manifest);

my $shipped = "$RealBin/../packages-manifest.conf";
plan skip_all => 'packages-manifest.conf not found' unless -f $shipped;
plan tests => 3;

my %manifest = read_manifest($shipped);

# Target sections are named after a mock config. EPEL feeds the ones built with an +epel- config;
# riscv64 is cross-built from a plain Rocky config and has no EPEL at all.
my @epel_fed = grep { /\+epel-/ }         sort keys %manifest;
my @no_epel  = grep { /-riscv64(?:-|$)/ } sort keys %manifest;

cmp_ok(scalar(@epel_fed), '>=', 1, 'the manifest has an EPEL-fed target');
cmp_ok(scalar(@no_epel),  '>=', 1, 'the manifest has a target with no EPEL');

my %needed_by;
for my $target (@epel_fed) {
    push @{ $needed_by{$_} }, $target for grep { /^perl-/ } keys %{ $manifest{$target} };
}

my @missing;
for my $target (@no_epel) {
    for my $package (sort keys %needed_by) {
        next if exists $manifest{$target}{$package};
        push @missing, "[$target] $package (listed for @{ $needed_by{$package} })";
    }
}

is_deeply(\@missing, [],
    'a target with no EPEL lists every perl module the EPEL-fed targets list')
  or diag("not built where nothing else provides it:\n  " . join("\n  ", @missing));
