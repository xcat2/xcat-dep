#!/usr/bin/env perl
# mock_chroot_uid must give the uid mock itself builds as, so it runs mock's own loader.
use strict;
use warnings;

use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use Test::More;

use lib "$RealBin/..", "$RealBin/../t/lib";
use MockBuildUtils qw(mock_chroot_uid mock_result_dirs);
use XCAT::MockResultTest qw(writable_as);

plan skip_all => 'native Mock Python library required'
    if system('python3 -c "import mockbuild.config" >/dev/null 2>&1') != 0;

# Flush before the forks below, or each child repeats this file's TAP output on exit.
$| = 1;

# mock takes its build user from these. The sudo case below sets the one it needs.
delete @ENV{qw(SUDO_UID SUDO_GID SUDO_USER USERHELPER_UID PKEXEC_UID)};

my $tmp = tempdir(CLEANUP => 1);
# Under sudo, mock reads its configuration as the caller.
chmod 0755, $tmp or die "Cannot make $tmp readable: $!\n";
write_text("$tmp/base.cfg", <<'CFG');
config_opts['root'] = 'xcat-chrootuid-base'
config_opts['chrootuid'] = 1000
CFG
write_text("$tmp/override.cfg", <<"CFG");
include('$tmp/base.cfg')
config_opts['chrootuid'] = 1001
CFG
write_text("$tmp/wrapper.cfg", <<"CFG");
include('$tmp/base.cfg')
config_opts['environment']['SOURCE_DATE_EPOCH'] = '1757000000'
CFG
write_text("$tmp/plain.cfg", "config_opts['root'] = 'xcat-chrootuid-plain'\n");

is(mock_chroot_uid("$tmp/override.cfg"), 1001, 'a chrootuid set after an include overrides the include');
is(mock_chroot_uid("$tmp/wrapper.cfg"), 1000, 'a wrapper keeps the chrootuid of the configuration it includes');
is(mock_chroot_uid("$tmp/plain.cfg"), $<, 'a configuration with no chrootuid keeps the uid that runs mock');

SKIP: {
    my $nobody = getpwnam 'nobody';
    skip 'acting as the sudo caller requires root and a nobody user', 4
        if $> != 0 || !defined $nobody;

    # sudo mock with no chrootuid builds as SUDO_UID.
    local $ENV{SUDO_UID}  = $nobody;
    local $ENV{SUDO_GID}  = (getpwnam 'nobody')[3];
    local $ENV{SUDO_USER} = 'nobody';
    is(mock_chroot_uid("$tmp/plain.cfg"), $nobody,
        'under sudo, a configuration with no chrootuid builds as the sudo caller');

    my @dirs = mock_result_dirs("$tmp/work/perl-Net-DNS", "$tmp/plain.cfg");
    ok(writable_as($nobody, $_), "the sudo caller can create a log in $_") for @dirs;
}

done_testing();
