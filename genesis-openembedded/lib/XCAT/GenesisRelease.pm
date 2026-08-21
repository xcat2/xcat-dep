package XCAT::GenesisRelease;

use strict;
use warnings;

use Digest::SHA ();
use Exporter qw(import);
use File::Find qw(find);
use File::Spec;

our @EXPORT_OK = qw(
  architectures
  deb_package_name
  read_release_manifest
  rpm_package_name
  validate_architecture
  validate_export
  validate_release
);

my @ARCHITECTURES = qw(x86 x86_64 ppc64 ppc64le armv7hf aarch64 riscv64);
my %ARCHITECTURE = map { $_ => 1 } @ARCHITECTURES;

sub architectures {
    return @ARCHITECTURES;
}

sub validate_architecture {
    my ($architecture) = @_;
    die "Unsupported Genesis architecture: $architecture\n"
      unless defined($architecture) && $ARCHITECTURE{$architecture};
    return $architecture;
}

sub rpm_package_name {
    my ($architecture) = @_;
    validate_architecture($architecture);
    return "xCAT-genesis-base-$architecture";
}

sub deb_package_name {
    my ($architecture) = @_;
    validate_architecture($architecture);
    $architecture =~ tr/_/-/;
    return "xcat-genesis-base-$architecture";
}

sub _read_key_values {
    my ($path, $allowed) = @_;
    open(my $fh, '<:raw', $path) or die "Cannot read $path: $!\n";
    my %values;
    while (my $line = <$fh>) {
        chomp($line);
        $line =~ s/\r\z//;
        die "Invalid manifest entry in $path: $line\n"
          unless $line =~ /^([a-z][a-z0-9_]*)=([A-Za-z0-9][A-Za-z0-9.,_+~-]*)$/;
        my ($key, $value) = ($1, $2);
        die "Unknown manifest key in $path: $key\n" unless $allowed->{$key};
        die "Duplicate manifest key in $path: $key\n" if exists($values{$key});
        $values{$key} = $value;
    }
    close($fh) or die "Cannot close $path: $!\n";
    return \%values;
}

sub _regular_files {
    my ($root) = @_;
    die "Invalid directory: $root\n" unless -d $root && !-l $root;

    my @files;
    find(
        {
            no_chdir => 1,
            wanted   => sub {
                my $path = $File::Find::name;
                return if $path eq $root;
                die "Symbolic links are not allowed: $path\n" if -l $path;
                return if -d $path;
                die "Non-regular release entry: $path\n" unless -f $path;
                my $relative = File::Spec->abs2rel($path, $root);
                $relative =~ tr{\\}{/};
                push(@files, $relative);
            },
        },
        $root,
    );
    my @sorted = sort @files;
    return @sorted;
}

sub _read_checksums {
    my ($root) = @_;
    my $path = "$root/SHA256SUMS";
    open(my $fh, '<:raw', $path) or die "Cannot read $path: $!\n";
    my %checksums;
    while (my $line = <$fh>) {
        chomp($line);
        $line =~ s/\r\z//;
        die "Invalid checksum entry in $path: $line\n"
          unless $line =~ /^([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._\/-]*)$/;
        my ($digest, $name) = ($1, $2);
        die "Unsafe checksum path in $path: $name\n"
          if $name =~ m{(?:\A|/)\.\.(?:/|\z)} || $name =~ m{//};
        die "Duplicate checksum entry in $path: $name\n"
          if exists($checksums{$name});
        $checksums{$name} = $digest;
    }
    close($fh) or die "Cannot close $path: $!\n";
    return \%checksums;
}

sub _verify_checksums {
    my ($root) = @_;
    my @files = grep { $_ ne 'SHA256SUMS' } _regular_files($root);
    my $checksums = _read_checksums($root);

    my %files = map { $_ => 1 } @files;
    for my $name (@files) {
        die "Missing checksum for $name\n" unless exists($checksums->{$name});
        open(my $fh, '<:raw', "$root/$name") or die "Cannot read $root/$name: $!\n";
        my $digest = Digest::SHA->new(256)->addfile($fh)->hexdigest;
        close($fh) or die "Cannot close $root/$name: $!\n";
        die "Checksum mismatch for $name\n" unless $digest eq $checksums->{$name};
    }
    for my $name (keys %{$checksums}) {
        die "Checksum names a missing file: $name\n" unless $files{$name};
    }
    return 1;
}

sub validate_export {
    my ($directory, $architecture) = @_;
    validate_architecture($architecture);
    die "Invalid Genesis export: $directory\n" unless -d $directory && !-l $directory;

    my %required = map { $_ => 1 } qw(
      SHA256SUMS
      image.manifest
      image.spdx.json
      image.vex.json
      initramfs.cpio.gz
      kernel
      license.manifest
      xcat-genesis.manifest
    );
    $required{'fw_jump.elf'} = 1 if $architecture eq 'riscv64';

    my @files = _regular_files($directory);
    my %files = map { $_ => 1 } @files;
    for my $name (sort keys %required) {
        die "Genesis export is missing $name\n" unless $files{$name};
    }
    for my $name (@files) {
        die "Unexpected Genesis export file: $name\n" unless $required{$name};
    }

    my $manifest = _read_key_values(
        "$directory/xcat-genesis.manifest",
        { map { $_ => 1 } qw(format version architecture) },
    );
    die "Unsupported Genesis export format\n"
      unless ($manifest->{format} // '') eq 'xcat-genesis';
    die "Unsupported Genesis export version\n"
      unless ($manifest->{version} // '') eq '1';
    die "Genesis export architecture mismatch\n"
      unless ($manifest->{architecture} // '') eq $architecture;

    _verify_checksums($directory);
    return 1;
}

sub read_release_manifest {
    my ($directory) = @_;
    my $values = _read_key_values(
        "$directory/release.manifest",
        {
            map { $_ => 1 } qw(
              format version xcat_version xcat_release xcat_revision
              source_date_epoch architectures formats
            )
        },
    );
    for my $key (qw(format version xcat_version xcat_release xcat_revision source_date_epoch architectures formats)) {
        die "Release manifest is missing $key\n" unless exists($values->{$key});
    }
    return $values;
}

sub validate_release {
    my ($directory) = @_;
    die "Invalid Genesis package release: $directory\n"
      unless -d $directory && !-l $directory;

    my $manifest = read_release_manifest($directory);
    die "Unsupported Genesis package release format\n"
      unless $manifest->{format} eq 'xcat-genesis-packages';
    die "Unsupported Genesis package release version\n"
      unless $manifest->{version} eq '1';
    die "Invalid xCAT version in release manifest\n"
      unless $manifest->{xcat_version} =~ /^\d+(?:\.\d+){1,3}$/;
    die "Invalid xCAT release in release manifest\n"
      unless $manifest->{xcat_release} =~ /^[A-Za-z0-9][A-Za-z0-9.+~]*$/;
    die "Invalid xCAT revision in release manifest\n"
      unless $manifest->{xcat_revision} =~ /^[0-9a-f]{40}$/;
    die "Invalid source epoch in release manifest\n"
      unless $manifest->{source_date_epoch} =~ /^\d+$/;

    my @architectures = split(/,/, $manifest->{architectures});
    my %seen_arch;
    for my $architecture (@architectures) {
        validate_architecture($architecture);
        die "Duplicate release architecture: $architecture\n" if $seen_arch{$architecture}++;
    }
    die "Release manifest has no architectures\n" unless @architectures;

    my @formats = split(/,/, $manifest->{formats});
    my %seen_format;
    for my $format (@formats) {
        die "Unsupported package format: $format\n" unless $format eq 'rpm' || $format eq 'deb';
        die "Duplicate package format: $format\n" if $seen_format{$format}++;
    }
    die "Release manifest has no package formats\n" unless @formats;

    _verify_checksums($directory);

    my %expected = (
        'release.manifest' => 1,
    );
    for my $architecture (@architectures) {
        my $rpm = rpm_package_name($architecture);
        my $deb = deb_package_name($architecture);
        if ($seen_format{rpm}) {
            $expected{"rpm/$rpm-$manifest->{xcat_version}-$manifest->{xcat_release}.noarch.rpm"} = 1;
            $expected{"srpm/$rpm-$manifest->{xcat_version}-$manifest->{xcat_release}.src.rpm"} = 1;
        }
        if ($seen_format{deb}) {
            $expected{"deb/${deb}_$manifest->{xcat_version}-$manifest->{xcat_release}_all.deb"} = 1;
        }
    }
    for my $file (grep { $_ ne 'SHA256SUMS' } _regular_files($directory)) {
        die "Unexpected Genesis release artifact: $file\n" unless $expected{$file};
        delete($expected{$file});
    }
    die "Genesis release is missing: " . join(', ', sort keys %expected) . "\n"
      if %expected;
    return $manifest;
}

1;
