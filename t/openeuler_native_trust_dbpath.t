#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Spec ();
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use XCAT::NativeInputs qw(trust_dbpath);

my $scratch = tempdir('trust-dbpath-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $root    = File::Spec->catdir($scratch, 'local-root');
my $foreign = File::Spec->catdir($scratch, 'foreign');
mkdir $root    or die "mkdir $root: $!";
mkdir $foreign or die "mkdir $foreign: $!";

sub fresh_private_dir_under {
    my ($db, $under, $what) = @_;
    ok(defined $db && length $db, "$what: trust_dbpath answers") or return;
    like($db, qr/^\Q$under\E\//, "$what: the keyring goes under the local root");
    ok(-d $db && !-l $db, "$what: the keyring is a real directory, not a symlink");
    is((lstat $db)[2] & 07777, 0700, "$what: the keyring directory is private");
    opendir my $dh, $db or return fail("$what: cannot read $db");
    is_deeply([grep { !/^\.\.?\z/ } readdir $dh], [], "$what: the keyring directory starts empty");
}

{
    local $ENV{XCAT_DEP_TRUST_TMP} = $root;
    my $first = trust_dbpath();
    fresh_private_dir_under($first, $root, 'first call');

    # Another user takes over the path the first call answered.
    rmdir $first if -d $first && !-l $first;
    symlink $foreign, $first or die "symlink $first: $!";

    my $second = trust_dbpath();
    isnt($second, $first, 'a path held by someone else is not reused');
    fresh_private_dir_under($second, $root, 'second call');
}

{
    my $other = File::Spec->catdir($scratch, 'other-root');
    mkdir $other or die "mkdir $other: $!";
    local $ENV{XCAT_DEP_TRUST_TMP} = $other;
    fresh_private_dir_under(trust_dbpath(), $other, 'XCAT_DEP_TRUST_TMP override');
}

done_testing();
