#!/usr/bin/env perl
use strict;
use warnings;

use FindBin qw($RealBin);
use Test::More;

use lib $RealBin, "$RealBin/..";
use MockBuildUtils qw(read_manifest);

# EL10 riscv64 has no EPEL, so every perl package the builder exists to supply must be pinned in
# the riscv64 cell: an omission there is not filled in by any other repository. perl-HTML-Form
# was missing, and perl-xCAT hard-requires perl(HTML::Form), so `dnf install xCAT` could not
# resolve on riscv64 at all. The set comes from the builder itself, so a package added to it later
# fails here until the cell names it.

my $builder = "$RealBin/../mockbuild-perl-packages.pl";
plan skip_all => 'mockbuild-perl-packages.pl not found' unless -f $builder;
plan skip_all => 'Parallel::ForkManager is not available' unless eval { require Parallel::ForkManager; 1 };

my @built = grep { length } split /\n/, `perl -I "$RealBin/.." -I "$RealBin/../lib" "$builder" --epel-gap --list-packages 2>/dev/null`;
is( $?, 0, 'the builder lists the packages an --epel-gap run would build' );
cmp_ok( scalar(@built), '>=', 10, '... and the list is the real one, not an empty run' );

my %m = read_manifest("$RealBin/../packages-manifest.conf");
my $cell = $m{'rocky-10-riscv64-xcat'};
ok( $cell, 'the manifest has the riscv64 cell' );

my @unpinned = grep { !defined $cell->{$_} } @built;
is_deeply( \@unpinned, [], 'every package the builder supplies is pinned in the riscv64 cell' )
  or diag( "missing from [rocky-10-riscv64-xcat]: @unpinned" );

done_testing;
