#!/usr/bin/env perl
# The Fedora perl source rpms BuildRequire perl-generators and perl-interpreter. openSUSE has
# neither: there `perl` provides the interpreter and rpm generates the perl dependencies itself,
# so `dnf builddep` stops before the build. Every one of the four perl packages fails that way in
# a Leap chroot.
#
# The answer is a build-only compat rpm that provides those names, in a local repository injected
# into the mock configuration for SUSE targets alone. The configuration text and the decision
# behind it are pure, so this writes no rpm and runs no mock.
use strict;
use warnings;

use FindBin qw($RealBin);
use Test::More;

use lib $RealBin, "$RealBin/..", "$RealBin/../lib";
use MockBuildUtils ();

my $needed = MockBuildUtils->can('perl_buildreq_compat_needed');
my $spec   = MockBuildUtils->can('perl_buildreq_compat_spec');
my $text   = MockBuildUtils->can('perl_mock_cfg_text');
ok($needed, 'MockBuildUtils decides which targets need the perl BuildRequires compat');
ok($spec,   'MockBuildUtils carries the compat spec');
ok($text,   'MockBuildUtils writes the perl mock configuration');

subtest 'only a SUSE target needs the compat' => sub {
    plan skip_all => 'MockBuildUtils has no perl_buildreq_compat_needed' unless $needed;
    ok($needed->($_), "$_ needs the compat") for qw(
        opensuse-leap-15.6-x86_64 opensuse-leap-42.3-x86_64 opensuse-leap-15.6-ppc64le
    );
    ok(!$needed->($_), "$_ does not need the compat") for qw(
        alma+epel-8-x86_64 alma+epel-10-x86_64 openeuler-24.03sp4-x86_64
        openeuler-24.03-ppc64le rocky-10-riscv64-xcat
    );
};

subtest 'the compat package provides the names and nothing else' => sub {
    plan skip_all => 'MockBuildUtils has no perl_buildreq_compat_spec' unless $spec;
    my $s = $spec->();
    like($s, qr/^BuildArch:\s+noarch$/m, 'the compat rpm is noarch');
    like($s, qr/^Provides:\s+perl-generators$/m, '... provides perl-generators');
    like($s, qr/^Provides:\s+perl-interpreter$/m, '... provides perl-interpreter');
    like($s, qr/^Provides:\s+perl-devel$/m, '... provides perl-devel');
    like($s, qr/^Requires:\s+perl$/m, '... and pulls the real perl');
    like($s, qr/^%files\n%changelog\n/m,
        '... and lists no file between %files and %changelog, so it installs nothing');
};

subtest 'the configuration carries the repository only for a SUSE target' => sub {
    plan skip_all => 'MockBuildUtils has no perl_mock_cfg_text' unless $text;
    my $suse = $text->('opensuse-leap-15.6-x86_64', '1700000000', '/work/compat/repo');
    like($suse, qr{^include\('/etc/mock/opensuse-leap-15\.6-x86_64\.cfg'\)$}m,
        'the SUSE configuration includes its base');
    like($suse, qr/SOURCE_DATE_EPOCH'\] = '1700000000'/,
        '... and keeps the deterministic epoch');
    like($suse, qr{\[xcat-buildreq-compat\]}, '... and adds the compat repository');
    like($suse, qr{baseurl=file:///work/compat/repo}, '... at the directory it was given');
    like($suse, qr/gpgcheck=0/, '... unsigned, because it is built locally for this build');

    my $el = $text->('alma+epel-10-x86_64', '1700000000', undef);
    like($el, qr{^include\('/etc/mock/alma\+epel-10-x86_64\.cfg'\)$}m,
        'the EL configuration includes its base');
    unlike($el, qr/xcat-buildreq-compat/, '... and adds no compat repository');

    # A SUSE target with no repository is a programming error, not a build without the compat.
    my $missed = eval { $text->('opensuse-leap-15.6-x86_64', '1700000000', undef); 1 };
    ok(!$missed, 'a SUSE target with no compat repository is refused');
    like($@, qr/compat repository/, '... and says what was missing');
};

done_testing();
