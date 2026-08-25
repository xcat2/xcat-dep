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

SKIP: {
    skip 'Genesis package activation requires Linux procfs semantics', 5
      unless $^O eq 'linux';
    test_activation_helper();
}

if ($ENV{XCAT_GENESIS_CI}) {
    BAIL_OUT('CI requires Linux root') unless $^O eq 'linux' && $> == 0;
    for my $command (qw(apt-ftparchive bash createrepo_c dpkg-deb gpg rpm rpmbuild)) {
        BAIL_OUT("CI requires $command") unless command_exists($command);
    }
}

SKIP: {
    skip 'RPM repository tools require a root Linux builder', 40
      unless $^O eq 'linux'
      && $> == 0
      && command_exists('rpmbuild')
      && command_exists('rpmsign')
      && command_exists('rpm')
      && command_exists('createrepo_c');
    test_rpm_consumer();
    test_signed_common_rpm_repository();
    test_legacy_rpm_consumer();
    test_partial_rpm_release();
    test_failed_build_release();
    test_dry_run_release();
}

SKIP: {
    skip 'APT repository tools are not installed', 45
      unless $^O eq 'linux'
      && command_exists('bash')
      && command_exists('dpkg-deb')
      && command_exists('apt-ftparchive')
      && command_exists('gpg');
    test_deb_consumer();
    test_legacy_deb_consumer();
    test_partial_deb_release();
    test_apt_lock();
}

done_testing();

sub test_rpm_consumer {
    my $release_root = make_package_release("$tmp/rpm", 'rpm');
    my $package = "xCAT-genesis-openembedded-x86_64-$version-$release.noarch.rpm";
    my $output = "$tmp/rpm output";
    my $target = 'test+epel-10-' . capture_command('uname', '-m');
    my $run = "$target-consumer";
    my $run_repo = "$output/mockbuild-all/$run/repo/" . capture_command('uname', '-m');
    my $source_repo = "$output/mockbuild-all/$run/repo-src";
    my $deploy_repo = "$output/xcat-dep/rh10/" . capture_command('uname', '-m');
    my $common_repo = "$output/xcat-dep/common";
    make_path($run_repo, $source_repo, $deploy_repo, $common_repo);
    write_binary("$run_repo/xCAT-genesis-openembedded-stale.noarch.rpm", 'stale');
    write_binary("$source_repo/xCAT-genesis-openembedded-stale.src.rpm", 'stale');
    write_binary("$deploy_repo/xCAT-genesis-openembedded-stale.noarch.rpm", 'stale');
    write_binary("$common_repo/xCAT-genesis-openembedded-stale.noarch.rpm", 'stale');
    write_binary("$common_repo/xCAT-genesis-openembedded-stale.src.rpm", 'stale');

    my $rpm_scripts = capture_command(
        'rpm', '-qp', '--scripts', "$release_root/rpm/$package"
    );
    like($rpm_scripts, qr{genesis-openembedded-activate-x86_64 x86_64},
        'the RPM refreshes its architecture after a package transaction');
    like(
        capture_command('rpm', '-qpl', "$release_root/rpm/$package"),
        qr{/usr/libexec/xcat/genesis-openembedded-activate-x86_64$}m,
        'the RPM contains its architecture-specific activation helper',
    );

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
    is(digest_file("$common_repo/$package"), digest_file("$release_root/rpm/$package"),
        'deployed RPM matches the release');
    is(
        sprintf('%04o', (stat("$common_repo/$package"))[2] & 0x0fff),
        sprintf('%04o', (stat("$release_root/rpm/$package"))[2] & 0x0fff),
        'deployed RPM keeps the release file mode',
    );
    opendir(my $deploy_dh, $common_repo) or die $!;
    my @staging_files = grep { /^\.xcat-deploy\./ } readdir($deploy_dh);
    closedir($deploy_dh) or die $!;
    is_deeply(\@staging_files, [], 'RPM deployment leaves no staging files');
    ok(!-e "$run_repo/xCAT-genesis-openembedded-stale.noarch.rpm",
        'stale run RPM is removed');
    ok(!-e "$source_repo/xCAT-genesis-openembedded-stale.src.rpm",
        'stale source RPM is removed');
    ok(!-e "$deploy_repo/xCAT-genesis-openembedded-stale.noarch.rpm",
        'stale deployed RPM is removed');
    ok(-f "$common_repo/repodata/repomd.xml", 'RPM repository metadata is generated');
    ok(-f "$deploy_repo/xCAT-genesis-base-x86_64-1.noarch.rpm",
        'legacy Genesis package remains available');
    my @expected_packages = sort map {
        rpm_package_name($_) . "-$version-$release.noarch.rpm"
    } architectures();
    my @common_packages = genesis_rpm_names($common_repo);
    is_deeply(\@common_packages, \@expected_packages,
        'common repository contains one complete Genesis release');
    is_deeply(
        [ genesis_rpm_names($deploy_repo) ],
        [],
        'per-EL repository contains no OpenEmbedded Genesis packages',
    );
    is_deeply(
        [ genesis_rpm_names($run_repo) ],
        [],
        'target staging repository contains no OpenEmbedded Genesis packages',
    );
    is_deeply(
        [ genesis_rpm_names($source_repo) ],
        [],
        'target source repository contains no OpenEmbedded Genesis packages',
    );
    my $common_config = read_binary("$common_repo/xcat-dep-common.repo");
    like($common_config, qr/^\[xcat-dep-common\]$/m,
        'common repository has its own repository ID');
    like($common_config, qr{/xcat-dep/common$}m,
        'common repository configuration uses the shared URL');
    ok(-x "$common_repo/mklocalrepo.sh", 'common repository supports offline setup');
    like(read_binary("$common_repo/buildinfo.txt"), qr/^TARGET=common$/m,
        'common repository records its target');
    like(read_binary("$output/mockbuild-all/$run/summary.txt"), qr/^copied_rpms=8$/m,
        'repository summary counts the collected dependencies');
}

sub test_deb_consumer {
    my $release_root = make_package_release("$tmp/deb", 'deb');
    my $package = "xcat-genesis-openembedded-x86-64_${version}-${release}_all.deb";
    my $apt_root = "$tmp/apt";
    my $input = make_apt_inputs($apt_root, "$tmp/dummy-deb");
    my $shared_pool = "$apt_root/pool/main/xcat-genesis-openembedded";
    make_path($input, $shared_pool);
    write_binary("$input/xcat-genesis-openembedded-stale.deb", 'stale');
    write_binary("$shared_pool/xcat-genesis-openembedded-old.deb", 'stale');

    my $postinst = capture_command(
        'dpkg-deb', '--info', "$release_root/deb/$package", 'postinst'
    );
    isnt($postinst, '', 'the DEB includes a post-installation script');
    like($postinst, qr{genesis-openembedded-activate-x86_64 x86_64},
        'the DEB refreshes its architecture after configuration');

    local $ENV{SOURCE_DATE_EPOCH} = $epoch;
    my $log = "$tmp/deb-consumer.log";
    my $status = run_capture(
        $log,
        'bash', $deb_consumer,
        '--repo-root', $repo_root,
        '--apt-dir', $apt_root,
        '--skip-sign',
        '--genesis-release', $release_root,
    );
    my $pool_package = "$shared_pool/$package";
    my $amd64 = "$apt_root/dists/noble/main/binary-amd64/Packages";

    is($status, 0, 'APT repository accepts a verified Genesis release');
    like(read_binary($log), qr/Verified copied Genesis package:/,
        'APT repository uses the shared copied-package verifier');
    is(digest_file($pool_package), digest_file("$release_root/deb/$package"),
        'pooled DEB matches the release');
    ok(!-e "$shared_pool/xcat-genesis-openembedded-old.deb",
        'stale pooled DEB is removed');
    my @expected_packages = sort map {
        deb_package_name($_) . "_${version}-${release}_all.deb"
    } architectures();
    is_deeply([ genesis_deb_names($shared_pool) ], \@expected_packages,
        'shared APT pool contains one complete Genesis release');
    my @suite_packages;
    for my $codename (qw(jammy noble resolute)) {
        push(@suite_packages, map { "$codename/$_" }
            genesis_deb_names("$apt_root/pool/main/$codename"));
    }
    is_deeply(\@suite_packages, [], 'suite pools contain no OpenEmbedded Genesis packages');
    for my $codename (qw(jammy noble resolute)) {
        for my $architecture (qw(amd64 ppc64el)) {
            my $packages = read_binary(
                "$apt_root/dists/$codename/main/binary-$architecture/Packages"
            );
            like($packages,
                qr{^Filename: pool/main/xcat-genesis-openembedded/\Q$package\E$}m,
                "$codename $architecture index uses the shared Genesis package",
            );
        }
    }
    is_deeply(
        [ grep { !-f "$apt_root/dists/$_/Release" } qw(jammy noble resolute) ],
        [],
        'APT Release metadata is generated for every suite',
    );
    like(read_binary($amd64), qr/^Package: xcat-genesis-base-amd64$/m,
        'legacy Genesis DEB remains available');
    ok(!-e "$apt_root/pool/main/noble/xcat-genesis-openembedded-stale.deb",
        'stale OpenEmbedded DEB is not collected');
    # The published package must be a file of its own: sharing an inode with the release
    # would make a later write through either path change what the other one holds.
    my @pooled = stat($pool_package);
    my @released = stat("$release_root/deb/$package");
    isnt("$pooled[0]:$pooled[1]", "$released[0]:$released[1]",
        'pooled DEB is published independently of the release file');
    like(read_binary($log), qr/^Re-verified pooled Genesis package: \Q$pool_package\E$/m,
        'pooled DEB is verified again before the indexes are generated');

    my $collision = "$tmp/apt-collision";
    make_apt_inputs($collision, "$tmp/collision-deb");
    write_binary("$collision/ubuntu24.04/$package", 'different');
    my $collision_log = "$tmp/deb-collision.log";
    my $collision_status = run_capture(
        $collision_log,
        'bash', $deb_consumer,
        '--repo-root', $repo_root,
        '--apt-dir', $collision,
        '--skip-sign',
        '--genesis-release', $release_root,
    );
    my $collision_package = "$collision/pool/main/xcat-genesis-openembedded/$package";
    is($collision_status, 0, 'verified release replaces a stale source package');
    is(digest_file($collision_package),
        digest_file("$release_root/deb/$package"),
        'pooled package still matches the verified release');

    my $subset_log = "$tmp/deb-subset.log";
    my $before_subset = digest_file($pool_package);
    my $subset_status = run_capture(
        $subset_log,
        'bash', $deb_consumer,
        '--repo-root', $repo_root,
        '--apt-dir', $apt_root,
        '--skip-sign',
        '--genesis-release', $release_root,
        'ubuntu24.04',
    );
    isnt($subset_status, 0, 'Genesis publication rejects a partial suite update');
    like(read_binary($subset_log), qr/updates all suites; omit DIST arguments/,
        'partial suite failure explains the consistency requirement');
    is(digest_file($pool_package), $before_subset,
        'partial suite failure leaves the shared package unchanged');

    my $jammy_before = digest_file(
        "$apt_root/dists/jammy/main/binary-amd64/Packages"
    );
    my $resolute_before = digest_file(
        "$apt_root/dists/resolute/main/binary-amd64/Packages"
    );
    write_binary(
        "$apt_root/ubuntu24.04/xcat-genesis-openembedded-stale.deb",
        'stale suite package',
    );
    my $refresh_log = "$tmp/deb-refresh.log";
    my $refresh_status = run_capture(
        $refresh_log,
        'bash', $deb_consumer,
        '--repo-root', $repo_root,
        '--apt-dir', $apt_root,
        '--skip-sign',
        'ubuntu24.04',
    );
    is($refresh_status, 0, 'a suite refresh reuses the shared Genesis pool');
    is(digest_file($pool_package), $before_subset,
        'a suite refresh leaves the shared package unchanged');
    like(
        read_binary("$apt_root/dists/noble/main/binary-amd64/Packages"),
        qr{^Filename: pool/main/xcat-genesis-openembedded/\Q$package\E$}m,
        'the refreshed suite still indexes the shared package',
    );
    ok(
        !-e "$apt_root/pool/main/noble/xcat-genesis-openembedded-stale.deb",
        'a suite refresh does not restore the old per-suite package layout',
    );
    is(
        digest_file("$apt_root/dists/jammy/main/binary-amd64/Packages"),
        $jammy_before,
        'a suite refresh leaves the jammy index alone',
    );
    is(
        digest_file("$apt_root/dists/resolute/main/binary-amd64/Packages"),
        $resolute_before,
        'a suite refresh leaves the resolute index alone',
    );

    my $full_refresh_log = "$tmp/deb-full-refresh.log";
    my $full_refresh_status = run_capture(
        $full_refresh_log,
        'bash', $deb_consumer,
        '--repo-root', $repo_root,
        '--apt-dir', $apt_root,
        '--skip-sign',
    );
    is($full_refresh_status, 0, 'a full refresh reuses the shared Genesis pool');
    is(digest_file($pool_package), $before_subset,
        'a full refresh leaves the shared package unchanged');
    for my $codename (qw(jammy noble resolute)) {
        like(
            read_binary("$apt_root/dists/$codename/main/binary-amd64/Packages"),
            qr{^Filename: pool/main/xcat-genesis-openembedded/\Q$package\E$}m,
            "$codename still indexes the shared package after a full refresh",
        );
    }
}

sub test_signed_common_rpm_repository {
    my $release_root = make_package_release("$tmp/rpm-signed", 'rpm');
    my $package = "xCAT-genesis-openembedded-x86_64-$version-$release.noarch.rpm";
    my $output = "$tmp/rpm-signed-output";
    my $target = 'test+epel-10-' . capture_command('uname', '-m');
    my $dependencies = "$tmp/rpm-signed-dependencies";
    my $scratch_repo_root = "$tmp/rpm-signed-repo-root";
    my $common = "$output/xcat-dep/common";
    my $gpg_home = "$tmp/rpm-signing-key";
    my $identity = 'xCAT repository test <xcat-repository-test@example.invalid>';
    make_rpm_dependencies($dependencies, "$release_root/rpm/$package");
    make_path($scratch_repo_root, $gpg_home);
    chmod(0700, $gpg_home) or die $!;
    system(
        'gpg', '--batch', '--homedir', $gpg_home, '--passphrase', '',
        '--quick-generate-key', $identity, 'rsa2048', 'sign', '0',
    ) == 0 or die "could not create the repository test key";

    my @perl_lib;
    push(@perl_lib, write_forkmanager_stub("$tmp/perl-signed-stub"))
      unless eval { require Parallel::ForkManager; 1 };
    push(@perl_lib, $ENV{PERL5LIB})
      if defined($ENV{PERL5LIB}) && $ENV{PERL5LIB} ne '';
    local $ENV{PERL5LIB} = join(':', @perl_lib);

    my $log = "$tmp/rpm-signed-consumer.log";
    my $status = run_capture(
        $log,
        $^X, $rpm_consumer,
        '--repo-root', $scratch_repo_root,
        '--xcat-source', $repo_root,
        '--output', $output,
        '--target', $target,
        '--run-id', 'signed-consumer',
        '--build-timestamp', $epoch,
        '--skip-build', '--skip-xcat', '--skip-xcat-dep', '--skip-perl',
        '--skip-genesis', '--skip-createrepo', '--skip-tarball',
        '--collect-dir', $dependencies,
        '--genesis-release', $release_root,
        '--gpg-sign', '--gpg-key-name', $identity, '--gpg-home', $gpg_home,
    );

    diag(read_binary($log)) if $status;
    is($status, 0, 'the common RPM repository can be signed');
    ok(-f "$common/repodata/repomd.xml.key",
        'the common repository exports its own public key');
    is(
        system(
            'gpg', '--batch', '--homedir', $gpg_home, '--verify',
            "$common/repodata/repomd.xml.asc",
            "$common/repodata/repomd.xml",
        ) >> 8,
        0,
        'the common repository metadata signature verifies',
    );
    like(
        read_binary("$common/xcat-dep-common.repo"),
        qr{^gpgkey=https://xcat\.org/files/xcat/repos/yum/devel/xcat-dep/common/repodata/repomd\.xml\.key$}m,
        'the common repository file points to its own exported key',
    );
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
    ok(!-d "$output/xcat-dep/common",
        'RPM legacy path does not create the common repository');
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
    my $common = "$output/xcat-dep/common";
    my $existing = "$common/xCAT-genesis-openembedded-existing.noarch.rpm";
    make_path($common);
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

sub test_failed_build_release {
    my $release_root = make_package_release("$tmp/rpm-empty", 'rpm');
    my $package = "xCAT-genesis-openembedded-x86_64-$version-$release.noarch.rpm";
    my $output = "$tmp/empty-output";
    my $target = 'test+epel-10-' . capture_command('uname', '-m');
    my $common = "$output/xcat-dep/common";
    my $scratch_repo_root = "$tmp/rpm-empty-root";
    my $collected = "$tmp/rpm-empty-collect";
    my $run_repo = "$output/mockbuild-all/$target-empty/repo/" . capture_command('uname', '-m');
    my $results = "$output/mockbuild-all/$target-empty/build-results/ipmitool-xcat";
    my $stale = "$run_repo/ipmitool-xcat-0-stale.noarch.rpm";
    my $kept = "$results/ipmitool-xcat-0-earlier.noarch.rpm";
    make_path($common, $scratch_repo_root, $collected, $run_repo, $results);
    write_binary($stale, 'package left by an earlier run');
    write_binary($kept, 'build output an earlier run produced');

    my $log = "$tmp/rpm-empty.log";
    my $status = run_capture(
        $log,
        $^X, $rpm_consumer,
        '--repo-root', $scratch_repo_root,
        '--output', $output,
        '--target', $target,
        '--run-id', 'empty',
        '--build-timestamp', $epoch,
        '--skip-build', '--skip-xcat', '--skip-xcat-dep', '--skip-perl',
        '--skip-createrepo', '--skip-tarball',
        '--genesis-release', $release_root,
        '--collect-dir', $collected,
    );

    isnt($status, 0, 'a run that built nothing fails even with a Genesis release');
    like(read_binary($log), qr/No binary RPMs were collected/,
        'the failure names the empty collection, not the missing dependencies');
    ok(!-e "$common/$package",
        'a run that built nothing publishes no release package');
    ok(!-e $stale,
        'a package left by an earlier run is cleared from the staging repository');
    ok(-e $kept,
        'a run that skips building keeps the build results it collects from');
}

sub test_dry_run_release {
    my $release_root = make_package_release("$tmp/rpm-dry", 'rpm');
    my $package = "xCAT-genesis-openembedded-x86_64-$version-$release.noarch.rpm";
    my $output = "$tmp/dry-output";
    my $target = 'test+epel-10-' . capture_command('uname', '-m');
    my $run_repo = "$output/mockbuild-all/$target-dry/repo/" . capture_command('uname', '-m');
    my $dependencies = "$tmp/rpm-dry-dependencies";
    my $scratch_repo_root = "$tmp/rpm-dry-root";
    make_rpm_dependencies($dependencies, "$release_root/rpm/$package");
    make_path($scratch_repo_root);

    my $log = "$tmp/rpm-dry.log";
    my $status = run_capture(
        $log,
        $^X, $rpm_consumer,
        '--repo-root', $scratch_repo_root,
        '--output', $output,
        '--target', $target,
        '--run-id', 'dry',
        '--build-timestamp', $epoch,
        '--skip-build', '--skip-xcat', '--skip-xcat-dep', '--skip-perl',
        '--skip-createrepo', '--skip-tarball',
        '--genesis-release', $release_root,
        '--collect-dir', $dependencies,
        '--dry-run',
    );
    my $printed = read_binary($log);

    is($status, 0, 'a dry run accepts a verified Genesis release');
    like($printed,
        qr{^DRY-RUN publish Genesis release package: .*\Q$package\E -> .*/xcat-dep/common/\Q$package\E$}m,
        'the dry run reports the shared package destination');
    like($printed, qr/^Collected binary RPMs: 8$/m,
        'the dry run counts the packages collected for the target repository');
    ok(!-e "$run_repo/$package", 'the dry run installs nothing');
}

sub test_apt_lock {
    my $apt_root = "$tmp/apt-lock";
    my $input = "$apt_root/ubuntu24.04";
    make_path($input, "$apt_root/.lock");
    make_legacy_deb("$tmp/lock-deb", "$input/xcat-genesis-base-amd64_1_all.deb");

    my $locked_log = "$tmp/deb-locked.log";
    my $locked_status = run_capture(
        $locked_log,
        'bash', $deb_consumer,
        '--repo-root', $repo_root,
        '--apt-dir', $apt_root,
        '--skip-sign',
        'ubuntu24.04',
    );
    isnt($locked_status, 0, 'a locked APT directory is not published into');
    like(read_binary($locked_log), qr/\Q$apt_root\E is locked/,
        'the refusal names the directory another run owns');

    my $forced_log = "$tmp/deb-forced.log";
    my $forced_status = run_capture(
        $forced_log,
        'bash', $deb_consumer,
        '--repo-root', $repo_root,
        '--apt-dir', $apt_root,
        '--skip-sign',
        '--force-unlock',
        'ubuntu24.04',
    );
    is($forced_status, 0, '--force-unlock takes over a stale lock');
    ok(!-d "$apt_root/.lock", 'the lock is released when the run finishes');
}

sub test_activation_helper {
    my $root = "$tmp/activation-root";
    my $bin = "$tmp/activation-bin";
    my $log = "$tmp/activation.log";
    my $output = "$tmp/activation-output.log";
    make_path(
        "$root/proc/1",
        "$root/opt/xcat/sbin",
        $bin,
    );
    write_binary("$root/proc/cmdline", "test\n");
    symlink($root, "$root/proc/1/root") or die "Cannot create proc root link: $!";
    write_binary(
        "$root/opt/xcat/sbin/mknb",
        <<'SH',
#!/bin/sh
echo "$*" >>"$XCAT_TEST_LOG"
exit "${XCAT_TEST_MKNB_STATUS:-0}"
SH
    );
    write_binary(
        "$root/opt/xcat/sbin/tabdump",
        <<'SH',
#!/bin/sh
printf '"sharedtftp","%s"\n' "${XCAT_TEST_SHAREDTFTP:-0}"
SH
    );
    write_binary(
        "$bin/rpm",
        <<'SH',
#!/bin/sh
[ "${XCAT_TEST_SERVICE_NODE:-0}" = "1" ]
SH
    );
    chmod(0755,
        "$root/opt/xcat/sbin/mknb",
        "$root/opt/xcat/sbin/tabdump",
        "$bin/rpm",
    ) or die "Cannot make activation fixtures executable: $!";

    local $ENV{XCAT_GENESIS_ROOT} = $root;
    local $ENV{XCAT_TEST_LOG} = $log;
    local $ENV{PATH} = "$bin:$ENV{PATH}";
    my $status = run_capture(
        $output, "$repo_root/genesis-openembedded/activate", 'x86_64'
    );
    is($status, 0, 'the activation helper accepts a local-TFTP node');
    is(read_binary($log), "x86_64\n", 'the activation helper runs mknb for one architecture');

    write_binary($log, '');
    local $ENV{XCAT_TEST_SERVICE_NODE} = 1;
    local $ENV{XCAT_TEST_SHAREDTFTP} = 1;
    $status = run_capture(
        $output, "$repo_root/genesis-openembedded/activate", 'ppc64le'
    );
    is($status, 0, 'a shared-TFTP service node is accepted');
    is(read_binary($log), '', 'a shared-TFTP service node does not rebuild Genesis');

    local $ENV{XCAT_TEST_SERVICE_NODE} = 0;
    local $ENV{XCAT_TEST_MKNB_STATUS} = 1;
    $status = run_capture(
        $output, "$repo_root/genesis-openembedded/activate", 'ppc64le'
    );
    is($status, 0, 'an mknb failure does not fail the package transaction');
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

sub genesis_rpm_names {
    my ($directory) = @_;
    return () unless -d $directory;
    opendir(my $dh, $directory) or die $!;
    my @names = sort grep { /^xCAT-genesis-openembedded-.*\.rpm$/ } readdir($dh);
    closedir($dh) or die $!;
    return @names;
}

sub genesis_deb_names {
    my ($directory) = @_;
    return () unless -d $directory;
    opendir(my $dh, $directory) or die $!;
    my @names = sort grep { /^xcat-genesis-openembedded-.*\.deb$/ } readdir($dh);
    closedir($dh) or die $!;
    return @names;
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

sub make_apt_inputs {
    my ($apt_root, $package_root) = @_;
    my $package = "$package_root.deb";
    make_legacy_deb($package_root, $package);
    for my $version (qw(ubuntu22.04 ubuntu24.04 ubuntu26.04)) {
        my $input = "$apt_root/$version";
        make_path($input);
        copy($package, "$input/xcat-genesis-base-amd64_1_all.deb") or die $!;
    }
    return "$apt_root/ubuntu24.04";
}
