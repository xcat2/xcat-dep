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

our @EXPORT_OK = qw(
  copy_tree
  dies_like
  make_export
  run_capture
  write_checksums
  write_release_manifest
);

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
        $architectures, $formats) = @_;
    write_binary(
        "$directory/release.manifest",
        "format=xcat-genesis-packages\n"
          . "version=1\n"
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
