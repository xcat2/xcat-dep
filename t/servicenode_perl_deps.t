#!/usr/bin/env perl
use strict;
use warnings;

use FindBin qw($RealBin);
use Test::More;

use lib $RealBin, "$RealBin/..";
use MockBuildUtils qw(read_manifest);

# A service node reaches only the OS install tree copycds made -- BaseOS and AppStream -- plus the
# xcat-core and xcat-dep repositories. It never reaches CRB or EPEL. xCAT-server, which xCATsn
# requires, declares perl dependencies that EL keeps in CRB or in EPEL, so `dnf install xCATsn` on
# a service node does not resolve unless xcat-dep carries them.
#
# The set below was read on 2026-09-04 from the "nothing provides" lines of:
#   dnf --releasever=<el> --installroot=<empty> install xCATsn \
#       --repofrompath=baseos,<alma>/<el>/BaseOS/<arch>/os/ \
#       --repofrompath=appstream,<alma>/<el>/AppStream/<arch>/os/ \
#       --repofrompath=core,<xcat-core repo> --repofrompath=dep,<xcat-dep repo>
# x86_64 and ppc64le give the same answer on every release.
#
# perl-Net-DNS is left out although an EL10 service node needs it. xcat-dep carries Net-DNS 0.80,
# which has no KEY resource record, and xCAT builds one in ddns.pm. Shipping 0.80 to a service
# node replaces a working AppStream copy with a broken one, so the EL10 Net-DNS gap waits for the
# version bump.

my %SN_PERL_DEPS = (
    8  => [qw(perl-Crypt-CBC perl-Crypt-Rijndael perl-Crypt-SSLeay perl-Digest-SHA1
              perl-Expect perl-HTML-Form perl-IO-Tty perl-Net-Telnet)],
    9  => [qw(perl-Crypt-CBC perl-Crypt-Rijndael perl-Crypt-SSLeay
              perl-Expect perl-HTML-Form perl-IO-Tty perl-Net-Telnet)],
    10 => [qw(perl-Crypt-CBC perl-Crypt-Rijndael perl-Crypt-SSLeay perl-Digest-SHA1
              perl-Expect perl-HTML-Form perl-IO-Tty perl-Net-Telnet)],
);

my $builder = "$RealBin/../mockbuild-perl-packages.pl";
plan skip_all => 'mockbuild-perl-packages.pl not found' unless -f $builder;
plan skip_all => 'Parallel::ForkManager is not available' unless eval { require Parallel::ForkManager; 1 };

my %manifest = read_manifest("$RealBin/../packages-manifest.conf");
my @el_targets = sort grep { /-(\d+)-/ } keys %manifest;
cmp_ok(scalar(@el_targets), '>=', 7, 'the manifest carries the EL target sections');

my %needed;
for my $target (@el_targets) {
    my ($release) = $target =~ /-(\d+)-/;
    my $want = $SN_PERL_DEPS{$release};
    ok($want, "$target: the service node perl set for EL$release is recorded")
        or next;
    $needed{$_} = 1 for @$want;

    my @missing = grep { !defined $manifest{$target}{$_} } @$want;
    is_deeply(\@missing, [], "$target: carries every perl package a service node cannot reach")
        or diag("not listed in [$target]: @missing");
}

# Ask the builder itself, rather than read its package table. It dies with
# "Unknown package in --packages" for a name it cannot build, and --list-packages stops before
# any host requirement, so this needs no root and no mock.
for my $pkg (sort keys %needed) {
    my $listed = `perl -I "$RealBin/.." -I "$RealBin/../lib" "$builder" --list-packages --packages $pkg 2>/dev/null`;
    is($?, 0, "$pkg: mockbuild-perl-packages.pl can build it");
    like($listed, qr/^\Q$pkg\E$/m, "... and names it in the set a run would build");
}

done_testing;
