use strict;
use warnings;

use Cwd qw(abs_path);
use Digest::SHA ();
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../genesis-openembedded/lib";
use XCAT::GenesisRelease qw(
  architectures
  deb_package_name
  rpm_package_name
  validate_architecture
  validate_export
  validate_release
);

my $repo_root = abs_path("$FindBin::Bin/..");
my $packager = "$repo_root/genesis-openembedded/package";
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
write_release_manifest($release_dir, 'x86_64,ppc64le', 'deb,rpm');
write_checksums($release_dir);
my $manifest = validate_release($release_dir);
is($manifest->{xcat_revision}, $revision, 'release records xcat-core revision');

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
    skip 'rpmbuild and rpm are not installed', 8
      unless command_exists('rpmbuild') && command_exists('rpm');
    exercise_packager('rpm');
}

SKIP: {
    skip 'dpkg-deb is not installed', 8 unless command_exists('dpkg-deb');
    exercise_packager('deb');
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

    is(system(@command, '--output-dir', $first), 0, "$format package builds");
    is(system(@command, '--output-dir', $second), 0, "$format package rebuilds");

    my ($relative, $source_relative);
    if ($format eq 'rpm') {
        $relative = "rpm/xCAT-genesis-base-x86_64-$version-$release.noarch.rpm";
        $source_relative = "srpm/xCAT-genesis-base-x86_64-$version-$release.src.rpm";
    } else {
        $relative = "deb/xcat-genesis-base-x86-64_${version}-${release}_all.deb";
    }
    ok(-f "$first/$relative", "$format binary exists");
    is(file_sha("$first/$relative"), file_sha("$second/$relative"),
        "$format binary is reproducible");
    if ($format eq 'rpm') {
        ok(-f "$first/$source_relative", 'source RPM exists');
        is(file_sha("$first/$source_relative"), file_sha("$second/$source_relative"),
            'source RPM is reproducible');
    } else {
        pass('DEB has no separate source package');
        pass('DEB source is carried by the RPM source archive');
    }

    my $release_root = "$tmp/$format-release";
    make_path($release_root);
    copy_tree($first, $release_root);
    write_release_manifest($release_root, 'x86_64', $format);
    write_checksums($release_root);
    ok(validate_release($release_root), "$format release layout passes");
    is(system($verifier, '--format', $format, $release_root), 0,
        "$format package metadata passes");
}

sub make_export {
    my ($directory, $architecture) = @_;
    make_path($directory);
    my %content = (
        'kernel'                => 'kernel',
        'initramfs.cpio.gz'     => 'initramfs',
        'image.manifest'        => 'packages',
        'image.spdx.json'       => '{}',
        'image.vex.json'        => '{}',
        'license.manifest'      => 'licenses',
        'xcat-genesis.manifest' => "format=xcat-genesis\nversion=1\narchitecture=$architecture\n",
    );
    $content{'fw_jump.elf'} = 'firmware' if $architecture eq 'riscv64';
    write_file("$directory/$_", $content{$_}) for sort keys %content;
    write_checksums($directory);
    return $directory;
}

sub write_release_manifest {
    my ($directory, $architectures, $formats) = @_;
    write_file(
        "$directory/release.manifest",
        "format=xcat-genesis-packages\n"
          . "version=1\n"
          . "xcat_version=$version\n"
          . "xcat_release=$release\n"
          . "xcat_revision=$revision\n"
          . "source_date_epoch=$epoch\n"
          . "architectures=$architectures\n"
          . "formats=$formats\n",
    );
}

sub write_checksums {
    my ($directory) = @_;
    unlink("$directory/SHA256SUMS") if -e "$directory/SHA256SUMS";
    my @files;
    find(
        {
            no_chdir => 1,
            wanted   => sub {
                return unless -f $_ && !-l $_;
                my $relative = File::Spec->abs2rel($File::Find::name, $directory);
                $relative =~ tr{\\}{/};
                push(@files, $relative);
            },
        },
        $directory,
    );
    my $content = join('', map { file_sha("$directory/$_") . "  $_\n" } sort @files);
    write_file("$directory/SHA256SUMS", $content);
}

sub file_sha {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or die $!;
    my $digest = Digest::SHA->new(256)->addfile($fh)->hexdigest;
    close($fh) or die $!;
    return $digest;
}

sub copy_tree {
    my ($source, $destination) = @_;
    make_path($destination);
    find(
        {
            no_chdir => 1,
            wanted   => sub {
                return if $File::Find::name eq $source;
                my $relative = File::Spec->abs2rel($File::Find::name, $source);
                my $target = "$destination/$relative";
                if (-d $File::Find::name) {
                    make_path($target);
                } elsif (-f $File::Find::name) {
                    make_path(dirname($target));
                    copy($File::Find::name, $target) or die $!;
                }
            },
        },
        $source,
    );
}

sub write_file {
    my ($path, $content) = @_;
    open(my $fh, '>:raw', $path) or die $!;
    print {$fh} $content or die $!;
    close($fh) or die $!;
}

sub command_exists {
    my ($command) = @_;
    for my $directory (File::Spec->path()) {
        return 1 if -x "$directory/$command";
    }
    return 0;
}

sub dies_like {
    my ($code, $pattern, $name) = @_;
    my $error = '';
    eval { $code->(); 1 } or $error = $@;
    like($error, $pattern, $name);
}
