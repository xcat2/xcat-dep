#!/usr/bin/perl
# Every architecture run of a dep build can publish the shared common/ tree. Recovery of an
# interrupted publication removes staging trees, so it runs only under the common lock, and never
# while another run holds that lock.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/..", "$RealBin/../lib";
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use MockBuildUtils qw(recover_common_repository);
use XCAT::NFSLock qw(owner_record parse_owner process_start);

my $me = parse_owner(owner_record());

# No process can have a pid above the kernel's pid_max (2**22 at most).
my $gone   = 2**22 + 7;
my $parent = getppid();

sub record {
    my (%f) = @_;
    my %r = (%$me, host => 'peer', created => 1, %f);
    return join('', map { "$_\n" } 'nfslock2',
        map { "$_=$r{$_}" } qw(machine boot pid start token host created));
}

# A repository left by an interrupted publication: common/ moved aside, a staging tree beside it.
sub interrupted {
    my ($holder) = @_;
    my $base = tempdir(CLEANUP => 1);
    make_path("$base/.common.previous.999", "$base/.common.staging");
    write_text("$base/.common.previous.999/marker", "previous repository\n");
    if (defined($holder)) {
        make_path("$base/.common-publish.lock");
        write_text("$base/.common-publish.lock/owner", $holder);
    }
    return $base;
}

{
    my $base = interrupted(undef);
    is(recover_common_repository($base), 1, 'recovery runs when nobody holds the common lock');
    is(read_text("$base/common/marker"), "previous repository\n", 'the interrupted common tree is restored');
    ok(!-e "$base/.common.staging", 'the abandoned staging tree is removed');
    ok(!-e "$base/.common-publish.lock", 'recovery releases the common lock');
}

for my $case (
    [ 'a live run on this host', record(pid => $parent, start => process_start($parent)) ],
    [ 'a run on another host',   record(machine => 'elsewhere', pid => $gone) ],
  )
{
    my ($name, $holder) = @$case;
    my $base = interrupted($holder);
    open(my $capture, '>', \my $printed) or die "Cannot capture output: $!";
    my $previous = select($capture);
    my $ran = recover_common_repository($base);
    select($previous);
    is($ran, 0, "recovery does not run while $name holds the common lock");
    like($printed, qr/^common recovery skipped: another run holds \Q$base\E\/\.common-publish\.lock$/m,
        "the skip names the lock $name holds");
    unlike($printed, qr/rm -rf/, "the skip does not tell the operator to remove the lock $name holds");
    ok(-d "$base/.common.staging", "the staging tree of $name is left in place");
    ok(!-e "$base/common", "the common tree stays where $name put it");
    is(read_text("$base/.common-publish.lock/owner"), $holder, "$name keeps the common lock");
}

{
    my $base = interrupted(record(pid => $gone));
    is(recover_common_repository($base), 1, 'recovery takes the common lock of a run that died on this host');
    ok(!-e "$base/.common.staging", 'the staging tree of the dead run is removed');
    ok(-d "$base/common", 'the common tree of the dead run is restored');
}

done_testing();
