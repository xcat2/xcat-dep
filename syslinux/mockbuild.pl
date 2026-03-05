#!/usr/bin/perl

use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname basename);
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
use Getopt::Long qw(GetOptions);

my $script_dir = abs_path(dirname(__FILE__));
my $repo_root  = abs_path("$script_dir/..");
my $pkg_dir    = "$repo_root/syslinux";
my $spec_file  = "$pkg_dir/syslinux-xcat.spec";

my $source_url   = 'https://www.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.xz';
my $source_file  = '';
my $work_dir     = '/tmp/syslinux-xcat-mockbuild';
my $mock_cfg     = '';
my $mock_uniqueext = '';
my $result_dir   = "$repo_root/build-output/list3/syslinux-xcat";
my $log_dir      = "$repo_root/build-logs/list3/syslinux-xcat";
my $skip_install = 0;
my $skip_upstream_download = 0;

GetOptions(
    'source-url=s'            => \$source_url,
    'source-file=s'           => \$source_file,
    'work-dir=s'              => \$work_dir,
    'mock-cfg=s'              => \$mock_cfg,
    'mock-uniqueext=s'        => \$mock_uniqueext,
    'result-dir=s'            => \$result_dir,
    'log-dir=s'               => \$log_dir,
    'skip-install!'           => \$skip_install,
    'skip-upstream-download!' => \$skip_upstream_download,
) or die usage();

die "Run as root (current uid=$>)\n" if $> != 0;
die "Missing spec file: $spec_file\n" if !-f $spec_file;

for my $bin (qw(wget mock rpmbuild rpm dnf file bash grep cut)) {
    run("command -v " . sh_quote($bin) . " >/dev/null 2>&1");
}

my ($pkg_name, $version, $source_assets_ref, $patch_assets_ref, $all_assets_ref) = parse_spec($spec_file);
my @source_assets = @{$source_assets_ref};
my @patch_assets  = @{$patch_assets_ref};
my @all_assets    = @{$all_assets_ref};

die "Could not parse Name/Version from $spec_file\n" if !$pkg_name || !$version;
die "No Source assets found in $spec_file\n" if !@source_assets;

if (!$source_file) {
    $source_file = $source_assets[0];
}

my $source_path = "$pkg_dir/$source_file";
my $arch = capture('uname -m');
if (!$mock_cfg) {
    my $os_id = capture(q{bash -lc 'source /etc/os-release; echo $ID'});
    $mock_cfg = "${os_id}+epel-10-${arch}";
}
my $mock_uniqueext_opt = $mock_uniqueext ne ''
    ? ' --uniqueext ' . sh_quote($mock_uniqueext)
    : '';

print_step("Configuration");
print "repo_root:  $repo_root\n";
print "pkg_dir:    $pkg_dir\n";
print "work_dir:   $work_dir\n";
print "result_dir: $result_dir\n";
print "log_dir:    $log_dir\n";
print "spec_file:  $spec_file\n";
print "pkg_name:   $pkg_name\n";
print "version:    $version\n";
print "mock_cfg:   $mock_cfg\n";
print "mock_uniqueext: " . ($mock_uniqueext ne '' ? $mock_uniqueext : '(none)') . "\n";
print "source_url: $source_url\n";
print "source_file:$source_file\n";
print "skip_install: $skip_install\n";
print "skip_upstream_download: $skip_upstream_download\n";

make_path($result_dir);
make_path($log_dir);

print_step("Mock config check");
run("mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt . " --print-root-path >/dev/null");

if (!$skip_upstream_download) {
    print_step("Download upstream source");
    run("wget --spider " . sh_quote($source_url));
    run("wget -O " . sh_quote($source_path) . " " . sh_quote($source_url));

    my $sha = capture("sha256sum " . sh_quote($source_path) . " | cut -d ' ' -f1");
    my $meta_file = "$log_dir/upstream-source.txt";
    open my $mfh, '>', $meta_file or die "Cannot write $meta_file: $!\n";
    print {$mfh} "url=$source_url\n";
    print {$mfh} "file=$source_path\n";
    print {$mfh} "sha256=$sha\n";
    close $mfh;
    print "Downloaded source: $source_path\n";
    print "SHA256: $sha\n";
}

print_step("Verify spec assets");
for my $asset (@all_assets) {
    my $path = "$pkg_dir/$asset";
    die "Missing required spec asset: $path\n" if !-f $path;
}
print "Verified Sources=" . scalar(@source_assets) . ", Patches=" . scalar(@patch_assets) . "\n";

print_step("Stage files for patch-application check");
remove_tree($work_dir) if -d $work_dir;
my $prep_top = "$work_dir/prep";
for my $d (qw(BUILD BUILDROOT RPMS SOURCES SPECS SRPMS)) {
    make_path("$prep_top/$d");
}
copy($spec_file, "$prep_top/SPECS/syslinux-xcat.spec")
    or die "Failed to copy spec to prep topdir: $!\n";
for my $asset (@all_assets) {
    copy("$pkg_dir/$asset", "$prep_top/SOURCES/$asset")
        or die "Failed to copy $asset into prep SOURCES: $!\n";
}

print_step("Apply patches in %prep");
my $prep_log = "$log_dir/prep.log";
run(
    "rpmbuild --define " . sh_quote("_topdir $prep_top") .
    " -bp --nodeps " . sh_quote("$prep_top/SPECS/syslinux-xcat.spec") .
    " > " . sh_quote($prep_log) . " 2>&1"
);
my $patch_count = capture("grep -c '^Patch #' " . sh_quote($prep_log) . " || true");
print "Patch application check passed. Applied patches: $patch_count\n";

print_step("Build SRPM with mock");
my $srpm_out = "$work_dir/srpm";
make_path($srpm_out);
run(
    "mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt .
    " --buildsrpm --spec " . sh_quote($spec_file) .
    " --sources " . sh_quote($pkg_dir) .
    " --resultdir " . sh_quote($srpm_out)
);

my @srpms = sort glob("$srpm_out/*.src.rpm");
die "SRPM not generated in $srpm_out\n" if !@srpms;
my $srpm = $srpms[-1];
print "SRPM: $srpm\n";

print_step("Rebuild RPM with mock");
my $rpm_out = "$work_dir/rpm";
make_path($rpm_out);
run(
    "mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt .
    " --rebuild " . sh_quote($srpm) .
    " --resultdir " . sh_quote($rpm_out)
);

my @all_rpms = sort glob("$rpm_out/*.rpm");
die "No RPMs generated in $rpm_out\n" if !@all_rpms;

my $xcat_rpm = '';
my $main_rpm = '';
for my $rpm (@all_rpms) {
    next if $rpm =~ /\.src\.rpm$/;
    my $name = capture("rpm -qp --qf '%{NAME}' " . sh_quote($rpm));
    my $rarch = capture("rpm -qp --qf '%{ARCH}' " . sh_quote($rpm));
    if ($name eq 'syslinux-xcat' && $rarch eq 'noarch') {
        $xcat_rpm = $rpm;
    }
    if ($name eq 'syslinux' && $rarch eq $arch) {
        $main_rpm = $rpm;
    }
}
die "Could not find main syslinux-xcat noarch RPM in $rpm_out\n" if !$xcat_rpm;

print_step("Verify generated RPM");
my $rpm_name = capture("rpm -qp --qf '%{NAME}' " . sh_quote($xcat_rpm));
my $rpm_arch = capture("rpm -qp --qf '%{ARCH}' " . sh_quote($xcat_rpm));
die "Unexpected RPM name: $rpm_name\n" if $rpm_name ne 'syslinux-xcat';
die "Unexpected RPM arch: $rpm_arch (expected noarch)\n" if $rpm_arch ne 'noarch';
run(
    "rpm -qpl " . sh_quote($xcat_rpm) .
    " | grep -F '/opt/xcat/share/xcat/netboot/syslinux/' >/dev/null"
);
run(
    "rpm -qpl " . sh_quote($xcat_rpm) .
    " | grep -Fx /opt/xcat/share/xcat/netboot/syslinux/pxelinux.0 >/dev/null"
);
print "Verified RPM name/arch/payload: $xcat_rpm\n";

print_step("Copy artifacts and logs");
for my $rpm (@all_rpms) {
    copy($rpm, $result_dir) or die "Failed to copy $rpm to $result_dir: $!\n";
}
copy($srpm, $result_dir) or die "Failed to copy $srpm to $result_dir: $!\n";
for my $log (qw(build.log root.log state.log hw_info.log installed_pkgs.log)) {
    my $src = "$rpm_out/$log";
    next if !-f $src;
    copy($src, "$log_dir/$log")
        or die "Failed to copy $src to $log_dir: $!\n";
}
for my $log (qw(build.log root.log state.log hw_info.log installed_pkgs.log)) {
    my $src = "$srpm_out/$log";
    next if !-f $src;
    copy($src, "$log_dir/srpm-$log")
        or die "Failed to copy $src to $log_dir: $!\n";
}

if (!$skip_install) {
    print_step("Install RPM(s) and run smoke tests");
    run("dnf -y install " . sh_quote($xcat_rpm));
    if ($main_rpm) {
        run("dnf -y install " . sh_quote($main_rpm));
    }

    my $pxe_file = '/opt/xcat/share/xcat/netboot/syslinux/pxelinux.0';
    die "Missing installed PXE file: $pxe_file\n" if !-f $pxe_file;

    my $file_log = "$log_dir/smoke-file.log";
    my $qf_log   = "$log_dir/smoke-rpm-qf.log";
    my $rc_file = run_capture_rc("file $pxe_file", $file_log);
    my $rc_qf   = run_capture_rc("rpm -qf $pxe_file", $qf_log);

    die "Smoke check failed: file returned $rc_file\n" if $rc_file != 0;
    die "Smoke check failed: rpm -qf returned $rc_qf\n" if $rc_qf != 0;

    my $qf_out = slurp($qf_log);
    die "Installed file is not owned by syslinux-xcat:\n$qf_out\n"
        if $qf_out !~ /^syslinux-xcat-/m;

    my $syslinux_help_log = "$log_dir/smoke-syslinux-help.log";
    if (-x '/usr/bin/syslinux') {
        my $rc_help = run_capture_rc("/usr/bin/syslinux --help", $syslinux_help_log);
        my $help_out = slurp($syslinux_help_log);
        die "syslinux --help returned unexpected rc=$rc_help\n"
            if $rc_help != 0 && $rc_help != 1;
        die "syslinux --help output missing expected usage text\n"
            if $help_out !~ /usage|syslinux/i;
    }

    my $summary = "$log_dir/smoke-summary.txt";
    open my $sfh, '>', $summary or die "Cannot write $summary: $!\n";
    print {$sfh} "pxe_file=$pxe_file\n";
    print {$sfh} "rc_file=$rc_file\n";
    print {$sfh} "rc_qf=$rc_qf\n";
    print {$sfh} "main_rpm_installed=" . ($main_rpm ? 1 : 0) . "\n";
    close $sfh;
}

print_step("Completed");
print "syslinux-xcat RPM: $xcat_rpm\n";
print "Artifacts: $result_dir\n";
print "Logs: $log_dir\n";
exit 0;

sub usage {
    return <<"USAGE";
Usage: $0 [options]
  --source-url URL      Upstream tarball URL (default: $source_url)
  --source-file FILE    Source filename stored in syslinux/ (default: inferred from spec)
  --work-dir PATH       Temporary work dir (default: $work_dir)
  --mock-cfg NAME       Mock config (default: <ID>+epel-10-<ARCH>)
  --mock-uniqueext TXT  Optional mock --uniqueext suffix to isolate concurrent builds
  --result-dir PATH     Output RPM/SRPM directory (default: $result_dir)
  --log-dir PATH        Log directory (default: $log_dir)
  --skip-upstream-download  Skip wget download step
  --skip-install        Skip dnf install + smoke tests
USAGE
}

sub parse_spec {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot open spec $path: $!\n";

    my %macros;
    my $name = '';
    my $version = '';
    my @sources;
    my @patches;

    while (my $line = <$fh>) {
        if ($line =~ /^\s*%(?:define|global)\s+([A-Za-z0-9_]+)\s+(.+?)\s*$/) {
            my ($k, $v) = (lc($1), $2);
            $v =~ s/\s+#.*$//;
            $macros{$k} = $v;
            next;
        }
        if ($line =~ /^Name:\s*(\S+)/) {
            $name = $1;
            $macros{name} = $name;
            next;
        }
        if ($line =~ /^Version:\s*(\S+)/) {
            $version = $1;
            $macros{version} = $version;
            next;
        }
        if ($line =~ /^Source\d*:\s*(\S+)/) {
            push @sources, $1;
            next;
        }
        if ($line =~ /^Patch\d*:\s*(\S+)/) {
            push @patches, $1;
            next;
        }
    }
    close $fh;

    $name = expand_macros($name, \%macros);
    $macros{name} = $name if $name;
    $version = expand_macros($version, \%macros);
    $macros{version} = $version if $version;

    @sources = map { normalize_asset(expand_macros($_, \%macros)) } @sources;
    @patches = map { normalize_asset(expand_macros($_, \%macros)) } @patches;

    my @assets = (@sources, @patches);
    return ($name, $version, \@sources, \@patches, \@assets);
}

sub expand_macros {
    my ($text, $macros) = @_;
    return '' if !defined $text;

    for (1..30) {
        my $prev = $text;
        $text =~ s/%\{([^}]+)\}/
            exists $macros->{lc($1)} ? $macros->{lc($1)} : "%{$1}"
        /ge;
        last if $text eq $prev;
    }
    return $text;
}

sub normalize_asset {
    my ($asset) = @_;
    $asset //= '';
    $asset =~ s/^["']//;
    $asset =~ s/["']$//;
    $asset =~ s/\?.*$//;

    if ($asset =~ m{^[A-Za-z][A-Za-z0-9+.-]*://}) {
        $asset =~ s{.*/}{};
    }
    $asset =~ s{^\./}{};
    return $asset;
}

sub print_step {
    my ($msg) = @_;
    print "\n== $msg ==\n";
}

sub sh_quote {
    my ($s) = @_;
    $s =~ s/'/'"'"'/g;
    return "'$s'";
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
    print "+ $cmd\n";
    my $out = `$cmd`;
    my $rc = $?;
    if ($rc != 0) {
        my $exit = $rc == -1 ? 255 : ($rc >> 8);
        die "Command failed (rc=$exit): $cmd\nOutput:\n$out\n";
    }
    chomp $out;
    return $out;
}

sub run_capture_rc {
    my ($cmd, $log_file) = @_;
    my $full = "$cmd > " . sh_quote($log_file) . " 2>&1";
    print "+ $full\n";
    my $rc = system($full);
    return $rc == -1 ? 255 : ($rc >> 8);
}

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot read $path: $!\n";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}
