#!/usr/bin/env perl
# mock_chroot_uid must give the uid mock itself builds as, so it runs mock's own loader.
use strict;
use warnings;

use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use Test::More;

use lib "$RealBin/..";
use MockBuildUtils qw(mock_chroot_uid);

plan skip_all => 'native Mock Python library required'
    if system('python3 -c "import mockbuild.config" >/dev/null 2>&1') != 0;

my $tmp = tempdir(CLEANUP => 1);
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

done_testing();
