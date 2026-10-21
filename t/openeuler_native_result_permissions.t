#!/usr/bin/perl
# A dep builder creates its own result directories before mock starts. ipxe-xcat/mockbuild.pl calls
# make_path on $work_dir/srpm and $work_dir/rpm and gives each one to mock as --resultdir, and it
# runs as root. The native openEuler overlay keeps chrootuid at the catalog's build_uid and
# chrootgid at the native build gid, so mock opens state.log, build.log and root.log in those
# directories as that uid. They are writable only if the step itself carries the native build gid
# and a group-writable umask. native_owner_command is where the step gets both.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/..";
use MockBuildUtils qw(native_owner_command NATIVE_BUILD_GID);

my $gid     = NATIVE_BUILD_GID;
my $overlay = '/work/native-1000.cfg';
my $cfg     = '/etc/mock/openeuler-24.03-ppc64le.cfg';
my $step    = "perl ipxe-xcat/mockbuild.pl --work-dir /tmp/ipxe-xcat --result-dir /results/ipxe-xcat";
my $cmd     = native_owner_command($overlay, $cfg, $step);

like($cmd, qr/\bsetpriv\b[^'"]*--regid\s+\Q$gid\E\b/,
    "the step runs under setpriv --regid $gid, so it creates its result directories in the native build group");
like($cmd, qr/\bsetpriv\b[^'"]*--clear-groups\b/,
    'setpriv --clear-groups drops the supplementary groups root started with');
like($cmd, qr/\bumask\s+0002\b/,
    'the step runs with umask 0002, so a directory it creates stays group writable');

my $umask   = index($cmd, 'umask 0002');
my $setpriv = index($cmd, 'setpriv');
my $builder = index($cmd, 'ipxe-xcat/mockbuild.pl');
ok($setpriv >= 0 && $setpriv < $umask,
    'setpriv comes before umask 0002, so the umask applies under the native build gid');
ok($umask >= 0 && $umask < $builder,
    'umask 0002 comes before the builder, so make_path in the builder inherits it');

like($cmd, qr/mount --bind \S*\Q$overlay\E\S*\s+\S*\Q$cfg\E/,
    'the wrapper binds the overlay it was given over the target config, so chrootuid stays as the catalog declared it');

done_testing();
