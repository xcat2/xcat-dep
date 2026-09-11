use strict;
use warnings;

use Cwd qw(abs_path);
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
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
  minimum_release_version
  rpm_package_name
  validated_release_checksums
  validate_architecture
  validate_complete_release
  validate_export
  validate_release
  verify_release_file
);
use XCAT::GenesisReleaseTest qw(
  copy_tree
  dies_like
  make_export
  run_capture
  write_checksums
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

if ($ENV{XCAT_GENESIS_CI}) {
    for my $command (qw(git dpkg-deb rpm rpmbuild tar)) {
        BAIL_OUT("CI requires $command") unless command_exists($command);
    }
}

is_deeply(
    [ architectures() ],
    [ qw(x86 x86_64 ppc64 ppc64le armv7hf aarch64 riscv64 s390x) ],
    'supported architectures keep their exact xCAT names',
);
is(rpm_package_name('ppc64le'), 'xCAT-genesis-openembedded-ppc64le',
    'RPM package keeps ppc64le distinct');
is(deb_package_name('x86_64'), 'xcat-genesis-openembedded-x86-64',
    'DEB package uses a legal spelling of x86_64');
is(minimum_release_version('x86_64'), 1,
    'legacy architectures use release format version 1');
is(minimum_release_version('x86_64', 's390x'), 2,
    's390x requires release format version 2');
dies_like(sub { minimum_release_version() }, qr/requires a Genesis architecture/,
    'release format selection requires an architecture');
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
write_binary("$corrupt/kernel", 'changed');
dies_like(sub { validate_export($corrupt, 'x86_64') }, qr/Checksum mismatch for kernel/,
    'corrupt payload fails');

my $unexpected = make_export("$tmp/unexpected", 'x86_64');
write_binary("$unexpected/extra", 'not part of the export');
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
    write_binary("$release_dir/rpm/$rpm-$version-$release.noarch.rpm", "rpm $architecture");
    write_binary("$release_dir/srpm/$rpm-$version-$release.src.rpm", "srpm $architecture");
    write_binary("$release_dir/deb/${deb}_${version}-${release}_all.deb", "deb $architecture");
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
write_binary(
    "$qualified_release/deb/${qualified_deb}_${version}-${qualified_release_name}_all.deb",
    'deb x86_64',
);
write_release_manifest(
    $qualified_release, $version, $qualified_release_name, $revision, $epoch,
    'x86_64', 'deb',
);
write_checksums($qualified_release);
ok(validate_release($qualified_release), 'package filenames accept valid release qualifiers');
my $checksum_reads = 0;
my $verified_checksums;
{
    no warnings 'redefine';
    my $reader = \&XCAT::GenesisRelease::read_checksum_manifest;
    local *XCAT::GenesisRelease::read_checksum_manifest = sub {
        $checksum_reads++;
        return $reader->(@_);
    };
    $verified_checksums = validated_release_checksums($release_dir);
}
is($checksum_reads, 1, 'validated checksums use the verified manifest read');
my $verified_relative = "rpm/xCAT-genesis-openembedded-x86_64-$version-$release.noarch.rpm";
my $verified_copy = "$tmp/verified-copy.rpm";
copy("$release_dir/$verified_relative", $verified_copy) or die $!;
ok(verify_release_file($verified_checksums, $verified_relative, $verified_copy),
    'collected package matches the verified release');
write_binary($verified_copy, 'changed after verification');
dies_like(
    sub { verify_release_file($verified_checksums, $verified_relative, $verified_copy) },
    qr/Collected release file checksum mismatch/,
    'release changes after verification are rejected',
);
copy("$release_dir/$verified_relative", $verified_copy) or die $!;
my $copied_file_log = "$tmp/copied-file.log";
is(
    run_capture(
        $copied_file_log,
        $verifier,
        '--checksum-file', "$release_dir/SHA256SUMS",
        '--relative-file', $verified_relative,
        '--copied-file', $verified_copy,
    ),
    0,
    'verifier accepts a copied release file',
);
write_binary($verified_copy, 'changed after verification');
isnt(
    run_capture(
        $copied_file_log,
        $verifier,
        '--checksum-file', "$release_dir/SHA256SUMS",
        '--relative-file', $verified_relative,
        '--copied-file', $verified_copy,
    ),
    0,
    'verifier rejects a changed copied file',
);
like(
    read_binary($copied_file_log),
    qr/Collected release file checksum mismatch/,
    'copied-file failure names the checksum mismatch',
);
dies_like(
    sub { validate_complete_release($release_dir) },
    qr/Genesis release version 2 omits currently supported architectures/,
    'partial release cannot be published',
);

my $complete_release = "$tmp/complete-release";
make_path("$complete_release/rpm", "$complete_release/srpm", "$complete_release/deb");
for my $architecture (architectures()) {
    my $rpm = rpm_package_name($architecture);
    my $deb = deb_package_name($architecture);
    write_binary("$complete_release/rpm/$rpm-$version-$release.noarch.rpm", "rpm $architecture");
    write_binary("$complete_release/srpm/$rpm-$version-$release.src.rpm", "srpm $architecture");
    write_binary("$complete_release/deb/${deb}_${version}-${release}_all.deb", "deb $architecture");
}
write_release_manifest(
    $complete_release, $version, $release, $revision, $epoch,
    join(',', architectures()), 'deb,rpm',
);
write_checksums($complete_release);
ok(validate_complete_release($complete_release), 'complete release can be published');

my $legacy_release = "$tmp/legacy-release";
copy_tree($complete_release, $legacy_release);
for my $directory (qw(rpm srpm deb)) {
    my @s390x_packages = glob("$legacy_release/$directory/*s390x*");
    unlink(@s390x_packages) == @s390x_packages
      or die "Cannot remove the s390x package fixture: $!\n";
}
write_release_manifest(
    $legacy_release, $version, $release, $revision, $epoch,
    'x86,x86_64,ppc64,ppc64le,armv7hf,aarch64,riscv64', 'deb,rpm', 1,
);
write_checksums($legacy_release);
ok(validate_release($legacy_release), 'version 1 releases remain readable');
dies_like(
    sub { validate_complete_release($legacy_release) },
    qr/Genesis release version 1 omits currently supported architectures: s390x/,
    'version 1 releases cannot replace the current repository',
);

my $invalid_legacy_release = "$tmp/invalid-legacy-release";
copy_tree($complete_release, $invalid_legacy_release);
write_release_manifest(
    $invalid_legacy_release, $version, $release, $revision, $epoch,
    join(',', architectures()), 'deb,rpm', 1,
);
write_checksums($invalid_legacy_release);
dies_like(
    sub { validate_release($invalid_legacy_release) },
    qr/Genesis architecture s390x is not valid in release version 1/,
    'version 1 rejects the version 2 architecture vocabulary',
);

my $unknown_release_version = "$tmp/unknown-release-version";
copy_tree($complete_release, $unknown_release_version);
write_release_manifest(
    $unknown_release_version, $version, $release, $revision, $epoch,
    join(',', architectures()), 'deb,rpm', 3,
);
write_checksums($unknown_release_version);
dies_like(sub { validate_release($unknown_release_version) },
    qr/Unsupported Genesis package release version/,
    'unknown release manifest versions fail');

my $deb_only_release = "$tmp/deb-only-release";
make_path("$deb_only_release/deb");
for my $architecture (architectures()) {
    my $deb = deb_package_name($architecture);
    write_binary("$deb_only_release/deb/${deb}_${version}-${release}_all.deb", "deb $architecture");
}
write_release_manifest(
    $deb_only_release, $version, $release, $revision, $epoch,
    join(',', architectures()), 'deb',
);
write_checksums($deb_only_release);
my $verify_all_log = "$tmp/verify-all.log";
isnt(run_capture($verify_all_log, $verifier, $deb_only_release), 0,
    'all-format verification rejects a single-format release');
like(read_binary($verify_all_log), qr/Release does not contain rpm packages/,
    'all-format failure names the missing format');

my $bad_release = "$tmp/bad-release";
copy_tree($release_dir, $bad_release);
write_binary("$bad_release/rpm/stale.rpm", 'stale');
write_checksums($bad_release);
dies_like(sub { validate_release($bad_release) }, qr/Unexpected Genesis release artifact/,
    'stale package fails');

my $missing_release = "$tmp/missing-release";
copy_tree($release_dir, $missing_release);
unlink("$missing_release/rpm/xCAT-genesis-openembedded-ppc64le-$version-$release.noarch.rpm") or die $!;
write_checksums($missing_release);
dies_like(sub { validate_release($missing_release) }, qr/Genesis release is missing/,
    'incomplete architecture set fails');

SKIP: {
    skip 'git is not installed', 13 unless command_exists('git');
    my $source = "$tmp/dirty-xcat-core";
    my $oe = "$source/xCAT-genesis-builder/oe";
    my $capability_marker = "$tmp/capability-query-ran";
    make_path($oe);
    write_binary("$source/Version", "$version\n");
    write_binary(
        "$source/xCAT-genesis-builder/oe/build",
        "#!/bin/sh\n"
          . "if [ \"\${1-}\" = --list-architectures ]; then\n"
          . "    [ -z \"\${XCAT_TEST_CAPABILITY_MARKER-}\" ] || : >\"\$XCAT_TEST_CAPABILITY_MARKER\"\n"
          . "    mkdir -p \"\${XCAT_GENESIS_WORK_DIR:?}\"\n"
          . "    printf '%s\\n' x86_64\n"
          . "    exit 0\n"
          . "fi\n"
          . "exit 99\n",
    );
    chmod(0755, "$source/xCAT-genesis-builder/oe/build")
      or die "Cannot make fixture build executable: $!";
    write_binary("$source/xCAT-genesis-builder/oe/export", "#!/bin/sh\nexit 99\n");
    for my $command (
        [ 'git', '-C', $source, 'init', '-q' ],
        [ 'git', '-C', $source, 'add', '.' ],
        [ 'git', '-C', $source, '-c', 'user.name=xCAT test',
          '-c', 'user.email=xcat-test@example.invalid', 'commit', '-qm', 'fixture' ],
    ) {
        die "Cannot prepare test repository\n"
          if run_capture("$tmp/git-fixture.log", @{$command});
    }
    my $previous_revision = capture_command('git', '-C', $source, 'rev-parse', 'HEAD');
    my $commit_source = sub {
        my ($path, $message) = @_;
        for my $command (
            [ 'git', '-C', $source, 'add', $path ],
            [ 'git', '-C', $source, '-c', 'user.name=xCAT test',
              '-c', 'user.email=xcat-test@example.invalid', 'commit', '-qm', $message ],
        ) {
            die "Cannot update test repository\n"
              if run_capture("$tmp/git-fixture.log", @{$command});
        }
    };
    write_binary("$source/untracked", "not part of the commit\n");
    my $log = "$tmp/dirty-source.log";
    {
        local $ENV{XCAT_TEST_CAPABILITY_MARKER} = $capability_marker;
        isnt(
            run_capture(
                $log, $builder, '--xcat-source', $source,
                '--architecture', 's390x',
                '--output-dir', "$tmp/dirty-output",
            ),
            0,
            'release builder rejects untracked source files',
        );
    }
    like(read_binary($log), qr/xcat-core checkout is not clean/,
        'dirty checkout failure is explicit');
    ok(!-e $capability_marker,
        'dirty source is rejected before its architecture helper runs');
    unlink("$source/untracked") or die "Cannot clean the source fixture: $!\n";

    write_binary("$source/revision-marker", "new revision\n");
    $commit_source->('revision-marker', 'advance source revision');
    my $ref_log = "$tmp/ref-mismatch.log";
    {
        local $ENV{XCAT_TEST_CAPABILITY_MARKER} = $capability_marker;
        isnt(
            run_capture(
                $ref_log, $builder, '--xcat-source', $source,
                '--xcat-ref', $previous_revision,
                '--architecture', 's390x',
                '--output-dir', "$tmp/ref-mismatch-output",
            ),
            0,
            'release builder rejects a mismatched xcat-core revision',
        );
    }
    like(read_binary($ref_log), qr/xcat-core HEAD .* does not match \Q$previous_revision\E/,
        'revision mismatch failure is explicit');
    ok(!-e $capability_marker,
        'revision mismatch is rejected before the architecture helper runs');

    my $target_log = "$tmp/missing-target.log";
    {
        local $ENV{XCAT_TEST_CAPABILITY_MARKER} = $capability_marker;
        isnt(
            run_capture(
                $target_log, $builder, '--xcat-source', $source,
                '--architecture', 's390x',
                '--output-dir', "$tmp/missing-target-output",
            ),
            0,
            'release builder rejects an unsupported xcat-core target',
        );
    }
    like(read_binary($target_log), qr/does not support Genesis architecture s390x/,
        'missing target failure identifies the required xcat-core support');
    ok(-e $capability_marker, 'the architecture helper records a successful query');

    write_binary("$oe/build", "#!/bin/sh\nexit 23\n");
    chmod(0755, "$oe/build") or die "Cannot update fixture build executable: $!";
    $commit_source->('xCAT-genesis-builder/oe/build', 'fail capability query');
    my $failed_log = "$tmp/failed-query.log";
    isnt(
        run_capture(
            $failed_log, $builder, '--xcat-source', $source,
            '--architecture', 's390x',
            '--output-dir', "$tmp/failed-query-output",
        ),
        0,
        'release builder rejects a failed architecture query',
    );
    like(read_binary($failed_log), qr/does not report supported Genesis architectures/,
        'failed architecture queries are reported');

    write_binary("$oe/build", "#!/bin/sh\nexit 0\n");
    chmod(0755, "$oe/build") or die "Cannot update fixture build executable: $!";
    $commit_source->('xCAT-genesis-builder/oe/build', 'empty capability query');
    my $empty_log = "$tmp/empty-query.log";
    isnt(
        run_capture(
            $empty_log, $builder, '--xcat-source', $source,
            '--architecture', 's390x',
            '--output-dir', "$tmp/empty-query-output",
        ),
        0,
        'release builder rejects an empty architecture query',
    );
    like(read_binary($empty_log), qr/reported no supported Genesis architectures/,
        'empty architecture queries are reported');
}

SKIP: {
    skip 'rpmbuild and rpm are not installed', 19
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
    skip 'dpkg-deb is not installed', 14 unless command_exists('dpkg-deb');
    exercise_packager('deb');
}

SKIP: {
    skip 'git and dpkg-deb are not installed', 9
      unless command_exists('git') && command_exists('dpkg-deb');
    exercise_builder_tmpdir();
}

done_testing();

sub exercise_packager {
    my ($format) = @_;
    my $first = "$tmp/$format-first";
    my $second = "$tmp/$format-second";
    my $package_revision = sprintf('%032x%08x', time, $$);
    my @command = (
        $packager,
        '--architecture', 'x86_64',
        '--export-dir', $export,
        '--version', $version,
        '--release', $release,
        '--revision', $package_revision,
        '--source-date-epoch', $epoch,
        '--format', $format,
    );
    my ($legacy_rpm_top, $legacy_rpm_work);
    if ($format eq 'rpm') {
        $legacy_rpm_top =
          "/var/tmp/xcat-genesis-rpmbuild-$package_revision-x86_64-$version-$release";
        $legacy_rpm_work = "$legacy_rpm_top/BUILD/stale";
        make_path("$legacy_rpm_top/BUILD");
        write_binary($legacy_rpm_work, 'stale work');
    }

    my $original_umask = umask(0022);
    is(system(@command, '--output-dir', $first), 0,
        "$format package builds with umask 0022");
    umask(0002);
    is(system(@command, '--output-dir', $second), 0,
        "$format package rebuilds with umask 0002");
    umask($original_umask);
    is(sprintf('%04o', (stat($first))[2] & 0x0fff), '0755',
        "$format output is readable and searchable");
    is(sprintf('%04o', (stat($second))[2] & 0x0fff), '0755',
        "$format rebuilt output is readable and searchable");
    if (defined($legacy_rpm_work)) {
        ok(-e $legacy_rpm_work, 'RPM package ignores the legacy fixed work path');
        remove_tree($legacy_rpm_top);
    }

    my ($relative, $source_relative);
    if ($format eq 'rpm') {
        $relative = "rpm/xCAT-genesis-openembedded-x86_64-$version-$release.noarch.rpm";
        $source_relative = "srpm/xCAT-genesis-openembedded-x86_64-$version-$release.src.rpm";
    } else {
        $relative = "deb/xcat-genesis-openembedded-x86-64_${version}-${release}_all.deb";
    }
    ok(-f "$first/$relative", "$format binary exists");
    is(digest_file("$first/$relative"), digest_file("$second/$relative"),
        "$format binary is reproducible across umasks");
    if ($format eq 'rpm') {
        ok(-f "$first/$source_relative", 'source RPM exists');
        is(digest_file("$first/$source_relative"), digest_file("$second/$source_relative"),
            'source RPM is reproducible across umasks');
    }

    my $release_root = "$tmp/$format-release";
    make_path($release_root);
    copy_tree($first, $release_root);
    write_release_manifest(
        $release_root, $version, $release, $package_revision, $epoch, 'x86_64', $format,
    );
    write_checksums($release_root);
    ok(validate_release($release_root), "$format release layout passes");
    is(system($verifier, '--format', $format, $release_root), 0,
        "$format package metadata passes");
    my $contents_log = "$tmp/$format-contents.log";
    if ($format eq 'rpm') {
        is(run_capture($contents_log, 'rpm', '-qpl', "$first/$relative"), 0,
            'RPM payload can be listed');
        like(read_binary($contents_log),
            qr{/opt/xcat/share/xcat/netboot/genesis-openembedded/x86_64/kernel},
            'RPM uses the OpenEmbedded staging namespace');
        like(read_binary($contents_log),
            qr{^/usr/share/doc/xCAT-genesis-openembedded-x86_64/?$}m,
            'RPM owns its documentation directory');
        my $ownership_log = "$tmp/rpm-ownership.log";
        is(
            run_capture(
                $ownership_log, 'rpm', '-qp',
                '--qf', '[%{FILEUSERNAME}:%{FILEGROUPNAME}\n]',
                "$first/$relative",
            ),
            0,
            'RPM file ownership can be read',
        );
        is_deeply(
            [ grep { $_ ne 'root:root' } split(/\n/, read_binary($ownership_log)) ],
            [],
            'RPM owns every payload path as root',
        );
        is(run_capture($contents_log, 'rpm', '-qp', '--scripts', "$first/$relative"), 0,
            'RPM script metadata can be read');
        like(
            read_binary($contents_log),
            qr{posttrans scriptlet.*\n/usr/libexec/xcat/genesis-openembedded-activate-x86_64 x86_64\n}s,
            'RPM refreshes the installed architecture after the transaction',
        );
        like(
            read_binary($contents_log),
            qr{postuninstall scriptlet.*mknb x86_64 --remove-openembedded}s,
            'RPM retires published artifacts after erasing the image',
        );
    } else {
        is(run_capture($contents_log, 'dpkg-deb', '-c', "$first/$relative"), 0,
            'DEB payload can be listed');
        like(read_binary($contents_log),
            qr{/opt/xcat/share/xcat/netboot/genesis-openembedded/x86_64/kernel},
            'DEB uses the OpenEmbedded staging namespace');
        my $control = "$tmp/deb-control";
        make_path($control);
        is(run_capture($contents_log, 'dpkg-deb', '-e', "$first/$relative", $control), 0,
            'DEB control files can be extracted');
        opendir(my $control_dh, $control) or die $!;
        my @control_files = sort grep { $_ ne '.' && $_ ne '..' } readdir($control_dh);
        closedir($control_dh) or die $!;
        is_deeply(\@control_files, [ qw(control md5sums postinst postrm) ],
            'DEB contains the expected installation and removal scripts');
        like(
            read_binary("$control/postinst"),
            qr{^#!/bin/sh\n/usr/libexec/xcat/genesis-openembedded-activate-x86_64 x86_64\nexit 0\n$},
            'DEB refreshes the installed architecture after configuration',
        );
        like(
            read_binary("$control/postrm"),
            qr{mknb x86_64 --remove-openembedded},
            'DEB retires published artifacts after erasing the image',
        );
    }
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
        -f "$output/rpm/xCAT-genesis-openembedded-x86_64-$version-$release.noarch.rpm",
        'RPM package is published from an inaccessible inherited working directory',
    );
}

sub exercise_builder_tmpdir {
    my $source = "$tmp/tmpdir-xcat-core";
    my $oe = "$source/xCAT-genesis-builder/oe";
    make_path($oe);
    write_binary("$source/Version", "$version\n");
    write_binary(
        "$oe/build",
        <<'BUILD',
#!/bin/sh
set -eu
if [ "${1-}" = --list-architectures ]; then
    printf '%s\n' x86_64 s390x
    exit 0
fi
expected=$XCAT_GENESIS_WORK_DIR/build/tmp
[ "${TMPDIR:-}" = "$expected" ] || exit 41
mkdir -p "$TMPDIR/deploy"
BUILD
    );
    write_binary(
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
    my $persistent_work = "$tmp/persistent-work";
    my $output = "$tmp/tmpdir-release";
    my $log = "$tmp/tmpdir-builder.log";
    make_path($ambient_tmp);
    my $status;
    {
        local $ENV{TMPDIR} = $ambient_tmp;
        $status = run_capture(
            $log, $builder, '--xcat-source', $source,
            '--output-dir', $output, '--work-dir', $persistent_work,
            '--format', 'deb', '--architecture', 's390x',
        );
    }
    is($status, 0, 'release builder isolates the OpenEmbedded tmpdir');
    unlike(read_binary($log), qr/Invalid OpenEmbedded deploy directory/,
        'release builder finds the configured deploy directory');
    ok(-d "$persistent_work/openembedded/build/tmp",
        'release builder preserves the requested work directory');
    is((stat($output))[2] & oct('07777'), oct('0755'),
        'release directory is readable by other users');
    my $built = validate_release($output);
    is($built->{architectures}, 's390x', 'isolated build keeps the target architecture');
    is($built->{formats}, 'deb', 'isolated build keeps the requested format');
    is($built->{version}, 2, 'a release containing s390x uses format version 2');

    my $legacy_output = "$tmp/tmpdir-legacy-release";
    my $legacy_log = "$tmp/tmpdir-legacy-builder.log";
    my $legacy_status = run_capture(
        $legacy_log, $builder, '--xcat-source', $source,
        '--output-dir', $legacy_output, '--work-dir', $persistent_work,
        '--format', 'deb', '--architecture', 'x86_64',
    );
    is($legacy_status, 0, 'release builder keeps legacy targets buildable');
    my $legacy = validate_release($legacy_output);
    is($legacy->{version}, 1, 'a release without s390x uses format version 1');
}
