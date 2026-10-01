#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use File::Basename qw(basename);
use File::Slurper qw(read_text);

my @cfg = sort glob("$RealBin/../mock-configs/openeuler-*.cfg");

cmp_ok(scalar @cfg, '>=', 2, 'mock-configs/ carries openEuler configurations')
    or die "no mock-configs/openeuler-*.cfg under $RealBin/.. -- this test reads nothing\n";

my %shipped = map { basename($_) => 1 } glob("$RealBin/../mock-configs/templates/*.tpl");
ok($shipped{'openeuler-lts-xcat.tpl'}, 'the xCAT openEuler template is shipped here');

for my $path (@cfg) {
    my $name = basename($path);
    my $text = read_text($path);

    my ($release) = $text =~ /openeuler_repository_release'\]\s*=\s*'([^']+)'/;
    ok(defined $release, "$name: declares openeuler_repository_release") or next;

    my @inc = $text =~ /include\('templates\/([^']+)'\)/g;
    cmp_ok(scalar @inc, '>=', 1, "$name: includes at least one template");

    my ($majmin) = $release =~ /\A(\d+\.\d+)/;
    ok(defined $majmin, "$name: its release starts with a major.minor ($release)") or next;

    for my $t (@inc) {
        next if $shipped{$t};          # shipped beside the cfg, so it always resolves
        is($t, "openeuler-$majmin.tpl",
           "$name: its mock-core-configs template is openeuler-$majmin.tpl, not '$t'");
    }
}

done_testing();
