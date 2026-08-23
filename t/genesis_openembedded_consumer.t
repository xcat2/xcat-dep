use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(basename);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";
use XCAT::BuildUtils qw(
  capture_command
  command_exists
  digest_file
  read_binary
  write_binary
);
use XCAT::GenesisRelease qw(
  architectures
  deb_package_name
  rpm_package_name
);
use XCAT::GenesisReleaseTest qw(
  make_export
  run_capture
  write_forkmanager_stub
  write_checksums
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

if ($ENV{XCAT_GENESIS_CI}) {
    BAIL_OUT('CI requires Linux root') unless $^O eq 'linux' && $> == 0;
    for my $command (qw(apt-ftparchive bash createrepo_c dpkg-deb gpg rpm rpmbuild)) {
        BAIL_OUT("CI requires $command") unless command_exists($command);
    }
}

SKIP: {
    skip 'RPM repository tools require a root Linux builder', 19
      unless $^O eq 'linux'
      && $> == 0
      && command_exists('rpmbuild')
      && command_exists('rpm')
      && command_exists('createrepo_c');
    test_rpm_consumer();
    test_legacy_rpm_consumer();
    test_partial_rpm_release();
}

SKIP: {
    skip 'APT repository tools are not installed', 17
      unless $^O eq 'linux'
      && command_exists('bash')
      && command_exists('dpkg-deb')
      && command_exists('apt-ftparchive')
      && command_exists('gpg');
    test_deb_consumer();
    test_legacy_deb_consumer();
    test_partial_deb_release();
}

done_testing();

sub test_rpm_consumer {
    my $release_root = make_package_release("$tmp/rpm", 'rpm');
    my $package = "xCAT-genesis-openembedded-x86_64-$version-$release.noarch.rpm";
    my $source_package = "xCAT-genesis-openembedded-x86_64-$version-$release.src.rpm";
    my $output = "$tmp/rpm output";
    my $target = 'test+epel-10-' . capture_command('uname', '-m');
    my $run = "$target-consumer";
    my $run_repo = "$output/mockbuild-all/$run/repo/" . capture_command('uname', '-m');
    my $source_repo = "$output/mockbuild-all/$run/repo-src";
    my $deploy_repo = "$output/xcat-dep/rh10/" . capture_command('uname', '-m');
    make_path($run_repo, $source_repo, $deploy_repo);
    write_binary("$run_repo/xCAT-genesis-openembedded-stale.noarch.rpm", 'stale');
    write_binary("$source_repo/xCAT-genesis-openembedded-stale.src.rpm", 'stale');
    write_binary("$deploy_repo/xCAT-genesis-openembedded-stale.noarch.rpm", 'stale');

    my $dependencies = "$tmp/rpm-dependencies";
    my $scratch_repo_root = "$tmp/rpm-repo-root";
    make_rpm_dependencies($dependencies, "$release_root/rpm/$package");
    make_path($scratch_repo_root);
    write_binary(
        "$dependencies/xCAT-genesis-openembedded-x86_64-$version-old.noarch.rpm",
        'stale OpenEmbedded RPM',
    );
    write_binary(
        "$dependencies/xCAT-genesis-openembedded-x86_64-$version-old.src.rpm",
        'stale OpenEmbedded SRPM',
    );

    my @perl_lib;
    push(@perl_lib, write_forkmanager_stub("$tmp/perl-stub"))
      unless eval { require Parallel::ForkManager; 1 };
    push(@perl_lib, $ENV{PERL5LIB})
      if defined($ENV{PERL5LIB}) && $ENV{PERL5LIB} ne '';
    local $ENV{PERL5LIB} = join(':', @perl_lib);
    my $log = "$tmp/rpm-consumer.log";
    my $status = run_capture(
        $log,
        $^X, $rpm_consumer,
        '--repo-root', $scratch_repo_root,
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
    is(digest_file("$deploy_repo/$package"), digest_file("$release_root/rpm/$package"),
        'deployed RPM matches the release');
    is(
        sprintf('%04o', (stat("$deploy_repo/$package"))[2] & 0x0fff),
        sprintf('%04o', (stat("$release_root/rpm/$package"))[2] & 0x0fff),
        'deployed RPM keeps the release file mode',
    );
    opendir(my $deploy_dh, $deploy_repo) or die $!;
    my @staging_files = grep { /^\.xcat-deploy\./ } readdir($deploy_dh);
    closedir($deploy_dh) or die $!;
    is_deeply(\@staging_files, [], 'RPM deployment leaves no staging files');
    ok(!-e "$run_repo/xCAT-genesis-openembedded-stale.noarch.rpm",
        'stale run RPM is removed');
    ok(!-e "$source_repo/xCAT-genesis-openembedded-stale.src.rpm",
        'stale source RPM is removed');
    ok(!-e "$deploy_repo/xCAT-genesis-openembedded-stale.noarch.rpm",
        'stale deployed RPM is removed');
    is(digest_file("$source_repo/$source_package"),
        digest_file("$release_root/srpm/$source_package"),
        'source RPM matches the release');
    ok(-f "$deploy_repo/repodata/repomd.xml", 'RPM repository metadata is generated');
    ok(-f "$deploy_repo/xCAT-genesis-base-x86_64-1.noarch.rpm",
        'legacy Genesis package remains available');
    ok(!-e "$run_repo/xCAT-genesis-openembedded-x86_64-$version-old.noarch.rpm",
        'stale OpenEmbedded RPM is not collected');
    ok(!-e "$source_repo/xCAT-genesis-openembedded-x86_64-$version-old.src.rpm",
        'stale OpenEmbedded SRPM is not collected');
    like(read_binary("$output/mockbuild-all/$run/summary.txt"), qr/^copied_rpms=15$/m,
        'release RPM is counted alongside required dependencies');
}

sub test_deb_consumer {
    my $release_root = make_package_release("$tmp/deb", 'deb');
    my $package = "xcat-genesis-openembedded-x86-64_${version}-${release}_all.deb";
    my $apt_root = "$tmp/apt";
    my $input = "$apt_root/ubuntu24.04";
    make_path($input, "$apt_root/pool/main/noble");
    make_legacy_deb("$tmp/dummy-deb", "$input/xcat-genesis-base-amd64_1_all.deb");
    write_binary("$input/xcat-genesis-openembedded-stale.deb", 'stale');
    write_binary("$apt_root/pool/main/noble/xcat-genesis-openembedded-old.deb", 'stale');

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
    like(read_binary($log), qr/Verified copied Genesis package:/,
        'APT repository uses the shared copied-package verifier');
    is(digest_file($pool_package), digest_file("$release_root/deb/$package"),
        'pooled DEB matches the release');
    ok(!-e "$apt_root/pool/main/noble/xcat-genesis-openembedded-old.deb",
        'stale pooled DEB is removed');
    like(read_binary($amd64), qr/^Package: xcat-genesis-openembedded-x86-64$/m,
        'all-architecture DEB is indexed for amd64');
    like(read_binary($ppc64el), qr/^Package: xcat-genesis-openembedded-x86-64$/m,
        'all-architecture DEB is indexed for ppc64el');
    ok(-f "$apt_root/dists/noble/Release", 'APT Release metadata is generated');
    like(read_binary($amd64), qr/^Package: xcat-genesis-base-amd64$/m,
        'legacy Genesis DEB remains available');
    ok(!-e "$apt_root/pool/main/noble/xcat-genesis-openembedded-stale.deb",
        'stale OpenEmbedded DEB is not collected');

    my $collision = "$tmp/apt-collision";
    make_path("$collision/ubuntu24.04");
    write_binary("$collision/ubuntu24.04/$package", 'different');
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
    is($collision_status, 0, 'verified release replaces a stale source package');
    is(digest_file("$collision/pool/main/noble/$package"),
        digest_file("$release_root/deb/$package"),
        'pooled package still matches the verified release');
}

sub test_legacy_rpm_consumer {
    my $release_root = make_package_release("$tmp/rpm-legacy", 'rpm', 'x86_64');
    my $package = "xCAT-genesis-openembedded-x86_64-$version-$release.noarch.rpm";
    my $dependencies = "$tmp/rpm-legacy-dependencies";
    my $output = "$tmp/rpm-legacy-output";
    my $scratch_repo_root = "$tmp/rpm-legacy-repo-root";
    my $target = 'test+epel-10-' . capture_command('uname', '-m');
    my $deployed = "$output/xcat-dep/rh10/" . capture_command('uname', '-m');
    make_rpm_dependencies($dependencies, "$release_root/rpm/$package");
    make_path($scratch_repo_root);
    write_binary("$scratch_repo_root/Gitepoch", '');

    my @perl_lib;
    push(@perl_lib, write_forkmanager_stub("$tmp/perl-legacy-stub"))
      unless eval { require Parallel::ForkManager; 1 };
    push(@perl_lib, $ENV{PERL5LIB})
      if defined($ENV{PERL5LIB}) && $ENV{PERL5LIB} ne '';
    local $ENV{PERL5LIB} = join(':', @perl_lib);

    my $log = "$tmp/rpm-legacy-consumer.log";
    my $status = run_capture(
        $log,
        $^X, $rpm_consumer,
        '--repo-root', $scratch_repo_root,
        '--output', $output,
        '--target', $target,
        '--run-id', 'legacy',
        '--skip-build', '--skip-xcat', '--skip-xcat-dep', '--skip-perl',
        '--skip-createrepo', '--skip-tarball',
        '--collect-dir', $dependencies,
    );

    is($status, 0, 'RPM legacy repository accepts an empty Gitepoch');
    ok(-f "$deployed/xCAT-genesis-base-x86_64-1.noarch.rpm",
        'RPM legacy path still deploys the existing Genesis package');
    is_deeply(
        [ glob("$deployed/xCAT-genesis-openembedded-*.rpm") ],
        [],
        'RPM legacy path does not add OpenEmbedded packages',
    );
}

sub test_legacy_deb_consumer {
    my $apt_root = "$tmp/apt-legacy";
    my $input = "$apt_root/ubuntu24.04";
    make_path($input);
    make_legacy_deb(
        "$tmp/legacy-dummy-deb",
        "$input/xcat-genesis-base-amd64_1_all.deb",
    );

    local $ENV{SOURCE_DATE_EPOCH} = $epoch;
    my $log = "$tmp/deb-legacy-consumer.log";
    my $status = run_capture(
        $log,
        'bash', $deb_consumer,
        '--repo-root', $repo_root,
        '--apt-dir', $apt_root,
        '--skip-sign',
        'ubuntu24.04',
    );
    my $packages = "$apt_root/dists/noble/main/binary-amd64/Packages";

    is($status, 0, 'APT repository keeps working without a Genesis release');
    like(read_binary($packages), qr/^Package: xcat-genesis-base-amd64$/m,
        'APT legacy path still indexes the existing Genesis package');
    unlike(read_binary($packages), qr/^Package: xcat-genesis-openembedded-/m,
        'APT legacy path does not add OpenEmbedded packages');
}

sub test_partial_rpm_release {
    my $release_root = make_package_release("$tmp/rpm-partial", 'rpm', 'x86_64');
    my $output = "$tmp/partial-output";
    my $target = 'test+epel-10-' . capture_command('uname', '-m');
    my $deployed = "$output/xcat-dep/rh10/" . capture_command('uname', '-m');
    my $existing = "$deployed/xCAT-genesis-base-existing.noarch.rpm";
    make_path($deployed);
    write_binary($existing, 'existing release');

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
    like(read_binary($log), qr/Genesis release is missing supported architectures/,
        'RPM partial-release failure names the missing architectures');
    ok(-f $existing, 'partial release does not remove the deployed package');
}

sub test_partial_deb_release {
    my $release_root = make_package_release("$tmp/deb-partial", 'deb', 'x86_64');
    my $apt_root = "$tmp/partial-apt";
    my $pool = "$apt_root/pool/main/noble";
    my $existing = "$pool/xcat-genesis-base-existing.deb";
    make_path($pool);
    write_binary($existing, 'existing release');

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
    like(read_binary($log), qr/Genesis release is missing supported architectures/,
        'APT partial-release failure names the missing architectures');
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

sub make_rpm_dependencies {
    my ($directory, $package) = @_;
    make_path($directory);
    for my $name (qw(
      ipmitool-xcat syslinux-xcat grub2-xcat xnba-undi
      perl-IO-Stty perl-HTTP-Async perl-Net-HTTPS-NB
      xCAT-genesis-base-x86_64
    )) {
        copy($package, "$directory/$name-1.noarch.rpm") or die $!;
    }
}

sub make_legacy_deb {
    my ($root, $output) = @_;
    make_path("$root/DEBIAN");
    write_binary(
        "$root/DEBIAN/control",
        "Package: xcat-genesis-base-amd64\nVersion: 1\nArchitecture: all\n"
          . "Maintainer: xCAT <xcat-user\@lists.sourceforge.net>\n"
          . "Description: repository test package\n",
    );
    die "Cannot build legacy test DEB\n"
      if run_capture(
        "$root.log", 'dpkg-deb', '--root-owner-group', '--build', $root, $output,
      );
}
