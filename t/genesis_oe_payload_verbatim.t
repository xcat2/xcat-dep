#!/usr/bin/env perl
# The Genesis OpenEmbedded package ships a pre-built netboot payload verbatim, beside the
# SHA256SUMS the export carries. rpm's install-post passes rewrite what they find: brp-strip
# runs strip over every unstripped ELF in the buildroot, and the ppc64, ppc64le and riscv64
# payloads are ELF. On an x86_64 build host strip cannot read them, so the pass fails and takes
# %install with it:
#
#   /usr/bin/strip: Unable to recognise the format of the input file
#     .../genesis-openembedded/ppc64/kernel
#   error: Bad exit status from /var/tmp/rpm-tmp.a79IE5 (%install)
#
# That stopped xcat-genesis-oe-build-ubuntu-amd64 #78 after a full eight-architecture build.
#
# This drives the real packager over a ppc64 export and asserts the build completes, that rpm
# runs no install-post pass at all, and that every payload file reaches the package with the
# bytes the export had. A grep for a %global line would pass on a definition rpm never reaches.
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use Test::More;

use lib "$RealBin/../lib", "$RealBin/lib";
use XCAT::BuildUtils qw(capture_command command_exists digest_file read_binary write_binary);
use XCAT::GenesisReleaseTest qw(make_export run_capture write_checksums);
use XCAT::GenesisRelease qw(rpm_package_name);

my $packager = "$RealBin/../genesis-openembedded/package";
plan skip_all => 'genesis-openembedded/package not found' unless -f $packager;
for my $command (qw(rpmbuild rpm file strip tar gzip)) {
    plan skip_all => "$command is not installed" unless command_exists($command);
}

my $ARCHITECTURE = 'ppc64';
my $VERSION      = '2.20.0';
my $RELEASE      = 'snap202610231815';
my $REVISION     = '0' x 40;
my $EPOCH        = 1792779356;

#-----------------------------------------------------------------------------------------------
=head3 ppc64_elf

Descriptions:
    A minimal 64-bit ELF whose e_machine is EM_PPC64 and whose section header table carries a
    SHT_SYMTAB. file(1) needs both before it calls a file an unstripped PowerPC ELF, and that
    is what rpm's brp-strip pass selects on. A real OpenEmbedded kernel is 47 MB, which is why
    the fixture is built here instead of committed.
Arguments:
    None
Returns:
    The ELF image as a byte string.
=cut
#-----------------------------------------------------------------------------------------------
sub ppc64_elf {
    my $ehsize = 64;
    my $shentsize = 64;
    my $shnum = 4;
    my $shoff = $ehsize;
    my $names = "\0.symtab\0.strtab\0.shstrtab\0";
    my $names_offset = $shoff + $shentsize * $shnum;
    my $header = pack(
        'a4C5a7vvVQ3Vvvvvvv',
        "\x7fELF", 2, 1, 1, 0, 0, '',    # 64-bit, little-endian, current version, System V
        2, 21,                           # ET_EXEC, EM_PPC64
        1, 0, 0, $shoff,                 # version, entry, program headers, section headers
        0, $ehsize, 0, 0, $shentsize, $shnum, 3,
    );
    die 'ELF header is ' . length($header) . " bytes\n" unless length($header) == $ehsize;
    my $section = sub {
        my ($name, $type, $offset, $size, $link, $entsize) = @_;
        return pack('VVQ6VV', $name, $type, 0, 0, 0, $offset, $size, $link, 0, 0, $entsize);
    };
    return $header
      . $section->(0, 0, 0, 0, 0, 0)
      . $section->(1, 2, $names_offset, 0, 2, 24)
      . $section->(9, 3, $names_offset, 0, 0, 0)
      . $section->(17, 3, $names_offset, length($names), 0, 0)
      . $names;
}

#-----------------------------------------------------------------------------------------------
=head3 package_file_digests

Descriptions:
    The SHA-256 digest rpm recorded for each payload file in a built package. Reading the header
    avoids unpacking the archive, and rpm computes the digest over the bytes it shipped.
Arguments:
    $rpm - the path of the built binary package
Returns:
    A hash reference of installed path to digest.
=cut
#-----------------------------------------------------------------------------------------------
sub package_file_digests {
    my ($rpm) = @_;
    my $dump = capture_command(
        'rpm', '-qp', '--nosignature', '--qf', '[%{FILENAMES} %{FILEDIGESTS}\n]', $rpm);
    my %digests;
    for my $line (split(/\n/, $dump)) {
        my ($path, $digest) = split(/ /, $line, 2);
        $digests{$path} = $digest if defined($digest);
    }
    return \%digests;
}

my $tmp = tempdir('xcat-genesis-verbatim.XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $export = make_export("$tmp/exports/$ARCHITECTURE", $ARCHITECTURE);
write_binary("$export/kernel", ppc64_elf());
write_checksums($export);

# Controls. Both assertions below are vacuous unless rpm's strip pass would select this file and
# this host's strip refuses it, which is the condition the build host failed under.
like(capture_command('file', '-b', "$export/kernel"),
    qr/\AELF \s 64-bit .* PowerPC .* not \s stripped\z/x,
    'control: the payload is an unstripped PowerPC ELF, which brp-strip selects');
write_binary("$tmp/strip-probe", read_binary("$export/kernel"));
isnt(run_capture("$tmp/strip.log", 'strip', '-g', "$tmp/strip-probe"), 0,
    'control: this host cannot strip a PowerPC ELF');

my $log = "$tmp/package.log";
my $status = run_capture(
    $log, $packager,
    '--architecture',      $ARCHITECTURE,
    '--export-dir',        $export,
    '--output-dir',        "$tmp/packages/$ARCHITECTURE",
    '--version',           $VERSION,
    '--release',           $RELEASE,
    '--revision',          $REVISION,
    '--source-date-epoch', $EPOCH,
    '--format',            'rpm',
);
is($status, 0, "packaging a $ARCHITECTURE Genesis export completes") or diag(read_binary($log));

unlike(read_binary($log), qr{/usr/lib/rpm/brp-},
    'rpm runs no install-post pass over the shipped payload');

my $rpm = "$tmp/packages/$ARCHITECTURE/rpm/"
  . rpm_package_name($ARCHITECTURE) . "-$VERSION-$RELEASE.noarch.rpm";
SKIP: {
    skip 'the package was not built', 3 unless -f $rpm;
    my $digests = package_file_digests($rpm);
    my $installed = "/opt/xcat/share/xcat/netboot/genesis-openembedded/$ARCHITECTURE";
    like($digests->{"$installed/kernel"} // '', qr/\A[0-9a-f]{64}\z/,
        'control: rpm records payload digests as SHA-256');
    my @differs = grep {
        ($digests->{"$installed/$_"} // '') ne digest_file("$export/$_", 'sha256')
    } _export_files($export);
    is_deeply(\@differs, [], 'every payload file reaches the package with the export bytes');
    is($digests->{"$installed/SHA256SUMS"}, digest_file("$export/SHA256SUMS", 'sha256'),
        'the shipped SHA256SUMS still describes the shipped payload');
}

done_testing();

#-----------------------------------------------------------------------------------------------
=head3 _export_files

Descriptions:
    The export file names, read from the export rather than from a list this test keeps, so a
    new file in an export is covered without editing the test.
Arguments:
    $directory - the export directory
Returns:
    The file names.
=cut
#-----------------------------------------------------------------------------------------------
sub _export_files {
    my ($directory) = @_;
    opendir(my $dh, $directory) or die "Cannot read $directory: $!\n";
    my @files = sort grep { -f "$directory/$_" } readdir($dh);
    closedir($dh);
    return @files;
}
