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
my $pkg_dir    = "$repo_root/elilo";
my $spec_file  = "$pkg_dir/elilo-xcat.spec";

my $source_url  = 'https://downloads.sourceforge.net/project/elilo/elilo/elilo-3.14/elilo-3.14-all.tar.gz';
my $source_file = '';
my $work_dir    = '/tmp/elilo-xcat-mockbuild';
my $mock_cfg    = '';
my $mock_uniqueext = '';
my $result_dir  = "$repo_root/build-output/list3/elilo-xcat";
my $log_dir     = "$repo_root/build-logs/list3/elilo-xcat";
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

for my $bin (qw(wget mock rpmbuild rpm dnf file bash grep)) {
    run("command -v " . sh_quote($bin) . " >/dev/null 2>&1");
}

my ($version, @spec_assets) = parse_spec($spec_file);
die "Could not parse Version from $spec_file\n" if !$version;

if (!$source_file) {
    $source_file = "elilo-$version-source.tar.gz";
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
copy($spec_file, "$prep_top/SPECS/elilo-xcat.spec")
    or die "Failed to copy spec to prep topdir: $!\n";
for my $asset (@spec_assets) {
    copy("$pkg_dir/$asset", "$prep_top/SOURCES/$asset")
        or die "Failed to copy $asset into prep SOURCES: $!\n";
}

print_step("Apply patches in %prep");
my $prep_log = "$log_dir/prep.log";
run(
    "rpmbuild --define " . sh_quote("_topdir $prep_top") .
    " -bp --nodeps " . sh_quote("$prep_top/SPECS/elilo-xcat.spec") .
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

my @srpms = sort glob("$srpm_out/elilo-xcat-*.src.rpm");
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
    if ($name eq 'elilo-xcat' && $rarch eq 'noarch') {
        $main_rpm = $rpm;
        last;
    }
}
die "Could not find main elilo-xcat noarch RPM in $rpm_out\n" if !$main_rpm;

print_step("Verify generated RPM");
my $rpm_name = capture("rpm -qp --qf '%{NAME}' " . sh_quote($main_rpm));
my $rpm_arch = capture("rpm -qp --qf '%{ARCH}' " . sh_quote($main_rpm));
die "Unexpected RPM name: $rpm_name\n" if $rpm_name ne 'elilo-xcat';
die "Unexpected RPM arch: $rpm_arch (expected noarch)\n" if $rpm_arch ne 'noarch';
run(
    "rpm -qpl " . sh_quote($main_rpm) .
    " | grep -Fx /tftpboot/xcat/elilo-x64.efi >/dev/null"
);
print "Verified RPM name/arch/payload: $main_rpm\n";

print_step("Copy artifacts and logs");
for my $rpm (@all_rpms) {
    copy($rpm, $result_dir) or die "Failed to copy $rpm to $result_dir: $!\n";
}
for my $log (qw(build.log root.log state.log hw_info.log installed_pkgs.log)) {
    my $src = "$rpm_out/$log";
    next if !-f $src;
    copy($src, "$log_dir/$log")
        or die "Failed to copy $src to $log_dir: $!\n";
}

if (!$skip_install) {
    print_step("Install RPM and run smoke tests");
    run("dnf -y install " . sh_quote($main_rpm));

    my $efi_file = '/tftpboot/xcat/elilo-x64.efi';
    die "Missing installed EFI binary: $efi_file\n" if !-f $efi_file;

    my $file_log = "$log_dir/smoke-file.log";
    my $qf_log   = "$log_dir/smoke-rpm-qf.log";
    my $rc_file  = run_capture_rc("file $efi_file", $file_log);
    my $rc_qf    = run_capture_rc("rpm -qf $efi_file", $qf_log);

    die "Smoke check failed: file returned $rc_file\n" if $rc_file != 0;
    die "Smoke check failed: rpm -qf returned $rc_qf\n" if $rc_qf != 0;

    my $file_out = slurp($file_log);
    my $qf_out   = slurp($qf_log);

    die "EFI file signature check failed:\n$file_out\n"
        if $file_out !~ /(EFI application|PE32\+ executable)/i;
    die "Installed file is not owned by elilo-xcat:\n$qf_out\n"
        if $qf_out !~ /^elilo-xcat-/m;

    my $summary = "$log_dir/smoke-summary.txt";
    open my $sfh, '>', $summary or die "Cannot write $summary: $!\n";
    print {$sfh} "efi_file=$efi_file\n";
    print {$sfh} "rc_file=$rc_file\n";
    print {$sfh} "rc_qf=$rc_qf\n";
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
  --source-file FILE    Source filename stored in elilo/ (default: inferred from spec version)
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

    my $has_elilo = capture(
        "tar -tzf " . sh_quote($archive) .
        " | grep -E '^(\\./)?elilo/' | head -n1 || true"
    );
    return if $has_elilo ne '';

    my $nested = capture(
        "tar -tzf " . sh_quote($archive) .
        " | grep -E '^(\\./)?elilo-$version-source\\.tar\\.gz\$' | head -n1 || true"
    );
    die "Downloaded archive does not contain elilo source payload: $archive\n"
        if $nested eq '';

    my $normalize_dir = "$work_base/source-normalize";
    remove_tree($normalize_dir) if -d $normalize_dir;
    make_path($normalize_dir);

    run(
        "tar -xzf " . sh_quote($archive) .
        " -C " . sh_quote($normalize_dir) .
        " " . sh_quote($nested)
    );

    my $nested_rel = $nested;
    $nested_rel =~ s{^\./}{};
    my $nested_path = "$normalize_dir/$nested_rel";
    die "Failed to extract nested source archive: $nested_path\n"
        if !-f $nested_path;

    copy($nested_path, $archive)
        or die "Failed to normalize source archive $archive: $!\n";

    my $recheck = capture(
        "tar -tzf " . sh_quote($archive) .
        " | grep -E '^(\\./)?elilo/' | head -n1 || true"
    );
    die "Normalized source archive still missing elilo top-level tree: $archive\n"
        if $recheck eq '';
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
