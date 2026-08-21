package XCAT::GenesisReleaseTest;

use strict;
use warnings;

use Digest::SHA ();
use Exporter qw(import);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Spec;
use Test::More ();

our @EXPORT_OK = qw(
  command_exists
  copy_tree
  dies_like
  file_sha
  make_export
  write_checksums
  write_file
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
    write_file("$directory/$_", $content{$_}) for sort keys %content;
    write_checksums($directory);
    return $directory;
}

sub write_release_manifest {
    my ($directory, $xcat_version, $xcat_release, $revision, $epoch,
        $architectures, $formats) = @_;
    write_file(
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
    Test::More::like($error, $pattern, $name);
}

1;
