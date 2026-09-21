use strict;
use warnings;

use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use Test::More;

use lib "$RealBin/../lib", "$RealBin/lib";
use XCAT::BuildUtils qw(capture_command command_exists digest_file read_binary write_binary);
use XCAT::GenesisReleaseTest qw(run_capture);

plan skip_all => 'Linux RPM repository tools required'
    unless $^O eq 'linux' && !grep { !command_exists($_) } qw(git rpm rpmbuild createrepo_c unshare);

my $tmp = tempdir(CLEANUP => 1);
my @namespace = $> == 0 ? () : ('unshare', '--user', '--map-root-user');
plan skip_all => 'An unprivileged user namespace is required for the collector root check'
    if @namespace && run_capture("$tmp/namespace.log", @namespace, 'true') != 0;

my $collector = $ENV{XCAT_TEST_COLLECTOR} // abs_path("$RealBin/../mockbuild-all.pl");
my $arch = capture_command('uname', '-m');
my $epoch = 1788718796;
my $snapshot = ('a' x 40) . '-dirty-snapshot-' . ('b' x 64);
my $top = "$tmp/rpmbuild";
make_path("$top/SPECS");
write_binary("$top/SPECS/provenance-fixture.spec", <<'SPEC');
Name: provenance-fixture
Version: 1
Release: 1
Summary: Repository metadata fixture
License: MIT
BuildArch: noarch
%description
Repository metadata fixture.
%install
mkdir -p %{buildroot}/usr/share/provenance-fixture
%files
/usr/share/provenance-fixture
SPEC
is(run_capture("$tmp/rpm-build.log", 'rpmbuild', '--quiet', '-bb', '--define', "_topdir $top",
    "$top/SPECS/provenance-fixture.spec"), 0, 'build an isolated RPM fixture')
    or BAIL_OUT(read_binary("$tmp/rpm-build.log"));
my $fixture = "$top/RPMS/noarch/provenance-fixture-1-1.noarch.rpm";
my $fixture_hash = digest_file($fixture);

for my $case (qw(checkout export missing empty)) {
    my $root = "$tmp/$case source";
    make_path($root);
    write_binary("$root/packages-manifest.conf",
        "[openeuler-24.03sp3-$arch]\nprovenance-fixture=1\n"
          . "[alma+epel-10-$arch]\nprovenance-fixture=1\n");
    write_binary("$root/Gitepoch", "$epoch\n");
    my $expected = 'unknown';
    if ($case eq 'checkout') {
        is(run_capture("$tmp/git-init.log", 'git', '-C', $root, 'init', '--quiet'), 0,
            'initialize the real checkout fixture');
        is(run_capture("$tmp/git-add.log", 'git', '-C', $root, 'add', 'packages-manifest.conf', 'Gitepoch'), 0,
            'stage the checkout fixture');
        is(run_capture("$tmp/git-commit.log", 'git', '-C', $root,
            '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
            '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'Fixture'), 0,
            'record the checkout fixture revision');
        $expected = capture_command('git', '-C', $root, 'rev-parse', 'HEAD');
        write_binary("$root/Gitinfo", "$snapshot\n");
    } elsif ($case eq 'export') {
        write_binary("$root/Gitinfo", "$snapshot\r\n");
        $expected = $snapshot;
    } elsif ($case eq 'empty') {
        write_binary("$root/Gitinfo", " \t\r\n");
    }

    for my $target ("openeuler-24.03sp3-$arch", "alma+epel-10-$arch") {
        my $output = "$tmp/$case-$target-output";
        my $repo = "$tmp/$case-$target-repo";
        my $log = "$tmp/$case-$target.log";
        local $ENV{MOCKBUILD_ALL_MOUNTNS} = 1;
        my $status = run_capture($log, @namespace, $^X, $collector,
            '--repo-root', $root, '--target', $target, '--output', $output,
            '--repo-dep', $repo, '--run-id', 'provenance', '--build-timestamp', $epoch,
            '--skip-build', '--skip-genesis', '--skip-xcat-dep', '--skip-perl',
            '--skip-createrepo', '--skip-tarball', '--no-verify-repo',
            '--collect-dir', "$top/RPMS/noarch");
        is($status, 0, "$case $target full collector succeeds") or diag(read_binary($log));
        my $subdir = $target =~ /^openeuler/ ? "openeuler24.03sp3/$arch" : "rh10/$arch";
        my $metadata_path = "$repo/$subdir/buildinfo.txt";
        ok(-f $metadata_path, "$case $target writes repository buildinfo");
        next unless -f $metadata_path;
        my %metadata = map { split /=/, $_, 2 } split /\n/, read_binary($metadata_path);
        is($metadata{COMMIT_ID_LONG}, $expected, "$case $target preserves the complete source identity");
        is($metadata{COMMIT_ID}, substr($expected, 0, 7), "$case $target preserves the short identity contract");
        is($metadata{SOURCE_DATE_EPOCH}, "$epoch", "$case $target retains the explicit epoch");
        is($metadata{TARGET}, $subdir, "$case $target retains the target repository path");
        is(digest_file("$repo/$subdir/provenance-fixture-1-1.noarch.rpm"), $fixture_hash,
            "$case $target collection preserves the RPM bytes");
    }
}

done_testing();
