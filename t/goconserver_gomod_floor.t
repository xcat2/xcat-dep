#!/usr/bin/env perl
# The go directive of the pinned goconserver module graph must not exceed the oldest Go any
# xcat-dep target provides.
#
# goconserver/mockbuild.pl compiles inside the chroot with BuildRequires: golang and
# GOTOOLCHAIN=local, so Go never downloads a newer toolchain: a directive above the chroot's Go
# stops the build before the compiler starts. Measured in a Leap 15.6 chroot on 2026-10-23:
#
#   go: go.mod requires go >= 1.25.12 (running go 1.25.8; GOTOOLCHAIN=local)
#
# 1.25.12 was the patch level of the toolchain that regenerated go.mod, not a requirement of the
# code. go.mod and mockbuild.pl are the artifacts, so this reads them and runs no Go.
use strict;
use warnings;

use FindBin qw($RealBin);
use File::Slurper qw(read_text);
use Test::More;

my $repo = "$RealBin/..";

# The oldest Go a target resolves BuildRequires: golang to. Leap 15.6 is the floor today; EL 10
# and openEuler are newer. Raise this only with the chroot that reports the new value.
my $FLOOR = '1.25.8';

sub as_tuple { return [ map { $_ + 0 } (split /\./, $_[0], 3), 0, 0 ]; }
sub cmp_ver {
    my ($a, $b) = map { as_tuple($_) } @_;
    return $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2];
}

is(cmp_ver('1.25.8',  '1.25.12'), -1, 'the comparison reads 1.25.8 as older than 1.25.12');
is(cmp_ver('1.25.0',  '1.25.8'),  -1, '... and 1.25.0 as older than 1.25.8');
is(cmp_ver('1.25.12', '1.25.12'),  0, '... and equal versions as equal');

my $gomod = read_text("$repo/goconserver/gomod/go.mod");
my ($directive) = $gomod =~ /^go\s+(\d+\.\d+(?:\.\d+)?)\s*$/m;
ok(defined $directive, 'goconserver/gomod/go.mod declares a go directive') or done_testing(), exit;

cmp_ok(cmp_ver($directive, $FLOOR), '<=', 0,
    "the go directive $directive is within the oldest target Go $FLOOR");

# The directive still has to be high enough for the pinned graph, so this is a window and not a
# race to the bottom.
cmp_ok(cmp_ver($directive, '1.25.0'), '>=', 0,
    "the go directive $directive is at or above the 1.25.0 the pinned graph needs");

# The floor binds only because the build refuses to fetch a newer toolchain. If this changes, the
# directive stops mattering and this test is measuring nothing.
my $mockbuild = read_text("$repo/goconserver/mockbuild.pl");
like($mockbuild, qr/GOTOOLCHAIN=local/,
    'the chroot build pins the chroot Go, which is what makes the directive binding');
like($mockbuild, qr/\$go_requires\s*=\s*'golang'/,
    '... and takes its Go from the target repositories');

done_testing();
