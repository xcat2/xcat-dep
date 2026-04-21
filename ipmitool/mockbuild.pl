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
my $pkg_dir    = "$repo_root/ipmitool";
my $spec_file  = "$pkg_dir/ipmitool.spec";

my $source_url = 'https://github.com/ipmitool/ipmitool/archive/refs/tags/IPMITOOL_1_8_18.tar.gz';
my $source_file = '';
my $work_dir = '/tmp/ipmitool-xcat-mockbuild';
my $mock_cfg = '';
my $mock_uniqueext = '';
my $result_dir = "$repo_root/build-output/list3/ipmitool-xcat";
my $log_dir = "$repo_root/build-logs/list3/ipmitool-xcat";
my $skip_install = 0;

GetOptions(
    'source-url=s'   => \$source_url,
    'source-file=s'  => \$source_file,
    'work-dir=s'     => \$work_dir,
    'mock-cfg=s'     => \$mock_cfg,
    'mock-uniqueext=s' => \$mock_uniqueext,
    'result-dir=s'   => \$result_dir,
    'log-dir=s'      => \$log_dir,
    'skip-install!'  => \$skip_install,
) or die usage();

die "Run as root (current uid=$>)\n" if $> != 0;
die "Missing spec file: $spec_file\n" if !-f $spec_file;

for my $bin (qw(wget mock rpmbuild rpm dnf ldd bash)) {
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
print "mock_cfg:   $mock_cfg\n";
print "mock_uniqueext: " . ($mock_uniqueext ne '' ? $mock_uniqueext : '(none)') . "\n";
print "source_url: $source_url\n";
print "source_file:$source_file\n";
print "skip_install: $skip_install\n";

make_path($result_dir);
make_path($log_dir);

print_step("Mock config check");
run("mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt . " --print-root-path >/dev/null");

print_step("Download upstream source");
run("wget --spider " . sh_quote($source_url));
run("wget -O " . sh_quote($source_path) . " " . sh_quote($source_url));
normalize_source_archive($source_path, $version, $work_dir);

print_step("Verify spec assets");
for my $asset (@spec_assets) {
    my $path = "$pkg_dir/$asset";
    die "Missing required spec asset: $path\n" if !-f $path;
}
print "Verified " . scalar(@spec_assets) . " Source/Patch assets from spec.\n";

print_step("Stage files for patch-application check");
remove_tree($work_dir) if -d $work_dir;
my $prep_top = "$work_dir/prep";
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
run(
    "mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt .
    " --buildsrpm --spec " . sh_quote($spec_file) .
    " --sources " . sh_quote($pkg_dir) .
    " --resultdir " . sh_quote($srpm_out)
);

my @srpms = sort glob("$srpm_out/ipmitool-xcat-*.src.rpm");
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

my @arch_rpms = sort glob("$rpm_out/*.${arch}.rpm");
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
die "Unexpected RPM arch: $rpm_arch (expected $arch)\n" if $rpm_arch ne $arch;
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

if (!$skip_install) {
    print_step("Install RPM and run smoke tests");
    run("dnf -y install " . sh_quote($main_rpm));

    my $bin = '/opt/xcat/bin/ipmitool-xcat';
    die "Missing installed binary: $bin\n" if !-x $bin;

    my $help_short_log = "$log_dir/smoke-help-short.log";
    my $help_long_log  = "$log_dir/smoke-help-long.log";
    my $version_log    = "$log_dir/smoke-version.log";
    my $open_log       = "$log_dir/smoke-open-mc-info.log";
    my $ldd_log        = "$log_dir/smoke-ldd.log";

    my $rc_help_short = run_capture_rc("$bin -h", $help_short_log);
    my $rc_help_long  = run_capture_rc("$bin --help", $help_long_log);
    my $rc_version    = run_capture_rc("$bin -V", $version_log);
    my $rc_open       = run_capture_rc("$bin -I open mc info", $open_log);
    my $rc_ldd        = run_capture_rc("ldd $bin", $ldd_log);

    die "Smoke check failed: -h returned $rc_help_short\n" if $rc_help_short != 0;
    die "Smoke check failed: -V returned $rc_version\n" if $rc_version != 0;
    die "Smoke check failed: ldd returned $rc_ldd\n" if $rc_ldd != 0;

    my $help_short_out = slurp($help_short_log);
    my $help_long_out  = slurp($help_long_log);
    my $version_out    = slurp($version_log);
    my $open_out       = slurp($open_log);
    my $ldd_out        = slurp($ldd_log);

    die "Short help output does not contain usage text\n"
        if $help_short_out !~ /usage:/i;
    die "Long help output does not contain usage text\n"
        if $help_long_out !~ /usage:/i;
    die "Long help returned unexpected rc=$rc_help_long (expected 0 or 1)\n"
        if $rc_help_long != 0 && $rc_help_long != 1;
    die "Version output missing expected version string\n"
        if $version_out !~ /ipmitool-xcat version \Q$version\E/i;
    die "ldd output missing libcrypto dependency\n"
        if $ldd_out !~ /libcrypto/;
    die "Expected no-IPMI failure did not occur; rc=$rc_open\n"
        if $rc_open == 0;
    die "No-IPMI probe failed with unexpected output:\n$open_out\n"
        if $open_out !~ m{Could not open device|/dev/ipmi};

    my $summary = "$log_dir/smoke-summary.txt";
    open my $sfh, '>', $summary or die "Cannot write $summary: $!\n";
    print {$sfh} "binary=$bin\n";
    print {$sfh} "rc_help_short=$rc_help_short\n";
    print {$sfh} "rc_help_long=$rc_help_long\n";
    print {$sfh} "rc_version=$rc_version\n";
    print {$sfh} "rc_open=$rc_open\n";
    print {$sfh} "rc_ldd=$rc_ldd\n";
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
  --source-url URL      Upstream tarball URL (default: $source_url)
  --source-file FILE    Source filename stored in ipmitool/ (default: inferred from spec version)
  --work-dir PATH       Temporary work dir (default: $work_dir)
  --mock-cfg NAME       Mock config (default: <ID>+epel-10-<ARCH>)
  --mock-uniqueext TXT  Optional mock --uniqueext suffix to isolate concurrent builds
  --result-dir PATH     Output RPM/SRPM directory (default: $result_dir)
  --log-dir PATH        Log directory (default: $log_dir)
  --skip-install        Skip dnf install + smoke tests
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

sub normalize_source_archive {
    my ($archive, $version, $work_base) = @_;

    my $normalize_dir = "$work_base/source-normalize";
    remove_tree($normalize_dir) if -d $normalize_dir;
    make_path($normalize_dir);

    run("tar -xzf " . sh_quote($archive) . " -C " . sh_quote($normalize_dir));

    my @entries = grep { $_ !~ m{/\.\.?$} } glob("$normalize_dir/*");
    die "Unexpected archive layout in $archive\n" if @entries != 1;
    my $top_path = $entries[0];
    die "Unexpected non-directory top-level entry in $archive: $top_path\n"
        if !-d $top_path;

    my $expected_top = "ipmitool-$version";
    my $actual_top = basename($top_path);
    if ($actual_top ne $expected_top) {
        my $new_path = "$normalize_dir/$expected_top";
        run("rm -rf " . sh_quote($new_path));
        run("mv " . sh_quote($top_path) . " " . sh_quote($new_path));
    }

    # Repack using the expected top-level directory required by the spec.
    run(
        "tar -C " . sh_quote($normalize_dir) .
        " -czf " . sh_quote($archive) .
        " " . sh_quote($expected_top)
    );
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
