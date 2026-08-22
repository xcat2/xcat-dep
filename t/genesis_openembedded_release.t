use strict;
use warnings;

use Cwd qw(abs_path);
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
  validated_release_checksums
  validate_architecture
  validate_complete_release
  validate_export
  validate_release
  verify_release_file
);
use XCAT::GenesisReleaseTest qw(
  command_exists
  copy_tree
  dies_like
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
my $builder = "$repo_root/genesis-openembedded/build";
my $verifier = "$repo_root/genesis-openembedded/verify-release";
my $revision = 'a' x 40;
my $version = '2.19.0';
my $release = 'snap202608210726';
my $epoch = 1787293573;

is_deeply(
    [ architectures() ],
    [ qw(x86 x86_64 ppc64 ppc64le armv7hf aarch64 riscv64) ],
    'supported architectures keep their exact xCAT names',
);
is(rpm_package_name('ppc64le'), 'xCAT-genesis-base-ppc64le',
    'RPM package keeps ppc64le distinct');
is(deb_package_name('x86_64'), 'xcat-genesis-base-x86-64',
    'DEB package uses a legal spelling of x86_64');
dies_like(sub { validate_architecture('ppc') }, qr/Unsupported Genesis architecture/,
    'legacy ppc alias is rejected');

my $tmp = tempdir(CLEANUP => 1);
my $export = make_export("$tmp/export", 'x86_64');
ok(validate_export($export, 'x86_64'), 'valid export passes');
dies_like(sub { validate_export($export, 'ppc64le') }, qr/architecture mismatch/,
    'wrong architecture fails');

my $missing = make_export("$tmp/missing", 'x86_64');
unlink("$missing/image.vex.json") or die $!;
write_checksums($missing);
dies_like(sub { validate_export($missing, 'x86_64') }, qr/missing image\.vex\.json/,
    'missing release evidence fails');

my $corrupt = make_export("$tmp/corrupt", 'x86_64');
write_file("$corrupt/kernel", 'changed');
dies_like(sub { validate_export($corrupt, 'x86_64') }, qr/Checksum mismatch for kernel/,
    'corrupt payload fails');

my $unexpected = make_export("$tmp/unexpected", 'x86_64');
write_file("$unexpected/extra", 'not part of the export');
write_checksums($unexpected);
dies_like(sub { validate_export($unexpected, 'x86_64') }, qr/Unexpected Genesis export file/,
    'unlisted export files fail');

my $linked = make_export("$tmp/linked", 'x86_64');
unlink("$linked/kernel") or die $!;
symlink('initramfs.cpio.gz', "$linked/kernel") or die $!;
dies_like(sub { validate_export($linked, 'x86_64') }, qr/Symbolic links are not allowed/,
    'export symlinks fail');

my $riscv = make_export("$tmp/riscv", 'riscv64');
ok(-f "$riscv/fw_jump.elf", 'RISC-V export carries firmware');
ok(validate_export($riscv, 'riscv64'), 'RISC-V export passes');

my $release_dir = "$tmp/release";
make_path("$release_dir/rpm", "$release_dir/srpm", "$release_dir/deb");
for my $architecture (qw(x86_64 ppc64le)) {
    my $rpm = rpm_package_name($architecture);
    my $deb = deb_package_name($architecture);
    write_file("$release_dir/rpm/$rpm-$version-$release.noarch.rpm", "rpm $architecture");
    write_file("$release_dir/srpm/$rpm-$version-$release.src.rpm", "srpm $architecture");
    write_file("$release_dir/deb/${deb}_${version}-${release}_all.deb", "deb $architecture");
}
write_release_manifest(
    $release_dir, $version, $release, $revision, $epoch,
    'x86_64,ppc64le', 'deb,rpm',
);
write_checksums($release_dir);
my $manifest = validate_release($release_dir);
is($manifest->{xcat_revision}, $revision, 'release records xcat-core revision');
my $qualified_release = "$tmp/qualified-release";
my $qualified_release_name = '1+deb~1';
my $qualified_deb = deb_package_name('x86_64');
make_path("$qualified_release/deb");
write_file(
    "$qualified_release/deb/${qualified_deb}_${version}-${qualified_release_name}_all.deb",
    'deb x86_64',
);
write_release_manifest(
    $qualified_release, $version, $qualified_release_name, $revision, $epoch,
    'x86_64', 'deb',
);
write_checksums($qualified_release);
ok(validate_release($qualified_release), 'package filenames accept valid release qualifiers');
my $verified_checksums = validated_release_checksums($release_dir);
my $verified_relative = "rpm/xCAT-genesis-base-x86_64-$version-$release.noarch.rpm";
my $verified_copy = "$tmp/verified-copy.rpm";
copy("$release_dir/$verified_relative", $verified_copy) or die $!;
ok(verify_release_file($verified_checksums, $verified_relative, $verified_copy),
    'collected package matches the verified release');
write_file($verified_copy, 'changed after verification');
dies_like(
    sub { verify_release_file($verified_checksums, $verified_relative, $verified_copy) },
    qr/Collected release file checksum mismatch/,
    'release changes after verification are rejected',
);
dies_like(
    sub { validate_complete_release($release_dir) },
    qr/Genesis release is missing supported architectures/,
    'partial release cannot be published',
);

my $complete_release = "$tmp/complete-release";
make_path("$complete_release/rpm", "$complete_release/srpm", "$complete_release/deb");
for my $architecture (architectures()) {
    my $rpm = rpm_package_name($architecture);
    my $deb = deb_package_name($architecture);
    write_file("$complete_release/rpm/$rpm-$version-$release.noarch.rpm", "rpm $architecture");
    write_file("$complete_release/srpm/$rpm-$version-$release.src.rpm", "srpm $architecture");
    write_file("$complete_release/deb/${deb}_${version}-${release}_all.deb", "deb $architecture");
}
write_release_manifest(
    $complete_release, $version, $release, $revision, $epoch,
    join(',', architectures()), 'deb,rpm',
);
write_checksums($complete_release);
ok(validate_complete_release($complete_release), 'complete release can be published');

my $deb_only_release = "$tmp/deb-only-release";
make_path("$deb_only_release/deb");
for my $architecture (architectures()) {
    my $deb = deb_package_name($architecture);
    write_file("$deb_only_release/deb/${deb}_${version}-${release}_all.deb", "deb $architecture");
}
write_release_manifest(
    $deb_only_release, $version, $release, $revision, $epoch,
    join(',', architectures()), 'deb',
);
write_checksums($deb_only_release);
my $verify_all_log = "$tmp/verify-all.log";
isnt(run_capture($verify_all_log, $verifier, $deb_only_release), 0,
    'all-format verification rejects a single-format release');
like(read_file($verify_all_log), qr/Release does not contain rpm packages/,
    'all-format failure names the missing format');

my $bad_release = "$tmp/bad-release";
copy_tree($release_dir, $bad_release);
write_file("$bad_release/rpm/stale.rpm", 'stale');
write_checksums($bad_release);
dies_like(sub { validate_release($bad_release) }, qr/Unexpected Genesis release artifact/,
    'stale package fails');

my $missing_release = "$tmp/missing-release";
copy_tree($release_dir, $missing_release);
unlink("$missing_release/rpm/xCAT-genesis-base-ppc64le-$version-$release.noarch.rpm") or die $!;
write_checksums($missing_release);
dies_like(sub { validate_release($missing_release) }, qr/Genesis release is missing/,
    'incomplete architecture set fails');

SKIP: {
    skip 'git is not installed', 2 unless command_exists('git');
    my $source = "$tmp/dirty-xcat-core";
    make_path("$source/xCAT-genesis-builder/oe");
    write_file("$source/Version", "$version\n");
    write_file("$source/xCAT-genesis-builder/oe/build", "#!/bin/sh\nexit 99\n");
    write_file("$source/xCAT-genesis-builder/oe/export", "#!/bin/sh\nexit 99\n");
    for my $command (
        [ 'git', '-C', $source, 'init', '-q' ],
        [ 'git', '-C', $source, 'add', '.' ],
        [ 'git', '-C', $source, '-c', 'user.name=xCAT test',
          '-c', 'user.email=xcat-test@example.invalid', 'commit', '-qm', 'fixture' ],
    ) {
        die "Cannot prepare test repository\n"
          if run_capture("$tmp/git-fixture.log", @{$command});
    }
    write_file("$source/untracked", "not part of the commit\n");
    my $log = "$tmp/dirty-source.log";
    isnt(
        run_capture(
            $log, $builder, '--xcat-source', $source,
            '--output-dir', "$tmp/dirty-output",
        ),
        0,
        'release builder rejects untracked source files',
    );
    like(read_file($log), qr/xcat-core checkout is not clean/,
        'dirty checkout failure is explicit');
}

SKIP: {
    skip 'rpmbuild and rpm are not installed', 8
      unless command_exists('rpmbuild') && command_exists('rpm');
    exercise_packager('rpm');
}

SKIP: {
    skip 'rpmbuild and rpm are not installed', 2
      unless command_exists('rpmbuild') && command_exists('rpm');
    skip 'root can traverse an unsearchable working directory', 2 if $> == 0;
    exercise_packager_from_unsearchable_cwd();
}

SKIP: {
    skip 'dpkg-deb is not installed', 6 unless command_exists('dpkg-deb');
    exercise_packager('deb');
}

SKIP: {
    skip 'git and dpkg-deb are not installed', 4
      unless command_exists('git') && command_exists('dpkg-deb');
    exercise_builder_tmpdir();
}

done_testing();

sub exercise_packager {
    my ($format) = @_;
    my $first = "$tmp/$format-first";
    my $second = "$tmp/$format-second";
    my @command = (
        $packager,
        '--architecture', 'x86_64',
        '--export-dir', $export,
        '--version', $version,
        '--release', $release,
        '--revision', $revision,
        '--source-date-epoch', $epoch,
        '--format', $format,
    );

    my $original_umask = umask(0022);
    is(system(@command, '--output-dir', $first), 0,
        "$format package builds with umask 0022");
    umask(0002);
    is(system(@command, '--output-dir', $second), 0,
        "$format package rebuilds with umask 0002");
    umask($original_umask);

    my ($relative, $source_relative);
    if ($format eq 'rpm') {
        $relative = "rpm/xCAT-genesis-base-x86_64-$version-$release.noarch.rpm";
        $source_relative = "srpm/xCAT-genesis-base-x86_64-$version-$release.src.rpm";
    } else {
        $relative = "deb/xcat-genesis-base-x86-64_${version}-${release}_all.deb";
    }
    ok(-f "$first/$relative", "$format binary exists");
    is(file_sha("$first/$relative"), file_sha("$second/$relative"),
        "$format binary is reproducible across umasks");
    if ($format eq 'rpm') {
        ok(-f "$first/$source_relative", 'source RPM exists');
        is(file_sha("$first/$source_relative"), file_sha("$second/$source_relative"),
            'source RPM is reproducible across umasks');
    }

    my $release_root = "$tmp/$format-release";
    make_path($release_root);
    copy_tree($first, $release_root);
    write_release_manifest(
        $release_root, $version, $release, $revision, $epoch, 'x86_64', $format,
    );
    write_checksums($release_root);
    ok(validate_release($release_root), "$format release layout passes");
    is(system($verifier, '--format', $format, $release_root), 0,
        "$format package metadata passes");
}

sub exercise_packager_from_unsearchable_cwd {
    my $cwd = "$tmp/unsearchable-cwd";
    my $output = "$tmp/cwd-independent-rpm";
    my $log = "$tmp/cwd-independent-rpm.log";
    make_path($cwd);

    my $pid = fork();
    die "Cannot fork: $!\n" unless defined($pid);
    if ($pid == 0) {
        chdir($cwd) or die "Cannot enter test directory: $!\n";
        chmod(0000, $cwd) or die "Cannot restrict test directory: $!\n";
        open(STDOUT, '>:raw', $log) or die $!;
        open(STDERR, '>&', STDOUT) or die $!;
        exec(
            $packager,
            '--architecture', 'x86_64',
            '--export-dir', $export,
            '--output-dir', $output,
            '--version', $version,
            '--release', $release,
            '--revision', $revision,
            '--source-date-epoch', $epoch,
            '--format', 'rpm',
        ) or die "Cannot run packager: $!\n";
    }
    waitpid($pid, 0);
    my $status = $? >> 8;
    chmod(0700, $cwd) or die "Cannot restore test directory: $!\n";

    is($status, 0, 'RPM package ignores an inaccessible inherited working directory');
    ok(
        -f "$output/rpm/xCAT-genesis-base-x86_64-$version-$release.noarch.rpm",
        'RPM package is published from an inaccessible inherited working directory',
    );
}

sub exercise_builder_tmpdir {
    my $source = "$tmp/tmpdir-xcat-core";
    my $oe = "$source/xCAT-genesis-builder/oe";
    make_path($oe);
    write_file("$source/Version", "$version\n");
    write_file(
        "$oe/build",
        <<'BUILD',
#!/bin/sh
set -eu
expected=$XCAT_GENESIS_WORK_DIR/build/tmp
[ "${TMPDIR:-}" = "$expected" ] || exit 41
mkdir -p "$TMPDIR/deploy"
BUILD
    );
    write_file(
        "$oe/export",
        <<'EXPORT',
#!/bin/sh
set -eu
architecture=$1
deploy=$2
output=$3
[ "$deploy" = "$XCAT_GENESIS_WORK_DIR/build/tmp/deploy" ] || exit 42
mkdir -p "$output"
printf '%s\n' kernel >"$output/kernel"
printf '%s\n' initramfs >"$output/initramfs.cpio.gz"
printf '%s\n' packages >"$output/image.manifest"
printf '%s\n' '{}' >"$output/image.spdx.json"
printf '%s\n' '{}' >"$output/image.vex.json"
printf '%s\n' licenses >"$output/license.manifest"
printf 'format=xcat-genesis\nversion=1\narchitecture=%s\n' "$architecture" \
    >"$output/xcat-genesis.manifest"
(
    cd "$output"
    sha256sum -- * >SHA256SUMS
)
EXPORT
    );
    chmod(0755, "$oe/build", "$oe/export") or die $!;
    for my $command (
        [ 'git', '-C', $source, 'init', '-q' ],
        [ 'git', '-C', $source, 'add', '.' ],
        [ 'git', '-C', $source, '-c', 'user.name=xCAT test',
          '-c', 'user.email=xcat-test@example.invalid', 'commit', '-qm', 'fixture' ],
    ) {
        die "Cannot prepare test repository\n"
          if run_capture("$tmp/tmpdir-git.log", @{$command});
    }

    my $ambient_tmp = "$tmp/ambient-tmp";
    my $output = "$tmp/tmpdir-release";
    my $log = "$tmp/tmpdir-builder.log";
    make_path($ambient_tmp);
    my $status;
    {
        local $ENV{TMPDIR} = $ambient_tmp;
        $status = run_capture(
            $log, $builder, '--xcat-source', $source,
            '--output-dir', $output, '--format', 'deb',
        );
    }
    is($status, 0, 'release builder isolates the OpenEmbedded tmpdir');
    unlike(read_file($log), qr/Invalid OpenEmbedded deploy directory/,
        'release builder finds the configured deploy directory');
    my $built = validate_release($output);
    is($built->{architectures}, 'x86_64', 'isolated build keeps the target architecture');
    is($built->{formats}, 'deb', 'isolated build keeps the requested format');
}
