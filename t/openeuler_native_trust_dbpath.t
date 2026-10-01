#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Spec ();
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use XCAT::NativeInputs qw(trust_dbpath);

my $root = File::Spec->catdir(File::Spec->rootdir, 'local-scratch');
local $ENV{XCAT_DEP_TRUST_TMP} = $root;

my $staging = File::Spec->catdir(File::Spec->rootdir, qw(opt xcat-ci-shared builds oe262 2 native-inputs));
my $db = trust_dbpath($staging);

ok(defined $db && length $db, 'trust_dbpath answers for a staging directory') or done_testing, exit;

unlike($db, qr/\Q$staging\E/,
       'the keyring is not inside the staging tree, where the rpm lock answers errno 524');
like($db, qr/^\Q$root\E\b/, 'the keyring goes under the local root');

my $other = File::Spec->catdir(File::Spec->rootdir, qw(opt xcat-ci-shared builds oe262 3 native-inputs));
isnt(trust_dbpath($other), $db, 'two staging directories get two databases');

is(trust_dbpath($staging), $db, 'the same staging directory always gets the same database');

done_testing();
