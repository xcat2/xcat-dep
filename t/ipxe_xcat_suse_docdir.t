#!/usr/bin/env perl
# ipxe-xcat installs the release source tarball under %{_pkgdocdir}. Fedora and EL rpm define that
# macro; openSUSE rpm does not, so on a Leap chroot the path reaches rpmbuild unexpanded and the
# build stops:
#
#   error: File must begin with "/": %{_pkgdocdir}
#   cp: cannot stat '%{_pkgdocdir}/ipxe-2.0.0-source.tar.gz': No such file or directory
#
# That is one of the two steps that failed the first real opensuse-leap-15.6-x86_64 dep build.
#
# This expands the spec with rpmspec, once with the macro undefined -- which is a Leap host -- and
# once with it defined, and asserts both produce absolute paths and produce the same ones. A grep
# for a %global line would pass on a definition rpm never reaches.
use strict;
use warnings;

use FindBin qw($RealBin);
use Test::More;

my $spec = "$RealBin/../ipxe-xcat/ipxe-xcat.spec";
plan skip_all => "ipxe-xcat.spec not found" unless -f $spec;
plan skip_all => 'rpmspec not installed' if system('command -v rpmspec >/dev/null 2>&1') != 0;

#-----------------------------------------------------------------------------------------------
=head3 doc_paths

Descriptions:
    Expand the spec with rpmspec and return the doc paths its %install and %files carry. Takes
    the macro state rather than assuming the host's, because the defect only appears where
    _pkgdocdir is undefined and every EL host defines it.
Arguments:
    $undefine - true to expand with _pkgdocdir undefined, as openSUSE rpm has it
Returns:
    A hash reference: 'rc' the rpmspec exit status, 'paths' the doc paths found.
=cut
#-----------------------------------------------------------------------------------------------
sub doc_paths {
    my ($undefine) = @_;
    my @cmd = ('rpmspec', ($undefine ? ('--undefine', '_pkgdocdir') : ()), '-P', $spec);
    open(my $fh, '-|', @cmd) or die "run rpmspec: $!";
    my (@paths, $line);
    while ($line = <$fh>) {
        push(@paths, $1) if $line =~ m{^%(?:dir|doc)\s+(\S+)};
        push(@paths, $1) if $line =~ m{^install .*\s(\S*doc\S*/ipxe-\S+source\.tar\.gz)\s*$};
    }
    close($fh);
    return { rc => $?, paths => \@paths };
}

my $leap = doc_paths(1);
my $el   = doc_paths(0);

# Control: rpmspec must have produced something, or every path assertion below is vacuous.
is($leap->{rc}, 0, 'control: rpmspec expands the spec with _pkgdocdir undefined');
cmp_ok(scalar(@{ $leap->{paths} }), '>=', 2,
    'control: the expansion carries the doc paths this test reads');

for my $path (@{ $leap->{paths} }) {
    like($path, qr{^/}, "with _pkgdocdir undefined the doc path is absolute: $path");
    unlike($path, qr/%\{?_pkgdocdir/,
        'the doc path does not carry an unexpanded _pkgdocdir, which rpmbuild refuses');
}

# The fix must not move the EL path. Both expansions name the same directory.
is_deeply($leap->{paths}, $el->{paths},
    'the doc paths are the same whether rpm defines _pkgdocdir or the spec does');

done_testing();
