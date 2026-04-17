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
my $pkg_dir    = "$repo_root/grub2-xcat";
my $spec_file  = "$pkg_dir/grub2-xcat.spec";
my $recompile_dir = "$repo_root/grub2-xcat.recompile";

my $resource_mode = 'reuse-grub2-res';
my $upstream_url  = 'https://mirror.stream.centos.org/10-stream/BaseOS/source/tree/Packages/grub2-2.12-37.el10.src.rpm';
my $upstream_file = '';
my $work_dir      = '/tmp/grub2-xcat-mockbuild';
my $mock_cfg      = '';
my $mock_uniqueext = '';
my $result_dir    = "$repo_root/build-output/list3/grub2-xcat";
my $log_dir       = "$repo_root/build-logs/list3/grub2-xcat";
my $skip_install  = 0;
my $skip_upstream_download = 0;

GetOptions(
    'resource-mode=s'        => \$resource_mode,
    'upstream-url=s'         => \$upstream_url,
    'upstream-file=s'        => \$upstream_file,
    'work-dir=s'             => \$work_dir,
    'mock-cfg=s'             => \$mock_cfg,
    'mock-uniqueext=s'       => \$mock_uniqueext,
    'result-dir=s'           => \$result_dir,
    'log-dir=s'              => \$log_dir,
    'skip-install!'          => \$skip_install,
    'skip-upstream-download!' => \$skip_upstream_download,
) or die usage();

die "Run as root (current uid=$>)\n" if $> != 0;
die "Missing spec file: $spec_file\n" if !-f $spec_file;
die "Invalid --resource-mode '$resource_mode'\n"
    if $resource_mode ne 'reuse-grub2-res' && $resource_mode ne 'regenerate-from-el10-srcrpm';
die "Mode regenerate-from-el10-srcrpm is not supported in this script yet; use reuse-grub2-res on x86_64 first.\n"
    if $resource_mode eq 'regenerate-from-el10-srcrpm';

make_path($recompile_dir) if !-d $recompile_dir;

for my $bin (qw(wget mock rpmbuild rpm dnf file bash tar sha256sum grep cmp cut)) {
    run("command -v " . sh_quote($bin) . " >/dev/null 2>&1");
}

my ($version, @spec_assets) = parse_spec($spec_file);
die "Could not parse Version from $spec_file\n" if !$version;

if (!$upstream_file) {
    $upstream_file = basename($upstream_url);
}
die "Could not derive upstream file name from URL: $upstream_url\n" if !$upstream_file;
my $upstream_path = "$recompile_dir/$upstream_file";

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
print "spec_file:  $spec_file\n";
print "recompile_dir: $recompile_dir\n";
print "resource_mode: $resource_mode\n";
print "work_dir:   $work_dir\n";
print "result_dir: $result_dir\n";
print "log_dir:    $log_dir\n";
print "mock_cfg:   $mock_cfg\n";
print "mock_uniqueext: " . ($mock_uniqueext ne '' ? $mock_uniqueext : '(none)') . "\n";
print "upstream_url:  $upstream_url\n";
print "upstream_file: $upstream_file\n";
print "skip_install:  $skip_install\n";
print "skip_upstream_download: $skip_upstream_download\n";

make_path($result_dir);
make_path($log_dir);

print_step("Mock config check");
run("mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt . " --print-root-path >/dev/null");

if (!$skip_upstream_download) {
    print_step("Download upstream source RPM");
    run("wget --spider " . sh_quote($upstream_url));
    run("wget -O " . sh_quote($upstream_path) . " " . sh_quote($upstream_url));
    my $sha = capture("sha256sum " . sh_quote($upstream_path) . " | cut -d ' ' -f1");
    my $meta_file = "$log_dir/upstream-source.txt";
    open my $mfh, '>', $meta_file or die "Cannot write $meta_file: $!\n";
    print {$mfh} "url=$upstream_url\n";
    print {$mfh} "file=$upstream_path\n";
    print {$mfh} "sha256=$sha\n";
    close $mfh;
    print "Downloaded upstream source rpm: $upstream_path\n";
    print "SHA256: $sha\n";
}

print_step("Verify grub2 resource payload");
my $resource_tar = "$pkg_dir/grub2-res.tar.gz";
die "Missing required resource tarball: $resource_tar\n" if !-f $resource_tar;
run(
    "tar -tzf " . sh_quote($resource_tar) .
    " | grep -F 'powerpc-ieee1275/' >/dev/null"
);
run(
    "tar -tzf " . sh_quote($resource_tar) .
    " | grep -F 'powerpc-ieee1275/core.elf' >/dev/null"
);

print_step("Verify spec assets");
for my $asset (@spec_assets) {
    my $path = "$pkg_dir/$asset";
    die "Missing required spec asset: $path\n" if !-f $path;
}
print "Verified " . scalar(@spec_assets) . " Source/Patch assets from spec.\n";

print_step("Stage files for prep check");
remove_tree($work_dir) if -d $work_dir;
my $prep_top = "$work_dir/prep";
for my $d (qw(BUILD BUILDROOT RPMS SOURCES SPECS SRPMS)) {
    make_path("$prep_top/$d");
}
copy($spec_file, "$prep_top/SPECS/grub2-xcat.spec")
    or die "Failed to copy spec to prep topdir: $!\n";
for my $asset (@spec_assets) {
    copy("$pkg_dir/$asset", "$prep_top/SOURCES/$asset")
        or die "Failed to copy $asset into prep SOURCES: $!\n";
}

print_step("Apply %prep flow");
my $prep_log = "$log_dir/prep.log";
run(
    "rpmbuild --define " . sh_quote("_topdir $prep_top") .
    " -bp --nodeps " . sh_quote("$prep_top/SPECS/grub2-xcat.spec") .
    " > " . sh_quote($prep_log) . " 2>&1"
);
my $patch_count = capture("grep -c '^Patch #' " . sh_quote($prep_log) . " || true");
print "Prep dry run passed. Applied patches: $patch_count\n";

print_step("Build SRPM with mock");
my $srpm_out = "$work_dir/srpm";
make_path($srpm_out);
run(
    "mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt .
    " --buildsrpm --spec " . sh_quote($spec_file) .
    " --sources " . sh_quote($pkg_dir) .
    " --resultdir " . sh_quote($srpm_out)
);

my @srpms = sort glob("$srpm_out/grub2-xcat-*.src.rpm");
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

my $main_rpm = '';
for my $rpm (@all_rpms) {
    next if $rpm =~ /\.src\.rpm$/;
    my $name = capture("rpm -qp --qf '%{NAME}' " . sh_quote($rpm));
    my $rarch = capture("rpm -qp --qf '%{ARCH}' " . sh_quote($rpm));
    if ($name eq 'grub2-xcat' && $rarch eq 'noarch') {
        $main_rpm = $rpm;
        last;
    }
}
die "Could not find main grub2-xcat noarch RPM in $rpm_out\n" if !$main_rpm;

print_step("Verify generated RPM");
my $rpm_name = capture("rpm -qp --qf '%{NAME}' " . sh_quote($main_rpm));
my $rpm_arch = capture("rpm -qp --qf '%{ARCH}' " . sh_quote($main_rpm));
die "Unexpected RPM name: $rpm_name\n" if $rpm_name ne 'grub2-xcat';
die "Unexpected RPM arch: $rpm_arch (expected noarch)\n" if $rpm_arch ne 'noarch';
run(
    "rpm -qpl " . sh_quote($main_rpm) .
    " | grep -F '/tftpboot/boot/grub2/powerpc-ieee1275/' >/dev/null"
);
run(
    "rpm -qpl " . sh_quote($main_rpm) .
    " | grep -Fx /tftpboot/boot/grub2/powerpc-ieee1275/core.elf >/dev/null"
);
print "Verified RPM name/arch/payload: $main_rpm\n";

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
    print_step("Install RPM and run smoke tests");
    run("dnf -y install " . sh_quote($main_rpm));

    my $core = '/tftpboot/boot/grub2/powerpc-ieee1275/core.elf';
    my $grub2ppc = '/tftpboot/boot/grub2/grub2.ppc';
    die "Missing installed core image: $core\n" if !-f $core;
    die "Missing installed post script output: $grub2ppc\n" if !-f $grub2ppc;

    my $file_core_log = "$log_dir/smoke-file-core.log";
    my $file_ppc_log  = "$log_dir/smoke-file-grub2ppc.log";
    my $qf_log        = "$log_dir/smoke-rpm-qf.log";

    my $rc_file_core = run_capture_rc("file $core", $file_core_log);
    my $rc_file_ppc  = run_capture_rc("file $grub2ppc", $file_ppc_log);
    my $rc_qf        = run_capture_rc("rpm -qf $core", $qf_log);
    my $rc_cmp       = run_capture_rc("cmp -s $core $grub2ppc", "$log_dir/smoke-cmp.log");

    die "Smoke check failed: file core returned $rc_file_core\n" if $rc_file_core != 0;
    die "Smoke check failed: file grub2.ppc returned $rc_file_ppc\n" if $rc_file_ppc != 0;
    die "Smoke check failed: rpm -qf returned $rc_qf\n" if $rc_qf != 0;
    die "Smoke check failed: core.elf and grub2.ppc differ (cmp rc=$rc_cmp)\n" if $rc_cmp != 0;

    my $core_out = slurp($file_core_log);
    my $qf_out   = slurp($qf_log);

    die "Core image signature check failed:\n$core_out\n"
        if $core_out !~ /ELF|data/i;
    die "Installed core image is not owned by grub2-xcat:\n$qf_out\n"
        if $qf_out !~ /^grub2-xcat-/m;

    my $summary = "$log_dir/smoke-summary.txt";
    open my $sfh, '>', $summary or die "Cannot write $summary: $!\n";
    print {$sfh} "core=$core\n";
    print {$sfh} "grub2ppc=$grub2ppc\n";
    print {$sfh} "rc_file_core=$rc_file_core\n";
    print {$sfh} "rc_file_ppc=$rc_file_ppc\n";
    print {$sfh} "rc_qf=$rc_qf\n";
    print {$sfh} "rc_cmp=$rc_cmp\n";
    close $sfh;
}

print_step("Completed");
print "Main RPM: $main_rpm\n";
print "Artifacts: $result_dir\n";
print "Logs: $log_dir\n";
exit 0;

sub usage {
    return <<"USAGE";
Usage: $0 [options]
  --resource-mode MODE    Build mode: reuse-grub2-res|regenerate-from-el10-srcrpm (default: $resource_mode)
  --upstream-url URL      Upstream grub2 source RPM URL (default: $upstream_url)
  --upstream-file FILE    Source RPM filename stored in grub2-xcat.recompile/ (default: basename of URL)
  --work-dir PATH         Temporary work dir (default: $work_dir)
  --mock-cfg NAME         Mock config (default: <ID>+epel-10-<ARCH>)
  --mock-uniqueext TXT    Optional mock --uniqueext suffix to isolate concurrent builds
  --result-dir PATH       Output RPM/SRPM directory (default: $result_dir)
  --log-dir PATH          Log directory (default: $log_dir)
  --skip-upstream-download  Skip wget of upstream source RPM
  --skip-install          Skip dnf install + smoke tests
USAGE
}

sub parse_spec {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot open spec $path: $!\n";

    my $version = '';
    my @assets;
    while (my $line = <$fh>) {
        if ($line =~ /^Version:\s*(\S+)/) {
            $version = $1;
        }
        if ($line =~ /^(?:Source|Patch)\d*:\s*(\S+)/) {
            my $asset = $1;
            push @assets, $asset;
        }
    }
    close $fh;

    @assets = map {
        my $v = $_;
        $v =~ s/%\{version\}/$version/g;
        $v =~ s/%\{ver\}/$version/g;
        $v;
    } @assets;

    return ($version, @assets);
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
