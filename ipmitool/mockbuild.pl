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
my $pkg_dir    = "$repo_root/ipmitool";
my $spec_file  = "$pkg_dir/ipmitool.spec";

my $source_file = '';
my $work_dir = '/tmp/ipmitool-xcat-mockbuild';
my $mock_cfg = '';
my $target_arch = '';
my $mock_uniqueext = '';
my $result_dir = "$repo_root/build-output/list3/ipmitool-xcat";
my $log_dir = "$repo_root/build-logs/list3/ipmitool-xcat";
my $build_timestamp;

GetOptions(
    'source-file=s'  => \$source_file,
    'work-dir=s'     => \$work_dir,
    'mock-cfg=s'     => \$mock_cfg,
    'target-arch=s'  => \$target_arch,
    'mock-uniqueext=s' => \$mock_uniqueext,
    'result-dir=s'   => \$result_dir,
    'log-dir=s'      => \$log_dir,
    'build-timestamp=i' => \$build_timestamp,
) or die usage();

die "Run as root (current uid=$>)\n" if $> != 0;
die "Missing spec file: $spec_file\n" if !-f $spec_file;

for my $bin (qw(mock rpmbuild rpm dnf ldd bash)) {
    run("command -v " . sh_quote($bin) . " >/dev/null 2>&1");
}

my ($version, @spec_assets) = parse_spec($spec_file);
die "Could not parse Version from $spec_file\n" if !$version;

if (!$source_file) {
    $source_file = "ipmitool-$version.tar.gz";
}

my $source_path = "$pkg_dir/$source_file";
my $arch = capture('uname -m');
if (!$mock_cfg) {
    my $os_id = capture(q{bash -lc 'source /etc/os-release; echo $ID'});
    $mock_cfg = resolve_mock_cfg($os_id, '10', $arch);
}
# Arch of the rpms --mock-cfg produces: the host arch unless the config is a forcearch (cross)
# one, e.g. rocky-10-riscv64-xcat built on x86_64 (see BUILD.md "riscv64").
$target_arch = $arch if $target_arch eq '';
my $mock_uniqueext_opt = $mock_uniqueext ne ''
    ? ' --uniqueext ' . sh_quote($mock_uniqueext)
    : '';

my $SOURCE_DATE_EPOCH;
$SOURCE_DATE_EPOCH = $build_timestamp if defined $build_timestamp;
if (!$SOURCE_DATE_EPOCH && -f "$repo_root/Gitepoch") {
    $SOURCE_DATE_EPOCH = slurp("$repo_root/Gitepoch");
    chomp $SOURCE_DATE_EPOCH;
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
print "target_arch:$target_arch\n";
print "mock_uniqueext: " . ($mock_uniqueext ne '' ? $mock_uniqueext : '(none)') . "\n";
print "source_file:$source_file\n";
print "SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH\n";

make_path($result_dir);
make_path($log_dir);

print_step("Mock config check");
run("mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt . " --print-root-path >/dev/null");

print_step("Verify tracked source archive");
# Upstream source (documented for provenance; NOT fetched at build time -- see below):
#   https://github.com/ipmitool/ipmitool/archive/refs/tags/IPMITOOL_1_8_18.tar.gz
# The ipmitool source (ipmitool-<ver>.tar.gz) is tracked in the repo, already normalized to the
# ipmitool-<ver>/ top-level that %setup -n expects, and consumed directly by mock (--sources
# $pkg_dir below). There is nothing to download: the old fetch re-derived this SAME tracked file
# and rewrote it IN PLACE, and the checkout is shared between the two arch build hosts building at
# once -- so the in-place rewrite raced the other host's concurrent ipmitool build, which could
# read the file mid-write and get a truncated archive. We only READ it now, so concurrent builds
# can never race on it. Fail loudly (do NOT silently re-fetch) if the checkout is missing/broken.
die "Tracked ipmitool source missing: $source_path (incomplete checkout?)\n" if !-f $source_path;
my $top = capture(
    "tar -tzf " . sh_quote($source_path) .
    " 2>/dev/null | grep -E '^(\\./)?ipmitool-$version/' | head -n1 || true"
);
die "Tracked ipmitool source is not the expected ipmitool-$version/ tree: $source_path\n"
    if $top eq '';
print "Using tracked source archive (read-only, no fetch, no shared write): $source_path\n";

print_step("Verify spec assets");
for my $asset (@spec_assets) {
    my $path = "$pkg_dir/$asset";
    die "Missing required spec asset: $path\n" if !-f $path;
}
print "Verified " . scalar(@spec_assets) . " Source/Patch assets from spec.\n";

print_step("Stage files for patch-application check");
remove_tree($work_dir) if -d $work_dir;
my $prep_top = "$work_dir/prep";
my $det_mock_cfg = create_deterministic_mock_cfg($mock_cfg, $SOURCE_DATE_EPOCH, $work_dir);
for my $d (qw(BUILD BUILDROOT RPMS SOURCES SPECS SRPMS)) {
    make_path("$prep_top/$d");
}
copy($spec_file, "$prep_top/SPECS/ipmitool.spec")
    or die "Failed to copy spec to prep topdir: $!\n";
for my $asset (@spec_assets) {
    copy("$pkg_dir/$asset", "$prep_top/SOURCES/$asset")
        or die "Failed to copy $asset into prep SOURCES: $!\n";
}

print_step("Apply patches in %prep");
my $prep_log = "$log_dir/prep.log";
run(
    "rpmbuild --define " . sh_quote("_topdir $prep_top") .
    " -bp --nodeps " . sh_quote("$prep_top/SPECS/ipmitool.spec") .
    " > " . sh_quote($prep_log) . " 2>&1"
);
my $patch_count = capture(
    "grep -c '^Patch #' " . sh_quote($prep_log) . " || true"
);
print "Patch application check passed. Applied patches: $patch_count\n";

print_step("Build SRPM with mock");
my $srpm_out = "$work_dir/srpm";
make_path($srpm_out);
run_mock(
    "mock -r " . sh_quote($det_mock_cfg) . $mock_uniqueext_opt .
    " --buildsrpm --spec " . sh_quote($spec_file) .
    " --sources " . sh_quote($pkg_dir) .
    " --define " . sh_quote("use_source_date_epoch_as_buildtime 1") .
    " --define " . sh_quote("clamp_mtime_to_source_date_epoch 1") .
    " --define " . sh_quote("_buildhost xcat-build") .
    " --resultdir " . sh_quote($srpm_out)
);

my @srpms = sort glob("$srpm_out/ipmitool-xcat-*.src.rpm");
die "SRPM not generated in $srpm_out\n" if !@srpms;
my $srpm = $srpms[-1];
print "SRPM: $srpm\n";

print_step("Rebuild RPM with mock");
my $rpm_out = "$work_dir/rpm";
make_path($rpm_out);
run_mock(
    "mock -r " . sh_quote($det_mock_cfg) . $mock_uniqueext_opt .
    " --rebuild " . sh_quote($srpm) .
    " --define " . sh_quote("use_source_date_epoch_as_buildtime 1") .
    " --define " . sh_quote("clamp_mtime_to_source_date_epoch 1") .
    " --define " . sh_quote("_buildhost xcat-build") .
    " --resultdir " . sh_quote($rpm_out)
);

my @arch_rpms = sort glob("$rpm_out/*.${target_arch}.rpm");
die "No architecture RPMs generated in $rpm_out\n" if !@arch_rpms;

my $main_rpm = '';
for my $rpm (@arch_rpms) {
    my $name = capture("rpm -qp --qf '%{NAME}' " . sh_quote($rpm));
    if ($name eq 'ipmitool-xcat') {
        $main_rpm = $rpm;
        last;
    }
}
die "Could not find main ipmitool-xcat RPM in $rpm_out\n" if !$main_rpm;

print_step("Verify generated RPM");
my $rpm_name = capture("rpm -qp --qf '%{NAME}' " . sh_quote($main_rpm));
my $rpm_arch = capture("rpm -qp --qf '%{ARCH}' " . sh_quote($main_rpm));
die "Unexpected RPM name: $rpm_name\n" if $rpm_name ne 'ipmitool-xcat';
die "Unexpected RPM arch: $rpm_arch (expected $target_arch)\n" if $rpm_arch ne $target_arch;
run(
    "rpm -qpl " . sh_quote($main_rpm) .
    " | grep -Fx /opt/xcat/bin/ipmitool-xcat >/dev/null"
);
print "Verified RPM name/arch/payload: $main_rpm\n";

print_step("Copy artifacts and logs");
for my $rpm (@arch_rpms) {
    copy($rpm, $result_dir) or die "Failed to copy $rpm to $result_dir: $!\n";
}
copy($srpm, $result_dir) or die "Failed to copy $srpm to $result_dir: $!\n";
for my $log (qw(build.log root.log state.log hw_info.log installed_pkgs.log)) {
    my $src = "$rpm_out/$log";
    next if !-f $src;
    copy($src, "$log_dir/$log")
        or die "Failed to copy $src to $log_dir: $!\n";
}

if ($target_arch ne $arch) {
    # A cross-built rpm cannot be installed on this host: install it into the (emulated) build
    # chroot instead and run the binary there.
    print_step("Install RPM into the chroot and run smoke tests");
    run_mock("mock -r " . sh_quote($det_mock_cfg) . $mock_uniqueext_opt . " --install " . sh_quote($main_rpm)
        . " > " . sh_quote("$log_dir/smoke-chroot-install.log") . " 2>&1");
    my $bin = '/opt/xcat/bin/ipmitool-xcat';
    my $version_log = "$log_dir/smoke-version.log";
    my $rc_version  = run_capture_rc(
        "mock -r " . sh_quote($det_mock_cfg) . $mock_uniqueext_opt . " -q --chroot -- " . sh_quote("$bin -V"),
        $version_log);
    die "Smoke check failed: -V in the chroot returned $rc_version\n" if $rc_version != 0;
    my $version_out = slurp($version_log);
    die "Version output missing expected version string\n"
        if $version_out !~ /ipmitool-xcat version \Q$version\E/i;
    my $summary = "$log_dir/smoke-summary.txt";
    open my $sfh, '>', $summary or die "Cannot write $summary: $!\n";
    print {$sfh} "binary=$bin (in chroot $mock_cfg)\n";
    print {$sfh} "rc_version=$rc_version\n";
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
  --source-file FILE    Source filename stored in ipmitool/ (default: inferred from spec version)
  --work-dir PATH       Temporary work dir (default: $work_dir)
  --mock-cfg NAME       Mock config (default: <ID>+epel-10-<ARCH>)
  --target-arch ARCH    Arch of the rpms --mock-cfg produces (default: uname -m); a forcearch
                        config such as rocky-10-riscv64-xcat needs it
  --mock-uniqueext TXT  Optional mock --uniqueext suffix to isolate concurrent builds
  --result-dir PATH     Output RPM/SRPM directory (default: $result_dir)
  --log-dir PATH        Log directory (default: $log_dir)
  --build-timestamp N   Unix epoch for SOURCE_DATE_EPOCH (deterministic builds)
USAGE
}

sub create_deterministic_mock_cfg {
    my ($base_cfg, $epoch, $dir) = @_;
    make_path($dir) unless -d $dir;
    my $cfg_path = "$dir/mock-deterministic.cfg";
    open my $fh, '>', $cfg_path or die "Cannot write $cfg_path: $!\n";
    print $fh "include('/etc/mock/${base_cfg}.cfg')\n";
    print $fh "config_opts['environment']['SOURCE_DATE_EPOCH'] = '$epoch'\n";
    close $fh;
    return $cfg_path;
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

# mock exits 30 when its package manager failed (chroot init, build deps), which against public
# mirrors is most often a transient download error (stale mirror metadata): retry such a run once.
sub run_mock {
    my ($cmd) = @_;
    print "+ $cmd\n";
    my $rc = system($cmd);
    if ($rc != -1 && ($rc >> 8) == 30) {
        print "mock failed with rc=30 (package manager); retrying once\n";
        $rc = system($cmd);
    }
    if ($rc != 0) {
        my $exit = $rc == -1 ? 255 : ($rc >> 8);
        die "Command failed (rc=$exit): $cmd\n";
    }
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
