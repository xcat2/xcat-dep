#!/usr/bin/env perl
# A MOCK RUN THAT DIED WITHOUT A BUILD ERROR IS RETRIED. A BUILD THAT FAILED IS NOT.
#
# xcat-dep-build-el8-x86_64 #107 failed on perl-Digest-SHA1 alone, ten of eleven packages passing
# in the same run. Its build.log shows `make test` reporting `Result: PASS`, %doc ending `+ exit
# 0`, and then `Child return code was: 255` with no rpm error at all -- the Provides/Requires pass
# never ran, and the container systemd recorded as `Deactivated successfully`. The same srpm, with
# the same defines, alone on the same host, builds all four rpms and exits 0.
#
# run_mock retried exit 30 only, so one dead chroot failed the package, the cell, the family and
# the run. xcat-core's buildrpms.pl has carried sh_retry for this exact class since the
# systemd-nspawn ENOMEDIUM race -- the perl builder is the copy that never got it.
#
# The predicate has to keep a REAL build failure fast: mock exits 1 when rpmbuild failed, and
# three attempts at a broken spec is three times the wait for the same answer.
use strict;
use warnings;
use Test::More;
use FindBin;
use lib $FindBin::Bin . '/..', $FindBin::Bin . '/../lib';
use MockBuildUtils qw(mock_exit_is_transient);

# 30 is mock's package-manager failure: a stale mirror, a chroot init that could not resolve.
# run_mock already retried this one, and the behaviour is kept.
ok(mock_exit_is_transient(30), 'exit 30, the package manager failed, is transient');

# 255 is the chroot or its nspawn dying with no rpm error behind it, which is #107.
ok(mock_exit_is_transient(255), 'exit 255, the chroot died with no build error, is transient');

# THE ONE THAT MUST NOT BE RETRIED. mock exits 1 when rpmbuild itself failed: a missing source, a
# %files entry with no file, a compile error. Retrying buys the same failure three times.
ok(!mock_exit_is_transient(1), 'exit 1, the build itself failed, is NOT transient');

# A success is not a retry case, however the caller asks.
ok(!mock_exit_is_transient(0), 'exit 0 is not transient');

# An unknown code is not retried: the list is what has been seen and explained, and a new code
# wants a reader to look at it rather than cost three attempts silently.
ok(!mock_exit_is_transient(10), 'an unexplained exit code is not retried');
ok(!mock_exit_is_transient(undef), 'and neither is no code at all');

done_testing;
