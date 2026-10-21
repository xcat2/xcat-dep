#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

use XCAT::GenesisRelease qw(oe_source_dir);

# xcat-core 2a7364476 renamed xCAT-genesis-builder to xCAT-genesis-base. A dep build
# serves a released core that still carries the old name and a master that carries the
# new one, so it must take either.
# oe_source_dir dies when it resolves nothing. Report that as a failed assertion rather
# than letting it abort the file: a die emits no TAP, so prove reports "no plan found" and
# names nothing, which reads as a harness problem instead of the defect it is.
sub resolved {
    my @args = @_;
    my $dir = eval { oe_source_dir(@args) };
    return defined($dir) ? $dir : "died: $@";
}

sub core_with {
    my (@paths) = @_;
    my $root = tempdir(CLEANUP => 1);
    foreach my $path (@paths) {
        my ($dir) = $path =~ m{^(.*)/[^/]+$};
        make_path("$root/$dir");
        open(my $fh, '>', "$root/$path") or die "cannot create $path: $!";
        close($fh);
    }
    return $root;
}

is(resolved(core_with(qw(xCAT-genesis-base/oe/build xCAT-genesis-base/oe/export))),
    'xCAT-genesis-base/oe', 'a renamed checkout resolves to the new directory');

is(resolved(core_with(qw(xCAT-genesis-builder/oe/build xCAT-genesis-builder/oe/export))),
    'xCAT-genesis-builder/oe', 'a checkout from before the rename still resolves');

is(resolved(core_with(qw(
        xCAT-genesis-base/oe/build xCAT-genesis-base/oe/export
        xCAT-genesis-builder/oe/build xCAT-genesis-builder/oe/export))),
    'xCAT-genesis-base/oe', 'a checkout carrying both prefers the new directory');

# Half a directory is not a directory: the build runs both scripts, so one without the
# other must fail here rather than at the second run_command.
is(resolved(core_with(qw(xCAT-genesis-base/oe/build xCAT-genesis-builder/oe/build
        xCAT-genesis-builder/oe/export))),
    'xCAT-genesis-builder/oe', 'a new directory missing export falls back to the complete one');

my $half = core_with(qw(xCAT-genesis-base/oe/build));
ok(!eval { oe_source_dir($half); 1 }, 'a checkout with no complete directory dies');
like($@, qr{xCAT-genesis-base/oe/export}, 'the error names what the new directory lacks');
like($@, qr{xCAT-genesis-builder/oe/build}, 'the error names the old directory too');

my $empty = core_with();
ok(!eval { oe_source_dir($empty); 1 }, 'a checkout with neither directory dies');
like($@, qr{no OpenEmbedded Genesis builder}, 'the error says what is missing');

# The caller asks for the two scripts it runs; a caller that needs one gets one.
is(resolved(core_with(qw(xCAT-genesis-base/oe/build)), 'build'),
    'xCAT-genesis-base/oe', 'a caller may require a subset');

done_testing();
