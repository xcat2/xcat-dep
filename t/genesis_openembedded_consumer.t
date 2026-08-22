use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(basename);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../genesis-openembedded/lib";
use lib "$FindBin::Bin/lib";
use XCAT::GenesisRelease qw(
  architectures
  deb_package_name
  rpm_package_name
);
use XCAT::GenesisReleaseTest qw(
  command_exists
  file_sha
  make_export
  read_file
  run_capture
  write_checksums
  write_file
  write_release_manifest
);

my $repo_root = abs_path("$FindBin::Bin/..");
my $packager = "$repo_root/genesis-openembedded/package";
my $rpm_consumer = "$repo_root/mockbuild-all.pl";
my $deb_consumer = "$repo_root/build-apt-repo.sh";
my $revision = 'b' x 40;
my $version = '2.19.0';
my $release = 'snap202608210726';
my $epoch = 1787293573;
my $tmp = tempdir(CLEANUP => 1);

SKIP: {
    skip 'RPM repository tools require a root Linux builder', 10
      unless $^O eq 'linux'
      && $> == 0
      && command_exists('rpmbuild')
      && command_exists('rpm')
      && command_exists('createrepo_c');
    test_rpm_consumer();
    test_partial_rpm_release();
}

SKIP: {
    skip 'APT repository tools are not installed', 10
      unless $^O eq 'linux'
      && command_exists('bash')
      && command_exists('dpkg-deb')
      && command_exists('apt-ftparchive')
      && command_exists('gpg');
    test_deb_consumer();
    test_partial_deb_release();
}

done_testing();

sub test_rpm_consumer {
    my $release_root = make_package_release("$tmp/rpm", 'rpm');
    my $package = "xCAT-genesis-base-x86_64-$version-$release.noarch.rpm";
    my $source_package = "xCAT-genesis-base-x86_64-$version-$release.src.rpm";
    my $output = "$tmp/rpm output";
    my $target = 'test+epel-10-' . capture('uname', '-m');
    my $run = "$target-consumer";
    my $run_repo = "$output/mockbuild-all/$run/repo/" . capture('uname', '-m');
    my $source_repo = "$output/mockbuild-all/$run/repo-src";
    my $deploy_repo = "$output/xcat-dep/rh10/" . capture('uname', '-m');
    make_path($run_repo, $source_repo, $deploy_repo);
    write_file("$run_repo/xCAT-genesis-base-stale.noarch.rpm", 'stale');
    write_file("$source_repo/xCAT-genesis-base-stale.src.rpm", 'stale');
    write_file("$deploy_repo/xCAT-genesis-base-stale.noarch.rpm", 'stale');

    my $dependencies = "$tmp/rpm-dependencies";
    make_path($dependencies);
    for my $name (qw(
      ipmitool-xcat syslinux-xcat grub2-xcat xnba-undi
      perl-IO-Stty perl-HTTP-Async perl-Net-HTTPS-NB
    )) {
        copy("$release_root/rpm/$package", "$dependencies/$name-1.noarch.rpm")
          or die $!;
    }

    my $stub = "$tmp/perl-stub/Parallel/ForkManager.pm";
    make_path("$tmp/perl-stub/Parallel");
    write_file(
        $stub,
        "package Parallel::ForkManager;\n"
          . "sub new { bless {}, shift }\n"
          . "sub run_on_finish { \$_[0]->{callback} = \$_[1] }\n"
          . "sub start { 0 }\n"
          . "sub finish { my (\$self, \$exit) = \@_; "
          . "\$self->{callback}->(\$\$, \$exit, undef, 0, 0) if \$self->{callback}; 0 }\n"
          . "sub wait_all_children { 0 }\n1;\n",
    );

    my @perl_lib = ("$tmp/perl-stub");
    push(@perl_lib, $ENV{PERL5LIB})
      if defined($ENV{PERL5LIB}) && $ENV{PERL5LIB} ne '';
    local $ENV{PERL5LIB} = join(':', @perl_lib);
    my $log = "$tmp/rpm-consumer.log";
    my $status = run_capture(
        $log,
        $^X, $rpm_consumer,
        '--repo-root', $repo_root,
        '--output', $output,
        '--target', $target,
        '--run-id', 'consumer',
        '--build-timestamp', $epoch,
        '--skip-build', '--skip-xcat', '--skip-xcat-dep', '--skip-perl',
        '--skip-createrepo', '--skip-tarball',
        '--genesis-release', $release_root,
        '--collect-dir', $dependencies,
    );

    is($status, 0, 'RPM repository accepts a verified Genesis release');
    is(file_sha("$deploy_repo/$package"), file_sha("$release_root/rpm/$package"),
        'deployed RPM matches the release');
    ok(!-e "$run_repo/xCAT-genesis-base-stale.noarch.rpm",
        'stale run RPM is removed');
    ok(!-e "$source_repo/xCAT-genesis-base-stale.src.rpm",
        'stale source RPM is removed');
    ok(!-e "$deploy_repo/xCAT-genesis-base-stale.noarch.rpm",
        'stale deployed RPM is removed');
    is(file_sha("$source_repo/$source_package"),
        file_sha("$release_root/srpm/$source_package"),
        'source RPM matches the release');
    ok(-f "$deploy_repo/repodata/repomd.xml", 'RPM repository metadata is generated');
    like(read_file("$output/mockbuild-all/$run/summary.txt"), qr/^copied_rpms=14$/m,
        'release RPM is counted with required dependencies');
}

sub test_deb_consumer {
    my $release_root = make_package_release("$tmp/deb", 'deb');
    my $package = "xcat-genesis-base-x86-64_${version}-${release}_all.deb";
    my $apt_root = "$tmp/apt";
    my $input = "$apt_root/ubuntu24.04";
    my $dummy = "$tmp/dummy-deb";
    make_path("$dummy/DEBIAN", $input, "$apt_root/pool/main/noble");
    write_file(
        "$dummy/DEBIAN/control",
        "Package: xcat-dep-test\nVersion: 1\nArchitecture: all\n"
          . "Maintainer: xCAT <xcat-user\@lists.sourceforge.net>\n"
          . "Description: repository test package\n",
    );
    die "Cannot build test DEB\n"
      if run_capture(
        "$tmp/dummy-deb.log", 'dpkg-deb', '--root-owner-group', '--build',
        $dummy, "$input/xcat-dep-test_1_all.deb",
      );
    write_file("$apt_root/pool/main/noble/xcat-genesis-base-stale.deb", 'stale');

    local $ENV{SOURCE_DATE_EPOCH} = $epoch;
    my $log = "$tmp/deb-consumer.log";
    my $status = run_capture(
        $log,
        'bash', $deb_consumer,
        '--repo-root', $repo_root,
        '--apt-dir', $apt_root,
        '--skip-sign',
        '--genesis-release', $release_root,
        'ubuntu24.04',
    );
    my $pool_package = "$apt_root/pool/main/noble/$package";
    my $amd64 = "$apt_root/dists/noble/main/binary-amd64/Packages";
    my $ppc64el = "$apt_root/dists/noble/main/binary-ppc64el/Packages";

    is($status, 0, 'APT repository accepts a verified Genesis release');
    is(file_sha($pool_package), file_sha("$release_root/deb/$package"),
        'pooled DEB matches the release');
    ok(!-e "$apt_root/pool/main/noble/xcat-genesis-base-stale.deb",
        'stale pooled DEB is removed');
    like(read_file($amd64), qr/^Package: xcat-genesis-base-x86-64$/m,
        'all-architecture DEB is indexed for amd64');
    like(read_file($ppc64el), qr/^Package: xcat-genesis-base-x86-64$/m,
        'all-architecture DEB is indexed for ppc64el');
    ok(-f "$apt_root/dists/noble/Release", 'APT Release metadata is generated');

    my $collision = "$tmp/apt-collision";
    make_path("$collision/ubuntu24.04");
    write_file("$collision/ubuntu24.04/$package", 'different');
    my $collision_log = "$tmp/deb-collision.log";
    my $collision_status = run_capture(
        $collision_log,
        'bash', $deb_consumer,
        '--repo-root', $repo_root,
        '--apt-dir', $collision,
        '--skip-sign',
        '--genesis-release', $release_root,
        'ubuntu24.04',
    );
    isnt($collision_status, 0, 'APT repository rejects a package collision');
    like(read_file($collision_log), qr/Package collision with different content/,
        'collision failure identifies the package');
}

sub test_partial_rpm_release {
    my $release_root = make_package_release("$tmp/rpm-partial", 'rpm', 'x86_64');
    my $output = "$tmp/partial-output";
    my $target = 'test+epel-10-' . capture('uname', '-m');
    my $deployed = "$output/xcat-dep/rh10/" . capture('uname', '-m');
    my $existing = "$deployed/xCAT-genesis-base-existing.noarch.rpm";
    make_path($deployed);
    write_file($existing, 'existing release');

    my $log = "$tmp/rpm-partial.log";
    my $status = run_capture(
        $log,
        $^X, $rpm_consumer,
        '--repo-root', $repo_root,
        '--output', $output,
        '--target', $target,
        '--run-id', 'partial',
        '--build-timestamp', $epoch,
        '--skip-build', '--skip-xcat', '--skip-xcat-dep', '--skip-perl',
        '--skip-createrepo', '--skip-tarball',
        '--genesis-release', $release_root,
    );

    isnt($status, 0, 'RPM repository rejects a partial Genesis release');
    ok(-f $existing, 'partial release does not remove the deployed package');
}

sub test_partial_deb_release {
    my $release_root = make_package_release("$tmp/deb-partial", 'deb', 'x86_64');
    my $apt_root = "$tmp/partial-apt";
    my $pool = "$apt_root/pool/main/noble";
    my $existing = "$pool/xcat-genesis-base-existing.deb";
    make_path($pool);
    write_file($existing, 'existing release');

    my $log = "$tmp/deb-partial.log";
    my $status = run_capture(
        $log,
        'bash', $deb_consumer,
        '--repo-root', $repo_root,
        '--apt-dir', $apt_root,
        '--skip-sign',
        '--genesis-release', $release_root,
        'ubuntu24.04',
    );

    isnt($status, 0, 'APT repository rejects a partial Genesis release');
    ok(-f $existing, 'partial DEB release does not remove the deployed package');
}

sub make_package_release {
    my ($root, $format, @requested_architectures) = @_;
    @requested_architectures = architectures() unless @requested_architectures;
    my $release_root = "$root/release";
    make_path($release_root);
    for my $architecture (@requested_architectures) {
        my $export = make_export("$root/exports/$architecture", $architecture);
        my $packages = "$root/packages/$architecture";
        die "Cannot package test release for $architecture\n"
          if run_capture(
            "$root/package-$architecture.log",
            $packager,
            '--architecture', $architecture,
            '--export-dir', $export,
            '--output-dir', $packages,
            '--version', $version,
            '--release', $release,
            '--revision', $revision,
            '--source-date-epoch', $epoch,
            '--format', $format,
          );
        if ($format eq 'rpm') {
            my $name = rpm_package_name($architecture);
            make_path("$release_root/rpm", "$release_root/srpm");
            copy(
                "$packages/rpm/$name-$version-$release.noarch.rpm",
                "$release_root/rpm/$name-$version-$release.noarch.rpm",
            ) or die $!;
            copy(
                "$packages/srpm/$name-$version-$release.src.rpm",
                "$release_root/srpm/$name-$version-$release.src.rpm",
            ) or die $!;
        } else {
            my $name = deb_package_name($architecture);
            make_path("$release_root/deb");
            copy(
                "$packages/deb/${name}_${version}-${release}_all.deb",
                "$release_root/deb/${name}_${version}-${release}_all.deb",
            ) or die $!;
        }
    }
    write_release_manifest(
        $release_root, $version, $release, $revision, $epoch,
        join(',', @requested_architectures), $format,
    );
    write_checksums($release_root);
    return $release_root;
}

sub capture {
    my (@command) = @_;
    open(my $fh, '-|', @command) or die $!;
    my $output = <$fh>;
    close($fh) or die $!;
    chomp($output);
    return $output;
}
