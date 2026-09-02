#!/usr/bin/perl
# The shared OpenEmbedded Genesis repository (xcat-dep/common) is published outside the per-target
# cells, so the per-target manifest sections never described it and nothing asserted it was COMPLETE
# once published. Its packages were only checked as they were copied, against the release checksums.
#
# This drives the real mockbuild-all.pl publish path and asserts on the repository it leaves behind:
# a complete release publishes and is gated against the manifest's [common] section, and a release
# missing one architecture is refused rather than published.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Copy qw(copy);
use lib "$RealBin/..";
use MockBuildUtils qw(read_manifest);

my $SCRIPT = "$RealBin/../mockbuild-all.pl";
my $RELEASE = '/opt/xcat-ci-shared/builds/genesis-openembedded-initial-20260825/release';
plan skip_all => 'mockbuild-all.pl not found'  unless -f $SCRIPT;
plan skip_all => 'no Genesis release fixture'  unless -d "$RELEASE/rpm";
# root, like every other test that drives mockbuild-all.pl: the script refuses to run otherwise,
# and the CI builder (XCAT_GENESIS_CI) is root.
plan skip_all => 'rpm tooling and a root Linux builder required'
    unless $^O eq 'linux'
    && $> == 0
    && !system('sh', '-c', 'command -v rpm >/dev/null 2>&1')
    && !system('sh', '-c', 'command -v createrepo_c >/dev/null 2>&1')
    && !system('sh', '-c', 'command -v rpmbuild >/dev/null 2>&1');

my $tmp = tempdir(CLEANUP => 1);
my $target = 'alma+epel-10-' . do { my $m = `uname -m`; chomp $m; $m };

# The shipped manifest must describe the shared repo, else nothing can gate it.
{
    my %m = read_manifest("$RealBin/../packages-manifest.conf");
    ok($m{common} && %{ $m{common} }, 'the shipped manifest has a [common] section');
    is(scalar(keys %{ $m{common} // {} }), 7,
        '... naming every architecture the release must carry');
}

# fixture_rpm: a minimal noarch rpm, built once, standing in for a compiled dep.
my $FIXTURE;
sub fixture_rpm {
    return $FIXTURE if $FIXTURE;
    my $top = "$tmp/rpmbuild";
    make_path("$top/SPECS");
    open my $fh, '>', "$top/SPECS/fixture.spec" or die $!;
    print $fh <<'SPEC';
Name:           ipmitool-xcat
Version:        1.8.18
Release:        4
Summary:        fixture
License:        EPL
BuildArch:      noarch
%description
fixture package standing in for a compiled dependency
%install
mkdir -p %{buildroot}/usr/share/ipmitool-xcat
%files
/usr/share/ipmitool-xcat
SPEC
    close $fh;
    system('rpmbuild', '--quiet', '-bb', '--define', "_topdir $top", "$top/SPECS/fixture.spec") == 0
        or die "cannot build the fixture rpm\n";
    ($FIXTURE) = glob("$top/RPMS/noarch/ipmitool-xcat-1.8.18-4.noarch.rpm");
    die "fixture rpm not produced\n" unless $FIXTURE && -f $FIXTURE;
    return $FIXTURE;
}

# run_publish($release_dir) -> ($exit, $output, $common_dir)
sub run_publish {
    my ($release, $tag) = @_;
    my $out = "$tmp/$tag";
    make_path("$out/root", "$out/collect");
    # Something to collect, so the run gets past the "built nothing" guard. It must NOT be an
    # OpenEmbedded package: collect_rpms drops those when --genesis-release is given (they come from
    # the release, not from the build), so collecting one would leave the run with nothing.
    copy(fixture_rpm(), "$out/collect/") or die $!;
    open my $fh, '>', "$out/root/packages-manifest.conf" or die $!;
    # the cell carries exactly the fixture dep, so the per-target gate runs for real too
    print $fh "[$target]\nipmitool-xcat=1.8.18\n";
    # the shared repo's own section, copied from the shipped manifest so the test uses the real one
    my %m = read_manifest("$RealBin/../packages-manifest.conf");
    print $fh "\n[common]\n";
    print $fh "$_=$m{common}{$_}\n" for sort keys %{ $m{common} // {} };
    close $fh;
    my $cmd = join(' ', map { my $x = $_; $x =~ s/'/'"'"'/g; "'$x'" }
        ($^X, $SCRIPT, '--repo-root', "$out/root", '--output', "$out/build",
         '--repo-dep', "$out/repo", '--target', $target, '--run-id', $tag,
         '--build-timestamp', '1787672536',
         '--skip-build', '--skip-genesis', '--skip-xcat-dep', '--skip-perl',
         '--skip-tarball',
         '--collect-dir', "$out/collect", '--genesis-release', $release)) . ' 2>&1';
    my $log = `$cmd`;
    return ($? >> 8, $log, "$out/repo/common");
}

# ---- a complete release publishes, and says it was gated -----------------------------------------
{
    my ($rc, $out, $common) = run_publish($RELEASE, 'full');
    is($rc, 0, 'a complete release publishes') or diag($out);
    is(scalar(grep { !/\.src\.rpm$/ } glob("$common/*.rpm")), 7,
        'the published shared repo carries every architecture');
    like($out, qr/\[verify-repo\] common complete/, 'the shared repo is gated against [common]');
}

# ---- an incomplete release is refused, and publishes nothing --------------------------------------
{
    my $partial = "$tmp/partial-release";
    make_path("$partial/rpm", "$partial/srpm");
    for my $f (glob("$RELEASE/rpm/*.rpm"), glob("$RELEASE/srpm/*.rpm")) {
        next if $f =~ /riscv64/;                        # drop one architecture
        my ($sub) = $f =~ m{/(rpm|srpm)/[^/]+$};
        copy($f, "$partial/$sub/") or die $!;
    }
    copy("$RELEASE/release.manifest", $partial) or die $!;
    # SHA256SUMS without the dropped arch, so the release itself still self-describes consistently
    open my $in, '<', "$RELEASE/SHA256SUMS" or die $!;
    open my $o, '>', "$partial/SHA256SUMS" or die $!;
    while (<$in>) { print {$o} $_ unless /riscv64/ }
    close $in; close $o;

    my ($rc, $out, $common) = run_publish($partial, 'partial');
    isnt($rc, 0, 'a release missing an architecture is refused');
    ok(!-d $common || !glob("$common/*.rpm"),
        '... and nothing is published into the shared repository');
}

done_testing();
