#!/usr/bin/perl

use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
use Getopt::Long qw(GetOptions);

my $script_dir = abs_path(dirname(__FILE__));
my $repo_root  = abs_path("$script_dir/..");
my $pkg_dir    = "$repo_root/xnba";
my $spec_file  = "$pkg_dir/xnba-undi.spec";
my $binary_dir = "$pkg_dir/binary";

my $work_dir    = '/tmp/xnba-undi-mockbuild';
my $mock_cfg    = '';
my $mock_uniqueext = '';
my $result_dir  = "$repo_root/build-output/list3/xnba-undi";
my $log_dir     = "$repo_root/build-logs/list3/xnba-undi";
my $build_timestamp;

GetOptions(
    'work-dir=s'     => \$work_dir,
    'mock-cfg=s'     => \$mock_cfg,
    'mock-uniqueext=s' => \$mock_uniqueext,
    'result-dir=s'   => \$result_dir,
    'log-dir=s'      => \$log_dir,
    'build-timestamp=i' => \$build_timestamp,
) or die usage();

die "Run as root (current uid=$>)\n" if $> != 0;
die "Missing spec file: $spec_file\n" if !-f $spec_file;
die "Missing binary directory: $binary_dir\n" if !-d $binary_dir;
die "Missing xnba.kpxe: $binary_dir/xnba.kpxe\n" if !-f "$binary_dir/xnba.kpxe";
die "Missing xnba.efi: $binary_dir/xnba.efi\n" if !-f "$binary_dir/xnba.efi";

for my $bin (qw(rpmbuild rpm tar)) {
    run("command -v " . sh_quote($bin) . " >/dev/null 2>&1");
}

my $arch = capture('uname -m');
if (!$mock_cfg) {
    my $os_id = capture(q{bash -lc 'source /etc/os-release; echo $ID'});
    $mock_cfg = resolve_mock_cfg($os_id, '10', $arch);
}

my $SOURCE_DATE_EPOCH;
$SOURCE_DATE_EPOCH = $build_timestamp if defined $build_timestamp;
if (!$SOURCE_DATE_EPOCH && -f "$repo_root/Gitepoch") {
    my $epoch_content = '';
    if (open my $efh, '<', "$repo_root/Gitepoch") {
        $epoch_content = <$efh>;
        close $efh;
        chomp $epoch_content;
    }
    $SOURCE_DATE_EPOCH = $epoch_content;
}
unless ($SOURCE_DATE_EPOCH && $SOURCE_DATE_EPOCH =~ /^\d+$/) {
    $SOURCE_DATE_EPOCH = `git -C \Q$repo_root\E log -1 --format=%ct HEAD 2>/dev/null`;
    chomp $SOURCE_DATE_EPOCH;
}
$SOURCE_DATE_EPOCH = time() unless $SOURCE_DATE_EPOCH =~ /^\d+$/;
$ENV{SOURCE_DATE_EPOCH} = $SOURCE_DATE_EPOCH;

print_step("Configuration");
print "repo_root:  $repo_root\n";
print "pkg_dir:    $pkg_dir\n";
print "work_dir:   $work_dir\n";
print "result_dir: $result_dir\n";
print "log_dir:    $log_dir\n";
print "mock_cfg:   $mock_cfg\n";

make_path($result_dir);
make_path($log_dir);

print_step("Stage build environment");
remove_tree($work_dir) if -d $work_dir;
# rpmbuild staging dir must be unique per run: --work-dir is run/target-scoped, so nesting it
# here keeps concurrent builds (e.g. parallel EL targets on one host) from wiping each other's
# tree. (Was a shared /var/tmp/xcat-rpmbuild-xnba, which collided under parallelism.)
my $rpmbuild_top = "$work_dir/rpmbuild";
remove_tree($rpmbuild_top) if -d $rpmbuild_top;
for my $d (qw(BUILD BUILDROOT RPMS SOURCES SPECS SRPMS)) {
    make_path("$rpmbuild_top/$d");
}

# Create source tarball with pre-built binaries
my $version = '1.21.1';
my $src_dir = "$work_dir/xnba-$version";
make_path("$src_dir/binary");
copy("$binary_dir/xnba.kpxe", "$src_dir/binary/xnba.kpxe")
    or die "Failed to copy xnba.kpxe: $!\n";
copy("$binary_dir/xnba.efi", "$src_dir/binary/xnba.efi")
    or die "Failed to copy xnba.efi: $!\n";

my $tarball = "$rpmbuild_top/SOURCES/xnba-$version.tar.gz";
run("tar --sort=name --owner=0 --group=0 --mtime=\@$SOURCE_DATE_EPOCH" .
    " -C " . sh_quote($work_dir) . " -czf " . sh_quote($tarball) . " xnba-$version");

# Create simplified spec that uses pre-built binaries
my $simple_spec = <<'SPEC';
Name:           xnba-undi
Version:        1.21.1
Release:        1%{?dist}
Summary:        xCAT Network Boot Agent for x86 PXE hosts
License:        GPL
URL:            https://ipxe.org/
BuildArch:      noarch

Source0:        xnba-%{version}.tar.gz

%description
The xCAT Network Boot Agent is a slightly modified version of iPXE.
It provides enhanced boot features for any UNDI compliant x86 host.
This includes iSCSI, http/ftp downloads, and iPXE script based booting.

%prep
%setup -n xnba-%{version}

%install
mkdir -p %{buildroot}/tftpboot/xcat
install -m 644 binary/xnba.kpxe %{buildroot}/tftpboot/xcat/xnba.kpxe
install -m 644 binary/xnba.efi %{buildroot}/tftpboot/xcat/xnba.efi

%files
/tftpboot/xcat/xnba.kpxe
/tftpboot/xcat/xnba.efi

%changelog
* Fri May 09 2026 xCAT Team <xcat-user@lists.sourceforge.net> - 1.21.1-1
- Packaged pre-built xnba binaries for EL10
SPEC

open my $fh, '>', "$rpmbuild_top/SPECS/xnba-undi.spec"
    or die "Cannot write spec: $!\n";
print $fh $simple_spec;
close $fh;

print_step("Build RPM");
my $rpmbuild_cmd = join(' ',
    'rpmbuild',
    '--define', sh_quote("_topdir $rpmbuild_top"),
    '--define', sh_quote("use_source_date_epoch_as_buildtime 1"),
    '--define', sh_quote("clamp_mtime_to_source_date_epoch 1"),
    '--define', sh_quote("_buildhost xcat-build"),
    '-ba',
    sh_quote("$rpmbuild_top/SPECS/xnba-undi.spec"),
);
run($rpmbuild_cmd);

print_step("Collect results");
for my $rpm (glob("$rpmbuild_top/RPMS/*/*.rpm"), glob("$rpmbuild_top/SRPMS/*.rpm")) {
    my $dest = "$result_dir/" . basename($rpm);
    copy($rpm, $dest) or die "Failed to copy $rpm to $dest: $!\n";
    print "Copied: $dest\n";
}

print_step("Completed");
print "Results in: $result_dir\n";
exit 0;

sub usage {
    return <<"USAGE";
Usage: $0 [options]

Build xnba-undi RPM from pre-built binaries.

Options:
  --work-dir PATH       Working directory (default: /tmp/xnba-undi-mockbuild)
  --mock-cfg NAME       Mock config name (auto-detected if omitted)
  --mock-uniqueext STR  Mock uniqueext value
  --result-dir PATH     Output directory for RPMs
  --log-dir PATH        Output directory for logs
  --build-timestamp EPOCH  Unix timestamp for reproducible builds
USAGE
}

sub print_step {
    my ($msg) = @_;
    print "\n== $msg ==\n";
}

sub run {
    my ($cmd) = @_;
    print "+ $cmd\n";
    my $rc = system($cmd);
    if ($rc != 0) {
        my $exit = $rc == -1 ? 255 : ($rc >> 8);
        die "Command failed (rc=$exit): $cmd\n";
    }
}

sub capture {
    my ($cmd) = @_;
    my $out = `$cmd`;
    chomp $out;
    return $out;
}

sub sh_quote {
    my ($s) = @_;
    $s = '' if !defined $s;
    $s =~ s/'/'"'"'/g;
    return "'$s'";
}

sub basename {
    my ($path) = @_;
    $path =~ s{.*/}{};
    return $path;
}

sub resolve_mock_cfg {
    my ($os_id, $rel, $arch) = @_;
    my %short_forms = (almalinux => 'alma', rocky => 'rocky');
    my $candidate = "${os_id}+epel-${rel}-${arch}";
    my $rc = system("mock -r " . sh_quote($candidate) . " --print-root-path >/dev/null 2>&1");
    return $candidate if $rc == 0;
    if (exists $short_forms{$os_id}) {
        $candidate = "$short_forms{$os_id}+epel-${rel}-${arch}";
        $rc = system("mock -r " . sh_quote($candidate) . " --print-root-path >/dev/null 2>&1");
        return $candidate if $rc == 0;
    }
    return "${os_id}+epel-${rel}-${arch}";
}
