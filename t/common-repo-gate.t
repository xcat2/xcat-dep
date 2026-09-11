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
use File::Basename qw(basename);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Copy qw(copy);
use lib "$RealBin/..";
use lib "$RealBin/../lib";
use lib "$RealBin/lib";
use MockBuildUtils qw(read_manifest);
use XCAT::BuildUtils qw(command_exists);
use XCAT::GenesisRelease qw(architectures rpm_package_name);
use XCAT::GenesisReleaseTest qw(
  build_package_release
  copy_tree
  write_checksums
  write_release_manifest
);

my $SCRIPT = "$RealBin/../mockbuild-all.pl";
my $PACKAGER = "$RealBin/../genesis-openembedded/package";
plan skip_all => 'mockbuild-all.pl not found'  unless -f $SCRIPT;
my @missing_requirements;
push @missing_requirements, 'Linux' unless $^O eq 'linux';
push @missing_requirements, 'root' unless $> == 0;
for my $command (qw(createrepo_c gzip rpm rpmbuild tar)) {
    push @missing_requirements, $command unless command_exists($command);
}
if (command_exists('tar')) {
    my $tar_version = `tar --version 2>/dev/null`;
    push @missing_requirements, 'GNU tar' unless $tar_version =~ /GNU tar/;
}
if (@missing_requirements) {
    my $message = 'requires ' . join(', ', @missing_requirements);
    BAIL_OUT($message) if $ENV{XCAT_GENESIS_CI};
    plan skip_all => $message;
}

my $tmp = tempdir(CLEANUP => 1);
my $target = 'alma+epel-10-' . do { my $m = `uname -m`; chomp $m; $m };
my @architectures = architectures();
my $xcat_version = '2.19.0';
my $xcat_release = 'snap202609040000';
my $xcat_revision = 'c' x 40;
my $source_date_epoch = 1788476400;
my $RELEASE = build_package_release(
    root => "$tmp/release-fixture",
    format => 'rpm',
    architectures => \@architectures,
    packager => $PACKAGER,
    version => $xcat_version,
    release => $xcat_release,
    revision => $xcat_revision,
    epoch => $source_date_epoch,
);
my @version_1_architectures = grep { $_ ne 's390x' } @architectures;
my $VERSION_1_RELEASE = build_package_release(
    root => "$tmp/version-1-release-fixture",
    format => 'rpm',
    architectures => \@version_1_architectures,
    packager => $PACKAGER,
    version => $xcat_version,
    release => $xcat_release,
    revision => $xcat_revision,
    epoch => $source_date_epoch,
);
write_release_manifest(
    $VERSION_1_RELEASE, $xcat_version, $xcat_release, $xcat_revision,
    $source_date_epoch, join(',', @version_1_architectures), 'rpm', 1,
);
write_checksums($VERSION_1_RELEASE);

# The shipped manifest must describe the shared repo, else nothing can gate it.
{
    my %m = read_manifest("$RealBin/../packages-manifest.conf");
    ok($m{common} && %{ $m{common} }, 'the shipped manifest has a [common] section');
    my @expected = sort map { rpm_package_name($_) }
      qw(x86 x86_64 ppc64 ppc64le armv7hf aarch64 riscv64 s390x);
    my @missing = grep { !exists $m{common}{$_} } @expected;
    is_deeply(\@missing, [],
        'the shared RPM manifest lists every Genesis architecture');
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

sub run_publish {
    my ($release, $tag, $mutate_common, $skip_repo_verification) = @_;
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
    $mutate_common->($m{common}) if $mutate_common;
    print $fh "\n[common]\n";
    print $fh "$_=$m{common}{$_}\n" for sort keys %{ $m{common} // {} };
    close $fh;
    my @command =
        ($^X, $SCRIPT, '--repo-root', "$out/root", '--output', "$out/build",
         '--repo-dep', "$out/repo", '--target', $target, '--run-id', $tag,
         '--build-timestamp', '1787672536',
         '--skip-build', '--skip-genesis', '--skip-xcat-dep', '--skip-perl',
         '--skip-tarball',
         '--collect-dir', "$out/collect", '--genesis-release', $release);
    push @command, '--no-verify-repo' if $skip_repo_verification;
    my $cmd = join(' ', map { my $x = $_; $x =~ s/'/'"'"'/g; "'$x'" } @command)
      . ' 2>&1';
    my $log = `$cmd`;
    return ($? >> 8, $log, "$out/repo/common");
}

{
    my $package = rpm_package_name('s390x');
    my ($rc, $out, $common) = run_publish(
        $RELEASE,
        'unsatisfied-common',
        sub { $_[0]->{$package} = '>= 99.0.0' },
    );
    isnt($rc, 0, 'an unsatisfied shared-repository requirement is refused');
    like($out, qr/EVR \Q$package\E: repo has .* manifest requires >= 99\.0\.0/,
        'the shared-repository gate names the unsatisfied requirement');
    ok(!-d $common || !glob("$common/*.rpm"),
        'a failed shared-repository gate publishes nothing');
}

# ---- a complete release publishes, and says it was gated -----------------------------------------
{
    my ($rc, $out, $common) = run_publish($RELEASE, 'full');
    is($rc, 0, 'a complete release publishes') or diag($out);
    is(scalar(grep { !/\.src\.rpm$/ } glob("$common/*.rpm")), 8,
        'the published shared repo carries every architecture');
    like($out, qr/\[verify-repo\] common complete: 8 packages present/,
        'the shared repo is gated against [common]');
}

{
    my ($rc, $out, $common) = run_publish($VERSION_1_RELEASE, 'version-1');
    isnt($rc, 0, 'a version 1 release cannot replace the current repository');
    like($out, qr/Genesis release version 1 omits currently supported architectures: s390x/,
        'version 1 refusal identifies the missing architecture');
    ok(!-d $common || !glob("$common/*.rpm"),
        'a version 1 release publishes nothing');
}

{
    my ($rc, $out, $common) = run_publish(
        $RELEASE,
        'missing-non-genesis-package',
        sub { $_[0]->{'xCAT-release'} = '>= 2.0.0' },
    );
    isnt($rc, 0, 'every common manifest package is verified');
    like($out, qr/MISSING xCAT-release/,
        'the common gate identifies a missing non-Genesis package');
    ok(!-d $common || !glob("$common/*.rpm"),
        'a missing non-Genesis package prevents publication');
}

{
    my ($rc, $out, $common) = run_publish(
        $RELEASE,
        'missing-current-package',
        sub { delete $_[0]->{ rpm_package_name('s390x') } },
    );
    isnt($rc, 0, 'a current release does not hide an incomplete manifest');
    like($out, qr/\[common\] is missing supported packages: .*s390x/,
        'the manifest failure identifies the missing current package');
    ok(!-d $common || !glob("$common/*.rpm"),
        'an incomplete current manifest publishes nothing');
}

{
    my ($rc, $out, $common) = run_publish(
        $RELEASE,
        'missing-current-package-without-repo-verification',
        sub { delete $_[0]->{ rpm_package_name('s390x') } },
        1,
    );
    isnt($rc, 0, 'repository verification cannot disable the common manifest gate');
    like($out, qr/\[common\] is missing supported packages: .*s390x/,
        'the mandatory manifest gate identifies the missing package');
    ok(!-d $common || !glob("$common/*.rpm"),
        'the mandatory manifest gate publishes nothing');
}

{
    my ($rc, $out, $common) = run_publish(
        $RELEASE,
        'unknown-current-package',
        sub { $_[0]->{'xCAT-genesis-openembedded-unknown'} = '>= 2.18.0' },
    );
    isnt($rc, 0, 'an unknown shared manifest package is refused');
    like($out, qr/\[common\] has unsupported packages: xCAT-genesis-openembedded-unknown/,
        'the manifest failure identifies the unknown package');
    ok(!-d $common || !glob("$common/*.rpm"),
        'an unknown shared manifest package publishes nothing');
}

# ---- an incomplete release is refused, and publishes nothing --------------------------------------
{
    my $partial = "$tmp/partial-release";
    my $missing_architecture = 's390x';
    my $missing_package = rpm_package_name($missing_architecture);
    my @partial_architectures = grep { $_ ne $missing_architecture } @architectures;
    make_path("$partial/rpm", "$partial/srpm");
    for my $f (glob("$RELEASE/rpm/*.rpm"), glob("$RELEASE/srpm/*.rpm")) {
        next if basename($f) =~ /^\Q$missing_package-\E/;
        my ($sub) = $f =~ m{/(rpm|srpm)/[^/]+$};
        copy($f, "$partial/$sub/") or die $!;
    }
    write_release_manifest(
        $partial, $xcat_version, $xcat_release, $xcat_revision, $source_date_epoch,
        join(',', @partial_architectures), 'rpm',
    );
    write_checksums($partial);

    my ($rc, $out, $common) = run_publish($partial, 'partial');
    isnt($rc, 0, 'a release missing an architecture is refused');
    like($out, qr/omits currently supported architectures: \Q$missing_architecture\E/,
        'the completeness gate identifies the missing architecture');
    ok(!-d $common || !glob("$common/*.rpm"),
        '... and nothing is published into the shared repository');
}

{
    my $inconsistent = "$tmp/inconsistent-release";
    my $missing_package = rpm_package_name('s390x');
    copy_tree($RELEASE, $inconsistent);
    for my $directory (qw(rpm srpm)) {
        my @packages = glob("$inconsistent/$directory/$missing_package-*");
        unlink(@packages) == @packages or die "cannot remove package fixture\n";
    }
    write_checksums($inconsistent);

    my ($rc, $out, $common) = run_publish($inconsistent, 'inconsistent');
    isnt($rc, 0, 'a release inconsistent with its manifest is refused');
    like($out, qr/Genesis release is missing:/,
        'the release-layout gate reports the missing package');
    ok(!-d $common || !glob("$common/*.rpm"),
        'an inconsistent release publishes nothing');
}

done_testing();
