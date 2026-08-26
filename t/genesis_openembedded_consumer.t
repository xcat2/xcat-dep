use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(basename);
use File::Copy qw(copy);
use File::Path qw(make_path);
use Fcntl qw(:flock);
use File::Temp qw(tempdir);
use FindBin;
use POSIX ();
use Test::More;
use Time::HiRes qw(sleep);

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
my $deb_consumer = "$repo_root/sbuild-all.pl";
my $revision = 'b' x 40;
my $version = '2.19.0';
my $release = 'snap202608210726';
my $epoch = 1787293573;
my $tmp = tempdir(CLEANUP => 1);
# every suite sbuild-all.pl knows; publishing a Genesis release must cover all of them
my @APT_SUITES = qw(focal jammy noble resolute);

test_activation_helper();

if ($ENV{XCAT_GENESIS_CI}) {
    BAIL_OUT('CI requires Linux root') unless $^O eq 'linux' && $> == 0;
    for my $command (qw(apt-ftparchive bash createrepo_c dpkg-deb gpg rpm rpmbuild)) {
        BAIL_OUT("CI requires $command") unless command_exists($command);
    }
}

SKIP: {
    skip 'RPM repository tools require a root Linux builder', 69
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
    test_rpm_repository_lock();
    test_rpm_signal_cleanup();
}

SKIP: {
    skip 'APT repository tools are not installed', 59
      unless $^O eq 'linux'
      && command_exists('dpkg-deb')
      && command_exists('apt-ftparchive');
    test_deb_consumer();
    test_legacy_deb_consumer();
    test_partial_deb_release();
    test_publish_lock();
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
    like($rpm_scripts, qr{mknb x86_64 --remove-openembedded},
        'the RPM removes published artifacts when the image is erased');
    like($rpm_scripts, qr{/proc/1/root},
        'the RPM removal path refuses to operate from a chroot');
    like(
        capture_command('rpm', '-qpl', "$release_root/rpm/$package"),
        qr{/usr/libexec/xcat/genesis-openembedded-activate-x86_64$}m,
        'the RPM contains its architecture-specific activation helper',
    );
    like(
        capture_command('rpm', '-qpl', "$release_root/rpm/$package"),
        qr{^/usr/libexec/xcat/?$}m,
        'the RPM owns its private helper directory',
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
    is(
        sprintf('%04o', (stat($common_repo))[2] & 0x0fff),
        '0755',
        'the common repository is traversable by an unprivileged server',
    );
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
    like($common_config, qr/^skip_if_unavailable=1$/m,
        'the published common repository stays optional during outages');
    like($common_config, qr/^repo_gpgcheck=0$/m,
        'unsigned test metadata is declared explicitly');
    ok(-x "$common_repo/mklocalrepo.sh", 'common repository supports offline setup');
    my $local_repo_helper = read_binary("$common_repo/mklocalrepo.sh");
    unlike($local_repo_helper, qr/\[\[/,
        'the offline helper does not require Bash conditionals');
    unlike($local_repo_helper, qr/`/,
        'the offline helper uses POSIX command substitution');
    like(read_binary("$common_repo/buildinfo.txt"), qr/^TARGET=common$/m,
        'common repository records its target');
    like(read_binary("$output/mockbuild-all/$run/summary.txt"), qr/^copied_rpms=8$/m,
        'repository summary counts the collected dependencies');

    my $retained = "$common_repo/xCAT-genesis-openembedded-retained.noarch.rpm";
    my $repomd = "$common_repo/repodata/repomd.xml";
    my $repomd_before = digest_file($repomd);
    write_binary($retained, 'previous complete release');
    my $fail_bin = "$tmp/rpm-fail-bin";
    make_path($fail_bin);
    write_binary(
        "$fail_bin/createrepo_c",
        <<'SH',
#!/bin/sh
for argument in "$@"; do last=$argument; done
case "$last" in
    */common|*/.common.*) exit 1 ;;
esac
exec "$XCAT_TEST_CREATEREPO" "$@"
SH
    );
    chmod(0755, "$fail_bin/createrepo_c") or die $!;
    local $ENV{XCAT_TEST_CREATEREPO} = capture_command(
        'sh', '-c', 'command -v createrepo_c'
    );
    local $ENV{PATH} = "$fail_bin:$ENV{PATH}";
    my $failed_log = "$tmp/rpm-publication-failure.log";
    my $failed_status = run_capture(
        $failed_log,
        $^X, $rpm_consumer,
        '--repo-root', $scratch_repo_root,
        '--output', $output,
        '--target', $target,
        '--run-id', 'publication-failure',
        '--build-timestamp', $epoch,
        '--skip-build', '--skip-xcat', '--skip-xcat-dep', '--skip-perl',
        '--skip-createrepo', '--skip-tarball',
        '--genesis-release', $release_root,
        '--collect-dir', $dependencies,
    );
    isnt($failed_status, 0, 'a failed RPM metadata build aborts publication');
    ok(-f $retained, 'a failed RPM publication keeps the previous package set');
    is(digest_file($repomd), $repomd_before,
        'a failed RPM publication keeps the previous metadata');
}

# The apt consumer is sbuild-all.pl's PUBLISH phase: it stages nothing here -- it assembles the
# already-staged debs plus the Genesis release into a side tree, gates it, and swaps that tree onto
# the published repository with a single rename. Every run below is therefore a publish-only run
# (--skip-build) over a hand-made staging tree, with the manifest reduced to the one package
# --skip-genesis drops, so the completeness gate has nothing to demand of a fixture.

sub run_apt_consumer {
    my (%args) = @_;
    my @dists = @{ $args{dists} // \@APT_SUITES };
    my $manifest = $args{manifest};
    unless ($manifest) {
        $manifest = "$args{output}/manifest.conf";
        make_path($args{output});
        # plus the shipped [shared] section verbatim: publishing a release gates the shared pool
        # against it, and a manifest without it is refused rather than silently ungated.
        my $shipped = read_binary("$repo_root/debs-manifest.conf");
        my ($shared) = $shipped =~ /^(\[shared\]\n(?:[^\[]*))/ms;
        BAIL_OUT('debs-manifest.conf has no [shared] section') unless $shared;
        write_binary($manifest,
            join('', map { "[$_-amd64]\nxcat-genesis-base=*\n" } @APT_SUITES) . "\n" . $shared);
    }
    return run_capture(
        $args{log},
        $^X, $deb_consumer,
        '--repo-root',   $repo_root,
        '--output-root', $args{output},
        '--apt-dir',     $args{apt_dir},
        '--manifest',    $manifest,
        '--dists',       join(' ', @dists),
        '--arch',        'amd64',
        '--skip-build', '--skip-genesis', '--skip-tarball',
        '--publish', '--expect-arch', 'amd64 ppc64el',
        ($args{verify} ? () : ('--no-verify-repo')),
        @{ $args{extra} // [] },
    );
}

# Stage one legacy genesis-base deb for the noble suite only -- enough for the runs that publish
# no Genesis release.
sub stage_legacy_deb {
    my ($root, $output) = @_;
    my $staging = "$output/staging/noble/amd64";
    make_path($staging);
    make_legacy_deb($root, "$staging/xcat-genesis-base-amd64_1_all.deb");
    return $staging;
}

# Stage one legacy genesis-base deb for each suite, standing in for a completed build.
sub stage_apt_suites {
    my ($output, $package_root, $content) = @_;
    my $package = "$package_root.deb";
    make_legacy_deb($package_root, $package, $content);
    for my $codename (@APT_SUITES) {
        my $staged = "$output/staging/$codename/amd64";
        make_path($staged);
        copy($package, "$staged/xcat-genesis-base-amd64_1_all.deb") or die $!;
    }
    return "$output/staging/noble/amd64";
}

sub test_deb_consumer {
    my $release_root = make_package_release("$tmp/deb", 'deb');
    my $package = "xcat-genesis-openembedded-x86-64_${version}-${release}_all.deb";
    my $apt_root = "$tmp/apt";
    my $output = "$tmp/deb-output";
    my $staged = stage_apt_suites($output, "$tmp/dummy-deb");
    my $shared_pool = "$apt_root/pool/main/xcat-genesis-openembedded";
    make_path($shared_pool);
    write_binary("$staged/xcat-genesis-openembedded-stale.deb", 'stale');
    write_binary("$shared_pool/xcat-genesis-openembedded-old.deb", 'stale');

    my $postinst = capture_command(
        'dpkg-deb', '--info', "$release_root/deb/$package", 'postinst'
    );
    isnt($postinst, '', 'the DEB includes a post-installation script');
    like($postinst, qr{genesis-openembedded-activate-x86_64 x86_64},
        'the DEB refreshes its architecture after configuration');
    my $postrm = capture_command(
        'dpkg-deb', '--info', "$release_root/deb/$package", 'postrm'
    );
    like($postrm, qr{mknb x86_64 --remove-openembedded},
        'the DEB removes published artifacts when the image is erased');
    like($postrm, qr{/proc/1/root},
        'the DEB removal path refuses to operate from a chroot');

    local $ENV{SOURCE_DATE_EPOCH} = $epoch;
    my $log = "$tmp/deb-consumer.log";
    my $status = run_apt_consumer(
        log => $log, output => $output, apt_dir => $apt_root,
        extra => [ '--genesis-release', $release_root ],
    );
    my $pool_package = "$shared_pool/$package";
    my $amd64 = "$apt_root/dists/noble/main/binary-amd64/Packages";

    is($status, 0, 'APT repository accepts a verified Genesis release');
    is(digest_file($pool_package), digest_file("$release_root/deb/$package"),
        'pooled DEB matches the release');
    is(
        sprintf('%04o', (stat($pool_package))[2] & 0x0fff),
        '0644',
        'the pooled DEB is readable by an unprivileged server',
    );
    ok(!-e "$shared_pool/xcat-genesis-openembedded-old.deb",
        'stale pooled DEB is removed');
    my @expected_packages = sort map {
        deb_package_name($_) . "_${version}-${release}_all.deb"
    } architectures();
    is_deeply([ genesis_deb_names($shared_pool) ], \@expected_packages,
        'shared APT pool contains one complete Genesis release');
    like(read_binary($log), qr/\[verify-repo\] shared pool complete: 7 packages present/,
        'the shared pool is gated against the manifest\'s [shared] section');
    my @suite_packages;
    for my $codename (@APT_SUITES) {
        push(@suite_packages, map { "$codename/$_" }
            genesis_deb_names("$apt_root/pool/main/$codename"));
    }
    is_deeply(\@suite_packages, [], 'suite pools contain no OpenEmbedded Genesis packages');
    for my $codename (@APT_SUITES) {
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
        [ grep { !-f "$apt_root/dists/$_/Release" } @APT_SUITES ],
        [],
        'APT Release metadata is generated for every suite',
    );
    like(read_binary($amd64), qr/^Package: xcat-genesis-base-amd64$/m,
        'legacy Genesis DEB remains available');
    ok(!-e "$apt_root/pool/main/noble/xcat-genesis-openembedded-stale.deb",
        'a staged OpenEmbedded DEB is not published into a suite pool');
    # The published package must be a file of its own: sharing an inode with the release
    # would make a later write through either path change what the other one holds.
    my @pooled = stat($pool_package);
    my @released = stat("$release_root/deb/$package");
    isnt("$pooled[0]:$pooled[1]", "$released[0]:$released[1]",
        'pooled DEB is published independently of the release file');
    my $publication_log = read_binary($log);
    my $verified_at = index($publication_log, 'published + verified');
    my $indexed_at = index($publication_log, 'assembled + ');
    ok($verified_at >= 0 && $verified_at < $indexed_at,
        'staged DEBs are verified before any suite index is generated');

    # A release rewrites the shared pool every suite indexes, so it cannot be published for
    # some suites only -- the others would be left indexing files the new release retired.
    my $before_subset = digest_file($pool_package);
    my $subset_log = "$tmp/deb-subset.log";
    my $subset_status = run_apt_consumer(
        log => $subset_log, output => $output, apt_dir => $apt_root,
        dists => ['noble'],
        extra => [ '--genesis-release', $release_root ],
    );
    isnt($subset_status, 0, 'Genesis publication rejects a partial suite update');
    like(read_binary($subset_log), qr/must\n?\s*cover all of them/,
        'partial suite failure explains the consistency requirement');
    is(digest_file($pool_package), $before_subset,
        'partial suite failure leaves the shared package unchanged');

    # A later suite rebuild carries no release and must keep indexing the shared pool.
    my $refresh_log = "$tmp/deb-refresh.log";
    my $refresh_status = run_apt_consumer(
        log => $refresh_log, output => $output, apt_dir => $apt_root,
        dists => ['noble'],
    );
    is($refresh_status, 0, 'a suite refresh reuses the shared Genesis pool');
    is(digest_file($pool_package), $before_subset,
        'a suite refresh leaves the shared package unchanged');
    like(read_binary($amd64),
        qr{^Filename: pool/main/xcat-genesis-openembedded/\Q$package\E$}m,
        'the refreshed suite still indexes the shared Genesis package');

    # The repository changes with ONE rename, at the very end: a publication that fails while it
    # assembles must leave every published byte -- packages, indexes and key -- exactly as it was.
    # Signing with a key the keyring does not hold fails inside that phase.
    my $package_before = digest_file(
        "$apt_root/pool/main/noble/xcat-genesis-base-amd64_1_all.deb");
    my $metadata_before = digest_file($amd64);
    my $empty_keyring = "$tmp/apt-empty-keyring";
    make_path($empty_keyring);
    chmod(0700, $empty_keyring) or die $!;
    my $failed_log = "$tmp/deb-failed-publish.log";
    my $failed_status = run_apt_consumer(
        log => $failed_log, output => $output, apt_dir => $apt_root,
        dists => ['noble'],
        extra => [ '--gpg-sign', '--gpg-key-id', 'absent@example.invalid',
                   '--gpg-home', $empty_keyring ],
    );
    isnt($failed_status, 0, 'a publication that cannot be signed is not published');
    like(read_binary($failed_log), qr/NOT publishing/,
        'the refusal says the published repository was left alone');
    is(digest_file("$apt_root/pool/main/noble/xcat-genesis-base-amd64_1_all.deb"),
        $package_before, 'a failed publication leaves the published package bytes');
    is(digest_file($amd64), $metadata_before,
        'a failed publication leaves the published package index');
    is(digest_file($pool_package), $before_subset,
        'a failed publication leaves the shared Genesis pool');

    # A rebuilt deb keeps its filename; the published copy must become the new one.
    my $legacy_pool = "$apt_root/pool/main/noble/xcat-genesis-base-amd64_1_all.deb";
    my $legacy_before = digest_file($legacy_pool);
    make_legacy_deb(
        "$tmp/rebuilt-legacy-deb",
        "$staged/xcat-genesis-base-amd64_1_all.deb",
        'rebuilt repository test package',
    );
    my $replace_log = "$tmp/deb-replace.log";
    my $replace_status = run_apt_consumer(
        log => $replace_log, output => $output, apt_dir => $apt_root,
        dists => ['noble'],
    );
    is($replace_status, 0, 'a rebuilt DEB may keep its published filename');
    isnt(digest_file($legacy_pool), $legacy_before,
        'the rebuilt DEB replaces the earlier package');

    # A staged package under a release package's own name is dropped, not published.
    my $collision = "$tmp/apt-collision";
    my $collision_output = "$tmp/deb-collision-output";
    my $collision_staged = stage_apt_suites($collision_output, "$tmp/collision-deb");
    write_binary("$collision_staged/$package", 'different');
    my $collision_log = "$tmp/deb-collision.log";
    my $collision_status = run_apt_consumer(
        log => $collision_log, output => $collision_output, apt_dir => $collision,
        extra => [ '--genesis-release', $release_root ],
    );
    is($collision_status, 0, 'verified release replaces a stale staged package');
    is(digest_file("$collision/pool/main/xcat-genesis-openembedded/$package"),
        digest_file("$release_root/deb/$package"),
        'pooled package still matches the verified release');
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
    like(read_binary("$common/xcat-dep-common.repo"), qr/^repo_gpgcheck=1$/m,
        'the signed common repository requires metadata verification');
    like(read_binary("$common/xcat-dep-common.repo"), qr/^skip_if_unavailable=1$/m,
        'the signed common repository remains optional during outages');
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
    my $output = "$tmp/deb-legacy-output";
    stage_legacy_deb("$tmp/legacy-dummy-deb", $output);

    local $ENV{SOURCE_DATE_EPOCH} = $epoch;
    my $log = "$tmp/deb-legacy-consumer.log";
    my $status = run_apt_consumer(log => $log, output => $output, apt_dir => $apt_root);
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
    my $output = "$tmp/deb-partial-output";
    my $pool = "$apt_root/pool/main/noble";
    my $existing = "$pool/xcat-genesis-base-existing.deb";
    stage_legacy_deb("$tmp/partial-deb", $output);
    make_path($pool);
    write_binary($existing, 'existing release');

    my $log = "$tmp/deb-partial.log";
    my $status = run_apt_consumer(
        log => $log, output => $output, apt_dir => $apt_root,
        extra => [ '--genesis-release', $release_root ],
    );

    isnt($status, 0, 'APT repository rejects a partial Genesis release');
    like(read_binary($log), qr/Genesis release is missing supported architectures/,
        'APT partial-release failure names the missing architectures');
    ok(-f $existing, 'partial DEB release does not remove the published package');
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

sub test_rpm_repository_lock {
    my $output = "$tmp/rpm-lock-output";
    my $repository = "$tmp/rpm-shared-repository";
    make_path("$repository/.lock");
    write_binary("$repository/.lock/owner", "host=other\npid=1\nepoch=1\n");

    my @perl_lib;
    push(@perl_lib, write_forkmanager_stub("$tmp/perl-lock-stub"))
      unless eval { require Parallel::ForkManager; 1 };
    push(@perl_lib, $ENV{PERL5LIB})
      if defined($ENV{PERL5LIB}) && $ENV{PERL5LIB} ne '';
    local $ENV{PERL5LIB} = join(':', @perl_lib);

    my $log = "$tmp/rpm-repository-lock.log";
    my $status = run_capture(
        $log,
        $^X, $rpm_consumer,
        '--repo-root', $repo_root,
        '--output', $output,
        '--repo-dep', $repository,
        '--target', 'test+epel-10-' . capture_command('uname', '-m'),
        '--skip-build', '--skip-xcat', '--skip-xcat-dep', '--skip-perl',
        '--skip-createrepo', '--skip-tarball', '--dry-run',
    );
    isnt($status, 0, 'a shared RPM repository cannot have two publishers');
    like(read_binary($log), qr/repository \Q$repository\E is locked/,
        'the lock failure names the shared repository');

    my $backup = "$repository/.common.previous.999";
    my $staging = "$repository/.common.abandoned";
    make_path($backup, $staging);
    write_binary("$backup/marker", "previous repository\n");
    my $forced_log = "$tmp/rpm-repository-force.log";
    my $forced_status = run_capture(
        $forced_log,
        $^X, $rpm_consumer,
        '--repo-root', $repo_root,
        '--output', "$tmp/rpm-force-output",
        '--repo-dep', $repository,
        '--target', 'test+epel-10-' . capture_command('uname', '-m'),
        '--skip-build', '--skip-xcat', '--skip-xcat-dep', '--skip-perl',
        '--skip-createrepo', '--skip-tarball', '--dry-run', '--force-unlock',
    );
    is($forced_status, 0, '--force-unlock recovers an interrupted RPM publication');
    ok(-f "$repository/common/marker",
        'the interrupted common repository is restored before publication');
    ok(!-d $staging, 'abandoned common repository staging is removed');
}

sub test_rpm_signal_cleanup {
    my $output = "$tmp/rpm-signal-output";
    my $repository = "$tmp/rpm-signal-repository";
    my $signal_bin = "$tmp/rpm-signal-bin";
    my $log = "$tmp/rpm-signal.log";
    make_path($repository, $signal_bin);
    write_binary(
        "$signal_bin/uname",
        "#!/bin/sh\n"
          . "if [ \"\$1\" = -m ]; then sleep 60; exit 1; fi\n"
          . "exec /usr/bin/uname \"\$@\"\n",
    );
    chmod(0755, "$signal_bin/uname") or die $!;

    my $pid = fork();
    die "Cannot fork signal test: $!" unless defined($pid);
    if ($pid == 0) {
        POSIX::setpgid(0, 0);
        local $ENV{PATH} = "$signal_bin:$ENV{PATH}";
        open(STDOUT, '>', $log) or die "open $log: $!";
        open(STDERR, '>&', fileno(STDOUT)) or die "redirect stderr: $!";
        exec(
            $^X, $rpm_consumer,
            '--repo-root', $repo_root,
            '--xcat-source', $repo_root,
            '--output', $output,
            '--repo-dep', $repository,
            '--target', 'test+epel-10-x86_64',
            '--skip-build', '--skip-xcat', '--skip-xcat-dep', '--skip-perl',
            '--skip-createrepo', '--skip-tarball', '--dry-run',
        );
        exit 127;
    }

    my $locked = 0;
    for (1 .. 200) {
        if (-d "$output/.lock" && -d "$repository/.lock") {
            $locked = 1;
            last;
        }
        sleep(0.05);
    }
    ok($locked, 'the signal test reaches the locked publication phase');
    kill('TERM', -$pid);
    waitpid($pid, 0);
    is($? >> 8, 1, 'SIGTERM follows the publisher cleanup exit path');
    ok(!-d "$output/.lock", 'SIGTERM releases the output lock');
    ok(!-d "$repository/.lock", 'SIGTERM releases the repository lock');
}

sub test_publish_lock {
    my $apt_root = "$tmp/apt-lock";
    my $output = "$tmp/deb-lock-output";
    stage_legacy_deb("$tmp/lock-deb", $output);
    make_path($output);

    my $lockfile = "$output/.sbuild-all.publish.lock";
    open(my $held, '>', $lockfile) or die "Cannot create $lockfile: $!\n";
    flock($held, LOCK_EX | LOCK_NB) or die "Cannot hold $lockfile: $!\n";

    my $locked_log = "$tmp/deb-locked.log";
    my $locked_status = run_apt_consumer(
        log => $locked_log, output => $output, apt_dir => $apt_root,
        extra => [ '--publish-lock-wait', '2' ],
    );
    isnt($locked_status, 0, 'a locked apt tree is not published into');
    like(read_binary($locked_log), qr/waiting for the publish lock \Q$lockfile\E/,
        'the refusal names the lock another run owns');
    ok(!-d "$apt_root/dists", 'nothing is published while another run holds the lock');

    close($held);

    # sbuild-all.pl never publishes in place: it assembles a COMPLETE side tree and renames it onto
    # the repository, so there is no half-written state to recover and no per-file backup to restore.
    # A side tree left by a run that died is simply inert -- the next run builds and publishes its own.
    my $abandoned = "$apt_root.publish-abandoned.999";
    make_path("$abandoned/dists/noble");
    write_binary("$abandoned/dists/noble/Release", "abandoned\n");

    my $freed_log = "$tmp/deb-freed.log";
    my $freed_status = run_apt_consumer(
        log => $freed_log, output => $output, apt_dir => $apt_root, dists => ['noble']);
    is($freed_status, 0, 'the publish runs once the lock is released');
    ok(-f "$apt_root/dists/noble/Release", 'the released lock lets the tree be published');
    isnt(read_binary("$apt_root/dists/noble/Release"), "abandoned\n",
        'a side tree abandoned by a dead run is never published');
}

sub test_activation_helper {
    my $activation = read_binary("$repo_root/genesis-openembedded/activate");
    unlike($activation, qr/XCAT_GENESIS_ROOT/,
        'the root package helper has no environment-controlled execution root');
    $activation =~ s/\ngenesis_activation_main "\$\@"\s*\z/\n/
      or BAIL_OUT('the activation helper has no reusable main boundary');

    my $driver = "$tmp/activation-driver";
    my $log = "$tmp/activation.log";
    my $output = "$tmp/activation-output.log";
    write_binary(
        $driver,
        $activation
          . <<'SH',
genesis_is_host_root() { return 0; }
genesis_mknb_exists() { return 0; }
genesis_is_service_node() { [ "${XCAT_TEST_SERVICE_NODE:-0}" = 1 ]; }
genesis_uses_shared_tftp() { [ "${XCAT_TEST_SHAREDTFTP:-0}" = 1 ]; }
genesis_run_mknb() {
    printf '%s\n' "$1" >>"$XCAT_TEST_LOG"
    return "${XCAT_TEST_MKNB_STATUS:-0}"
}
genesis_activation_main "$@"
SH
    );
    chmod(0755, $driver) or die "Cannot make activation driver executable: $!";

    local $ENV{XCAT_TEST_LOG} = $log;
    my $status = run_capture($output, $driver, 'x86_64');
    is($status, 0, 'the activation helper accepts a local-TFTP node');
    is(read_binary($log), "x86_64\n", 'the activation helper runs mknb for one architecture');

    write_binary($log, '');
    local $ENV{XCAT_TEST_SERVICE_NODE} = 1;
    local $ENV{XCAT_TEST_SHAREDTFTP} = 1;
    $status = run_capture($output, $driver, 'ppc64le');
    is($status, 0, 'a shared-TFTP service node is accepted');
    is(read_binary($log), '', 'a shared-TFTP service node does not rebuild Genesis');

    local $ENV{XCAT_TEST_SERVICE_NODE} = 0;
    local $ENV{XCAT_TEST_MKNB_STATUS} = 1;
    $status = run_capture($output, $driver, 'ppc64le');
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
    my ($root, $output, $description) = @_;
    $description //= 'repository test package';
    make_path("$root/DEBIAN");
    write_binary(
        "$root/DEBIAN/control",
        "Package: xcat-genesis-base-amd64\nVersion: 1\nArchitecture: all\n"
          . "Maintainer: xCAT <xcat-user\@lists.sourceforge.net>\n"
          . "Description: $description\n",
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
