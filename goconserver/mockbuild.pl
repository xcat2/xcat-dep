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
my $pkg_dir    = "$repo_root/goconserver";
my $work_dir   = '/tmp/goconserver-mockbuild';
my $mock_cfg   = '';
my $mock_uniqueext = '';
my $result_dir = '';
my $log_dir    = '';
my $src_rpm    = '';
my $src_rpm_url = '';
my $skip_install = 0;

GetOptions(
    'work-dir=s'      => \$work_dir,
    'mock-cfg=s'      => \$mock_cfg,
    'mock-uniqueext=s' => \$mock_uniqueext,
    'result-dir=s'    => \$result_dir,
    'log-dir=s'       => \$log_dir,
    'src-rpm=s'       => \$src_rpm,
    'src-rpm-url=s'   => \$src_rpm_url,
    'skip-install!'   => \$skip_install,
) or die usage();

die "Run as root (current uid=$>)\n" if $> != 0;
die "Missing package directory: $pkg_dir\n" if !-d $pkg_dir;

for my $bin (qw(mock rpmbuild rpm dnf ldd bash grep tar wget sha256sum cut)) {
    run("command -v " . sh_quote($bin) . " >/dev/null 2>&1");
}
my $has_bsdtar = command_exists('bsdtar');
if (!$has_bsdtar) {
    for my $bin (qw(rpm2cpio cpio)) {
        run("command -v " . sh_quote($bin) . " >/dev/null 2>&1");
    }
}

my $arch = capture('uname -m');
if (!$mock_cfg) {
    my $os_id = capture(q{bash -lc 'source /etc/os-release; echo $ID'});
    $mock_cfg = "${os_id}+epel-10-${arch}";
}
my $release_tag = derive_release_tag($mock_cfg);
my $mock_uniqueext_opt = $mock_uniqueext ne ''
    ? ' --uniqueext ' . sh_quote($mock_uniqueext)
    : '';

if (!$result_dir) {
    $result_dir = "$repo_root/build-output/list5/goconserver/$arch";
}
if (!$log_dir) {
    $log_dir = "$repo_root/build-logs/list5/goconserver/$arch";
}

make_path($result_dir);
make_path($log_dir);
make_path($work_dir);

if ($src_rpm_url) {
    my $dst = "$work_dir/" . basename($src_rpm_url);
    print_step("Download source RPM");
    run("wget --spider " . sh_quote($src_rpm_url));
    run("wget -O " . sh_quote($dst) . " " . sh_quote($src_rpm_url));
    my $sha = capture("sha256sum " . sh_quote($dst) . " | cut -d ' ' -f1");
    open my $mfh, '>', "$log_dir/source-rpm.txt"
        or die "Cannot write $log_dir/source-rpm.txt: $!\n";
    print {$mfh} "url=$src_rpm_url\n";
    print {$mfh} "path=$dst\n";
    print {$mfh} "sha256=$sha\n";
    close $mfh;
    $src_rpm = $dst;
}

if (!$src_rpm) {
    my @candidates;
    push @candidates, glob("$repo_root/build-output/list5/goconserver/$arch/goconserver-*.src.rpm");
    push @candidates, glob("$repo_root/goconserver-build-$arch/results/srpm/goconserver-*.src.rpm");
    push @candidates, glob("$repo_root/goconserver-build-$arch/results/rpm/goconserver-*.src.rpm");
    @candidates = sort @candidates;
    $src_rpm = $candidates[-1] if @candidates;
}
die "Could not locate goconserver source RPM. Use --src-rpm or --src-rpm-url.\n"
    if !$src_rpm || !-f $src_rpm;

print_step("Configuration");
print "repo_root:   $repo_root\n";
print "pkg_dir:     $pkg_dir\n";
print "work_dir:    $work_dir\n";
print "result_dir:  $result_dir\n";
print "log_dir:     $log_dir\n";
print "arch:        $arch\n";
print "mock_cfg:    $mock_cfg\n";
print "release_tag: " . ($release_tag ne '' ? $release_tag : '(unchanged)') . "\n";
print "mock_uniqueext: " . ($mock_uniqueext ne '' ? $mock_uniqueext : '(none)') . "\n";
print "src_rpm:     $src_rpm\n";
print "skip_install:$skip_install\n";
print "extractor:   " . ($has_bsdtar ? 'bsdtar' : 'rpm2cpio|cpio') . "\n";

print_step("Mock config check");
run("mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt . " --print-root-path >/dev/null");

print_step("Extract source RPM contents");
my $stage_dir = "$work_dir/stage";
remove_tree($stage_dir) if -d $stage_dir;
make_path($stage_dir);
if ($has_bsdtar) {
    run("bsdtar -xf " . sh_quote($src_rpm) . " -C " . sh_quote($stage_dir));
} else {
    my $extract_cmd =
        "cd " . sh_quote($stage_dir) .
        " && rpm2cpio " . sh_quote($src_rpm) .
        " | cpio -idm --quiet";
    run(
        "bash -lc " .
        sh_quote($extract_cmd)
    );
}

my @specs = sort glob("$stage_dir/*.spec");
die "Expected exactly one spec in $stage_dir, found " . scalar(@specs) . "\n"
    if @specs != 1;
my $spec_file = $specs[0];
normalize_spec_release($spec_file, $release_tag, $log_dir);

my ($version, @assets) = parse_spec($spec_file);
die "Could not parse Version from $spec_file\n" if !$version;
die "No Source/Patch assets parsed from $spec_file\n" if !@assets;

for my $asset (@assets) {
    my $path = "$stage_dir/$asset";
    die "Missing extracted spec asset: $path\n" if !-f $path;
}

my @repack = grep { /goconserver-repack-.*\.tar\.gz$/ } @assets;
die "Expected goconserver-repack source tar from spec assets.\n" if !@repack;
my $repack_tar = "$stage_dir/$repack[0]";

print_step("Verify repack payload");
for my $required (
    '/usr/bin/goconserver',
    '/usr/bin/congo',
    '/usr/lib/systemd/system/goconserver.service',
    '/etc/goconserver/server.conf'
) {
    my $rel = substr($required, 1);
    run(
        "tar -tzf " . sh_quote($repack_tar) .
        " | grep -F " . sh_quote("./$rel") .
        " >/dev/null"
    );
}

print_step("Run %prep check");
my $prep_top = "$work_dir/prep";
remove_tree($prep_top) if -d $prep_top;
for my $d (qw(BUILD BUILDROOT RPMS SOURCES SPECS SRPMS)) {
    make_path("$prep_top/$d");
}
copy($spec_file, "$prep_top/SPECS/" . basename($spec_file))
    or die "Failed to copy spec for prep check: $!\n";
for my $asset (@assets) {
    copy("$stage_dir/$asset", "$prep_top/SOURCES/$asset")
        or die "Failed to copy $asset for prep check: $!\n";
}
run(
    "rpmbuild --define " . sh_quote("_topdir $prep_top") .
    " -bp --nodeps " . sh_quote("$prep_top/SPECS/" . basename($spec_file)) .
    " > " . sh_quote("$log_dir/prep.log") . " 2>&1"
);

print_step("Build SRPM with mock");
my $srpm_out = "$work_dir/srpm";
remove_tree($srpm_out) if -d $srpm_out;
make_path($srpm_out);
run(
    "mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt .
    " --buildsrpm --spec " . sh_quote($spec_file) .
    " --sources " . sh_quote($stage_dir) .
    " --resultdir " . sh_quote($srpm_out) .
    " > " . sh_quote("$log_dir/mock-buildsrpm.log") . " 2>&1"
);

my @srpms = sort glob("$srpm_out/goconserver-*.src.rpm");
die "SRPM not generated in $srpm_out\n" if !@srpms;
my $built_srpm = $srpms[-1];
print "SRPM: $built_srpm\n";

print_step("Rebuild RPM with mock");
my $rpm_out = "$work_dir/rpm";
remove_tree($rpm_out) if -d $rpm_out;
make_path($rpm_out);
run(
    "mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt .
    " --rebuild " . sh_quote($built_srpm) .
    " --resultdir " . sh_quote($rpm_out) .
    " > " . sh_quote("$log_dir/mock-rebuild.log") . " 2>&1"
);

my @all_rpms = sort glob("$rpm_out/*.rpm");
die "No RPMs generated in $rpm_out\n" if !@all_rpms;

my $main_rpm = '';
for my $rpm (@all_rpms) {
    next if $rpm =~ /\.src\.rpm$/;
    my $name = capture("rpm -qp --qf '%{NAME}' " . sh_quote($rpm));
    my $rarch = capture("rpm -qp --qf '%{ARCH}' " . sh_quote($rpm));
    if ($name eq 'goconserver' && $rarch eq $arch) {
        $main_rpm = $rpm;
        last;
    }
}
die "Could not find main goconserver RPM in $rpm_out\n" if !$main_rpm;

print_step("Verify generated RPM");
my $rpm_name = capture("rpm -qp --qf '%{NAME}' " . sh_quote($main_rpm));
my $rpm_arch = capture("rpm -qp --qf '%{ARCH}' " . sh_quote($main_rpm));
die "Unexpected main RPM name: $rpm_name\n" if $rpm_name ne 'goconserver';
die "Unexpected main RPM arch: $rpm_arch (expected $arch)\n" if $rpm_arch ne $arch;
for my $required (
    '/usr/bin/goconserver',
    '/usr/bin/congo',
    '/usr/lib/systemd/system/goconserver.service'
) {
    run("rpm -qpl " . sh_quote($main_rpm) . " | grep -Fx " . sh_quote($required) . " >/dev/null");
}

print_step("Copy artifacts and logs");
for my $rpm (@all_rpms) {
    copy($rpm, $result_dir) or die "Failed to copy $rpm to $result_dir: $!\n";
}
copy($built_srpm, $result_dir) or die "Failed to copy $built_srpm to $result_dir: $!\n";

for my $log (qw(build.log root.log state.log hw_info.log installed_pkgs.log)) {
    my $src = "$rpm_out/$log";
    next if !-f $src;
    copy($src, "$log_dir/$log") or die "Failed to copy $src to $log_dir: $!\n";
}
for my $log (qw(build.log root.log state.log hw_info.log installed_pkgs.log)) {
    my $src = "$srpm_out/$log";
    next if !-f $src;
    copy($src, "$log_dir/srpm-$log") or die "Failed to copy $src to $log_dir: $!\n";
}

if (!$skip_install) {
    print_step("Install RPM and run smoke tests");
    install_for_smoke($main_rpm);

    my $bin_main = '/usr/bin/goconserver';
    my $bin_cli  = '/usr/bin/congo';
    die "Missing installed binary: $bin_main\n" if !-x $bin_main;
    die "Missing installed binary: $bin_cli\n" if !-x $bin_cli;

    my $rc_help_main = run_capture_rc("$bin_main -h", "$log_dir/smoke-goconserver-help.log");
    my $rc_help_cli  = run_capture_rc("$bin_cli -h", "$log_dir/smoke-congo-help.log");
    my $rc_ldd_main  = run_capture_rc("ldd $bin_main", "$log_dir/smoke-goconserver-ldd.log");
    my $rc_ldd_cli   = run_capture_rc("ldd $bin_cli", "$log_dir/smoke-congo-ldd.log");

    die "goconserver -h returned unexpected rc=$rc_help_main\n"
        if $rc_help_main != 0 && $rc_help_main != 1;
    die "congo -h returned unexpected rc=$rc_help_cli\n"
        if $rc_help_cli != 0 && $rc_help_cli != 1;
    die "ldd goconserver returned rc=$rc_ldd_main\n" if $rc_ldd_main != 0;
    die "ldd congo returned rc=$rc_ldd_cli\n" if $rc_ldd_cli != 0;

    my $help_main = slurp("$log_dir/smoke-goconserver-help.log");
    my $help_cli  = slurp("$log_dir/smoke-congo-help.log");
    my $ldd_main  = slurp("$log_dir/smoke-goconserver-ldd.log");
    my $ldd_cli   = slurp("$log_dir/smoke-congo-ldd.log");

    die "goconserver help output missing usage text\n"
        if $help_main !~ /usage|goconserver/i;
    die "congo help output missing usage text\n"
        if $help_cli !~ /usage|congo/i;
    die "goconserver ldd output missing libc\n"
        if $ldd_main !~ /libc/;
    die "congo ldd output missing libc\n"
        if $ldd_cli !~ /libc/;

    open my $sfh, '>', "$log_dir/smoke-summary.txt"
        or die "Cannot write $log_dir/smoke-summary.txt: $!\n";
    print {$sfh} "binary_main=$bin_main\n";
    print {$sfh} "binary_cli=$bin_cli\n";
    print {$sfh} "rc_help_main=$rc_help_main\n";
    print {$sfh} "rc_help_cli=$rc_help_cli\n";
    print {$sfh} "rc_ldd_main=$rc_ldd_main\n";
    print {$sfh} "rc_ldd_cli=$rc_ldd_cli\n";
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
  --src-rpm PATH       Source RPM containing goconserver.spec + repack tar
  --src-rpm-url URL    Optional URL to download source RPM before build
  --work-dir PATH      Temporary work dir (default: $work_dir)
  --mock-cfg NAME      Mock config (default: <ID>+epel-10-<ARCH>)
  --mock-uniqueext TXT Optional mock --uniqueext suffix to isolate concurrent builds
  --result-dir PATH    Output RPM/SRPM directory (default: build-output/list5/goconserver/<ARCH>)
  --log-dir PATH       Log directory (default: build-logs/list5/goconserver/<ARCH>)
  --skip-install       Skip dnf install + smoke tests
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

sub normalize_spec_release {
    my ($path, $release_tag, $log_dir) = @_;
    return if !$release_tag;

    open my $fh, '<', $path or die "Cannot open spec $path: $!\n";
    my @lines = <$fh>;
    close $fh;

    my $changed = 0;
    my $before = '';
    my $after  = '';
    for my $line (@lines) {
        next if $line !~ /^Release:\s*(\S+)/;
        $before = $1;
        my $updated = $before;
        if ($updated =~ s/\.el\d+(?=$|[^[:alnum:]])/.$release_tag/) {
            # already normalized
        } elsif ($updated !~ /\Q.$release_tag\E(?:$|[^[:alnum:]])/) {
            $updated .= ".$release_tag";
        }
        if ($updated ne $before) {
            $line =~ s/^Release:\s*\S+/Release: $updated/;
            $after = $updated;
            $changed = 1;
        }
        last;
    }

    if ($changed) {
        open my $out, '>', $path or die "Cannot write spec $path: $!\n";
        print {$out} @lines;
        close $out;
    }

    open my $lfh, '>', "$log_dir/spec-release-normalization.txt"
        or die "Cannot write $log_dir/spec-release-normalization.txt: $!\n";
    print {$lfh} "release_tag=$release_tag\n";
    print {$lfh} "changed=" . ($changed ? 'yes' : 'no') . "\n";
    print {$lfh} "before=$before\n" if $before ne '';
    print {$lfh} "after=$after\n" if $after ne '';
    close $lfh;
}

sub derive_release_tag {
    my ($cfg) = @_;
    return '' if !$cfg;
    return "el$1" if $cfg =~ /(?:^|[+_-])(\d+)-(?:x86_64|ppc64le|aarch64|s390x|ppc64)\b/;
    return '';
}

sub install_for_smoke {
    my ($rpm_path) = @_;
    my $name = capture("rpm -qp --qf '%{NAME}' " . sh_quote($rpm_path));
    my $installed = run_capture_rc("rpm -q " . sh_quote($name), "/tmp/goconserver-installed-query.log");
    if ($installed == 0) {
        my $install_rc = system("dnf -y install " . sh_quote($rpm_path) . " >/tmp/goconserver-dnf-install.log 2>&1");
        my $install_exit = $install_rc == -1 ? 255 : ($install_rc >> 8);
        return if $install_exit == 0;
        run("dnf -y downgrade " . sh_quote($rpm_path));
        return;
    }
    run("dnf -y install " . sh_quote($rpm_path));
}

sub command_exists {
    my ($bin) = @_;
    my $rc = system("command -v " . sh_quote($bin) . " >/dev/null 2>&1");
    return $rc == 0 ? 1 : 0;
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
