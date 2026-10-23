#!/usr/bin/env perl
# ipxe-xcat/mockbuild.pl checks that the built RPM carries the iPXE source archive and the
# licences, and compares each one with the committed file. It used to look for them under
# /usr/share/doc/ipxe-xcat and /usr/share/licenses/ipxe-xcat. Those directories are
# distribution policy: openSUSE installs documents under /usr/share/doc/packages, so the
# Leap 15.6 build reported
#
#   Missing from the RPM payload: .../usr/share/doc/ipxe-xcat/ipxe-2.0.0-source.tar.gz
#
# on a package that carried the file one directory deeper.
#
# packaged_path takes the directory from the package. The lists below are what "rpm -qpd" and
# "rpm -qpL" print for the same spec on each distribution.
use strict;
use warnings;

use FindBin qw($RealBin);
use lib "$RealBin/..";
use Test::More;
use MockBuildUtils qw(packaged_path);

my @el_documents  = ('/usr/share/doc/ipxe-xcat', '/usr/share/doc/ipxe-xcat/ipxe-2.0.0-source.tar.gz');
my @el_licences   = ('/usr/share/licenses/ipxe-xcat/ipxe/COPYING',
                     '/usr/share/licenses/ipxe-xcat/ipxe/COPYING.GPLv2',
                     '/usr/share/licenses/ipxe-xcat/shim/COPYRIGHT');
my @suse_documents = ('/usr/share/doc/packages/ipxe-xcat',
                      '/usr/share/doc/packages/ipxe-xcat/ipxe-2.0.0-source.tar.gz');
my @suse_licences  = ('/usr/share/doc/packages/ipxe-xcat/ipxe/COPYING',
                      '/usr/share/doc/packages/ipxe-xcat/ipxe/COPYING.GPLv2',
                      '/usr/share/doc/packages/ipxe-xcat/shim/COPYRIGHT');

# A lookup that cannot resolve dies, so each one runs in an eval: a failure then names the
# assertion it broke instead of ending the file.
sub resolved {
    my ($paths, $want) = @_;
    my $path = eval { packaged_path($paths, 'ipxe-xcat', $want) };
    return defined($path) ? $path : "died: $@";
}

is(resolved(\@el_documents, 'ipxe-2.0.0-source.tar.gz'),
    '/usr/share/doc/ipxe-xcat/ipxe-2.0.0-source.tar.gz',
    'the EL document path is unchanged');
is(resolved(\@suse_documents, 'ipxe-2.0.0-source.tar.gz'),
    '/usr/share/doc/packages/ipxe-xcat/ipxe-2.0.0-source.tar.gz',
    'the openSUSE document path is found one directory deeper');
is(resolved(\@el_licences, 'ipxe/COPYING'),
    '/usr/share/licenses/ipxe-xcat/ipxe/COPYING',
    'a licence below its own subdirectory is found on EL');
is(resolved(\@suse_licences, 'shim/COPYRIGHT'),
    '/usr/share/doc/packages/ipxe-xcat/shim/COPYRIGHT',
    'a licence below its own subdirectory is found on openSUSE');

# The directory the package owns still has to be the package's own, or the check would accept a
# file another package installed under the same name.
my $foreign = eval {
    packaged_path(['/usr/share/doc/packages/ipxe/ipxe-2.0.0-source.tar.gz'],
        'ipxe-xcat', 'ipxe-2.0.0-source.tar.gz');
};
is($foreign, undef, 'a file under another package name is not accepted');
like($@, qr/no packaged path ends in ipxe-xcat/, 'the refusal names what was looked for');

# A package that ships the file nowhere must fail, not resolve to something else: that absence is
# the hole the check exists to catch.
eval { packaged_path([@el_licences], 'ipxe-xcat', 'ipxe-2.0.0-source.tar.gz') };
like($@, qr/no packaged path ends in ipxe-xcat\/ipxe-2\.0\.0-source\.tar\.gz \(searched 3\)/,
    'a missing document fails and reports how many paths were searched');

# Two matches mean the caller cannot tell which file it compared.
eval {
    packaged_path(['/usr/share/doc/ipxe-xcat/ipxe/COPYING',
                   '/usr/share/licenses/ipxe-xcat/ipxe/COPYING'], 'ipxe-xcat', 'ipxe/COPYING');
};
like($@, qr/matches 2 packaged paths/, 'an ambiguous match is refused');

done_testing();
