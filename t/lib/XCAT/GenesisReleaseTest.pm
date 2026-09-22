package XCAT::GenesisReleaseTest;

use strict;
use warnings;

use Exporter qw(import);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use Test::More ();
use XCAT::BuildUtils qw(
  digest_manifest
  relative_files
  write_binary
);
use XCAT::GenesisRelease qw(deb_package_name rpm_package_name);

our @EXPORT_OK = qw(
  build_package_release
  copy_tree
  dies_like
  make_export
  run_capture
  write_forkmanager_stub
  write_checksums
  write_release_manifest
);

sub build_package_release {
    my (%args) = @_;
    my $root = $args{root};
    my $format = $args{format};
    my @architectures = @{ $args{architectures} };
    my $release_root = "$root/release";

    make_path($release_root);
    for my $architecture (@architectures) {
        my $export = make_export("$root/exports/$architecture", $architecture);
        my $packages = "$root/packages/$architecture";
        die "Cannot package test release for $architecture\n"
          if run_capture(
            "$root/package-$architecture.log",
            $args{packager},
            '--architecture', $architecture,
            '--export-dir', $export,
            '--output-dir', $packages,
            '--version', $args{version},
            '--release', $args{release},
            '--revision', $args{revision},
            '--source-date-epoch', $args{epoch},
            '--format', $format,
        );
        if ($format eq 'rpm') {
            my $name = rpm_package_name($architecture);
            make_path("$release_root/rpm", "$release_root/srpm");
            copy(
                "$packages/rpm/$name-$args{version}-$args{release}.noarch.rpm",
                "$release_root/rpm/$name-$args{version}-$args{release}.noarch.rpm",
            ) or die $!;
            copy(
                "$packages/srpm/$name-$args{version}-$args{release}.src.rpm",
                "$release_root/srpm/$name-$args{version}-$args{release}.src.rpm",
            ) or die $!;
        } else {
            my $name = deb_package_name($architecture);
            make_path("$release_root/deb");
            copy(
                "$packages/deb/${name}_$args{version}-$args{release}_all.deb",
                "$release_root/deb/${name}_$args{version}-$args{release}_all.deb",
            ) or die $!;
        }
    }
    write_release_manifest(
        $release_root, $args{version}, $args{release}, $args{revision},
        $args{epoch}, join(',', @architectures), $format,
    );
    write_checksums($release_root);
    return $release_root;
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
        'xcat-genesis.manifest' =>
          "format=xcat-genesis\nversion=1\narchitecture=$architecture\n",
    );
    $content{'fw_jump.elf'} = 'firmware' if $architecture eq 'riscv64';
    write_binary("$directory/$_", $content{$_}) for sort keys %content;
    write_checksums($directory);
    return $directory;
}

sub write_release_manifest {
    my ($directory, $xcat_version, $xcat_release, $revision, $epoch,
        $architectures, $formats, $manifest_version) = @_;
    $manifest_version //= 2;
    write_binary(
        "$directory/release.manifest",
        "format=xcat-genesis-packages\n"
          . "version=$manifest_version\n"
          . "xcat_version=$xcat_version\n"
          . "xcat_release=$xcat_release\n"
          . "xcat_revision=$revision\n"
          . "source_date_epoch=$epoch\n"
          . "architectures=$architectures\n"
          . "formats=$formats\n",
    );
}

sub write_checksums {
    my ($directory) = @_;
    unlink("$directory/SHA256SUMS") if -e "$directory/SHA256SUMS";
    my @files = relative_files($directory);
    write_binary(
        "$directory/SHA256SUMS",
        digest_manifest($directory, 'sha256', @files),
    );
}

sub copy_tree {
    my ($source, $destination) = @_;
    make_path($destination);
    for my $relative (relative_files($source)) {
        my $target = "$destination/$relative";
        make_path(dirname($target));
        copy("$source/$relative", $target) or die $!;
    }
}

sub write_forkmanager_stub {
    my ($root) = @_;
    my $stub = "$root/Parallel/ForkManager.pm";
    make_path("$root/Parallel");
    write_binary(
        $stub,
        "package Parallel::ForkManager;\n"
          . "sub new { bless {}, shift }\n"
          . "sub run_on_finish { \$_[0]->{callback} = \$_[1] }\n"
          . "sub start { 0 }\n"
          . "sub finish { my (\$self, \$exit) = \@_; "
          . "\$self->{callback}->(\$\$, \$exit, undef, 0, 0) if \$self->{callback}; 0 }\n"
          . "sub wait_all_children { 0 }\n1;\n",
    );
    return $root;
}

sub run_capture {
    my ($log, @command) = @_;
    my $pid = fork();
    die "Cannot fork: $!\n" unless defined $pid;
    if ($pid == 0) {
        open(STDOUT, '>:raw', $log) or die $!;
        open(STDERR, '>&', STDOUT) or die $!;
        exec(@command) or die "Cannot run $command[0]: $!\n";
    }
    waitpid($pid, 0);
    return 255 if $? == -1;
    return 128 + ($? & 127) if $? & 127;
    return $? >> 8;
}

sub dies_like {
    my ($code, $pattern, $name) = @_;
    my $error = '';
    eval { $code->(); 1 } or $error = $@;
    Test::More::like($error, $pattern, $name);
}

1;
