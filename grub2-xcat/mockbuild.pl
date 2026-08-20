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
my $pkg_dir    = "$repo_root/grub2-xcat";
my $spec_file  = "$pkg_dir/grub2-xcat.spec";
my $recompile_dir = "$repo_root/grub2-xcat.recompile";

my $resource_mode = 'reuse-grub2-res';
my $work_dir      = '/tmp/grub2-xcat-mockbuild';
my $mock_cfg      = '';
my $mock_uniqueext = '';
my $result_dir    = "$repo_root/build-output/list3/grub2-xcat";
my $log_dir       = "$repo_root/build-logs/list3/grub2-xcat";
my $skip_install  = 0;
my $build_timestamp;

GetOptions(
    'resource-mode=s'        => \$resource_mode,
    'work-dir=s'             => \$work_dir,
    'mock-cfg=s'             => \$mock_cfg,
    'mock-uniqueext=s'       => \$mock_uniqueext,
    'result-dir=s'           => \$result_dir,
    'log-dir=s'              => \$log_dir,
    'skip-install!'          => \$skip_install,
    'build-timestamp=i'      => \$build_timestamp,
) or die usage();

die "Run as root (current uid=$>)\n" if $> != 0;
die "Missing spec file: $spec_file\n" if !-f $spec_file;
die "Invalid --resource-mode '$resource_mode'\n"
    if $resource_mode ne 'reuse-grub2-res' && $resource_mode ne 'regenerate-from-el10-srcrpm';
die "Mode regenerate-from-el10-srcrpm is not supported in this script yet; use reuse-grub2-res on x86_64 first.\n"
    if $resource_mode eq 'regenerate-from-el10-srcrpm';

make_path($recompile_dir) if !-d $recompile_dir;

for my $bin (qw(mock rpmbuild rpm dnf file bash tar grep cmp)) {
    run("command -v " . sh_quote($bin) . " >/dev/null 2>&1");
}

my ($version, @spec_assets) = parse_spec($spec_file);
die "Could not parse Version from $spec_file\n" if !$version;

# NOTE: grub2-xcat is a pure noarch repackaging of the committed grub2-res.tar.gz (Source1),
# so the build needs no external source. Fetching the distro grub2 src.rpm would only ever be
# needed by the (currently unimplemented) regenerate-from-el10-srcrpm mode, which would rebuild
# the grub tree from source and commit a fresh grub2-res.tar.gz rather than download at build time.

my $arch = capture('uname -m');
if (!$mock_cfg) {
    my $os_id = capture(q{bash -lc 'source /etc/os-release; echo $ID'});
    $mock_cfg = "${os_id}+epel-10-${arch}";
}
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
print "spec_file:  $spec_file\n";
print "recompile_dir: $recompile_dir\n";
print "resource_mode: $resource_mode\n";
print "work_dir:   $work_dir\n";
print "result_dir: $result_dir\n";
print "log_dir:    $log_dir\n";
print "mock_cfg:   $mock_cfg\n";
print "mock_uniqueext: " . ($mock_uniqueext ne '' ? $mock_uniqueext : '(none)') . "\n";
print "skip_install:  $skip_install\n";

make_path($result_dir);
make_path($log_dir);

print_step("Mock config check");
run("mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt . " --print-root-path >/dev/null");

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

print_step("Verify riscv64 grub2 UEFI image");
my $riscv_efi = "$pkg_dir/grubriscv64.efi";
die "Missing required riscv64 grub2 image: $riscv_efi\n" if !-f $riscv_efi;
# Read the PE header ourselves: file(1) only learned the RISC-V PE machine types in 5.38,
# so an older build host (EL8 ships 5.33) would reject a perfectly good image.
my $riscv_efi_type = pe_image_type($riscv_efi);
die "Unexpected riscv64 grub2 image type: $riscv_efi is $riscv_efi_type, expected PE32+ RISC-V 64-bit\n"
    if $riscv_efi_type ne 'PE32+ RISC-V 64-bit';

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
my $det_mock_cfg = create_deterministic_mock_cfg($mock_cfg, $SOURCE_DATE_EPOCH, $work_dir);

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
run_mock(
    "mock -r " . sh_quote($det_mock_cfg) . $mock_uniqueext_opt .
    " --buildsrpm --spec " . sh_quote($spec_file) .
    " --sources " . sh_quote($pkg_dir) .
    " --resultdir " . sh_quote($srpm_out) .
    " --define 'use_source_date_epoch_as_buildtime 1'" .
    " --define 'clamp_mtime_to_source_date_epoch 1'" .
    " --define '_buildhost xcat-build'"
);

my @srpms = sort glob("$srpm_out/grub2-xcat-*.src.rpm");
die "SRPM not generated in $srpm_out\n" if !@srpms;
my $srpm = $srpms[-1];
print "SRPM: $srpm\n";

print_step("Rebuild RPM with mock");
my $rpm_out = "$work_dir/rpm";
make_path($rpm_out);
run_mock(
    "mock -r " . sh_quote($det_mock_cfg) . $mock_uniqueext_opt .
    " --rebuild " . sh_quote($srpm) .
    " --resultdir " . sh_quote($rpm_out) .
    " --define 'use_source_date_epoch_as_buildtime 1'" .
    " --define 'clamp_mtime_to_source_date_epoch 1'" .
    " --define '_buildhost xcat-build'"
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
run(
    "rpm -qpl " . sh_quote($main_rpm) .
    " | grep -Fx /tftpboot/boot/grub2/riscv64-efi/grubriscv64.efi >/dev/null"
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

    my $riscv_image = '/tftpboot/boot/grub2/riscv64-efi/grubriscv64.efi';
    my $grub2riscv  = '/tftpboot/boot/grub2/grub2.riscv64';
    die "Missing installed riscv64 grub2 image: $riscv_image\n" if !-f $riscv_image;
    die "Missing installed post script output: $grub2riscv\n" if !-f $grub2riscv;
    # The installed image must be the verified source image byte for byte, and %post must have
    # copied it to grub2.riscv64.
    my $rc_cmp_riscv_src = run_capture_rc("cmp -s " . sh_quote($riscv_efi) . " $riscv_image",
                                          "$log_dir/smoke-cmp-riscv64-source.log");
    my $rc_cmp_riscv     = run_capture_rc("cmp -s $riscv_image $grub2riscv", "$log_dir/smoke-cmp-riscv64.log");
    die "Smoke check failed: installed grubriscv64.efi differs from the source image (cmp rc=$rc_cmp_riscv_src)\n"
        if $rc_cmp_riscv_src != 0;
    die "Smoke check failed: grubriscv64.efi and grub2.riscv64 differ (cmp rc=$rc_cmp_riscv)\n" if $rc_cmp_riscv != 0;
    my $riscv_type = pe_image_type($grub2riscv);
    die "riscv64 grub2 image type check failed: $grub2riscv is $riscv_type\n"
        if $riscv_type ne 'PE32+ RISC-V 64-bit';

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
    print {$sfh} "grub2riscv64=$grub2riscv\n";
    print {$sfh} "rc_cmp_riscv64_source=$rc_cmp_riscv_src\n";
    print {$sfh} "type_riscv64=$riscv_type\n";
    print {$sfh} "rc_cmp_riscv64=$rc_cmp_riscv\n";
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
  --work-dir PATH         Temporary work dir (default: $work_dir)
  --mock-cfg NAME         Mock config (default: <ID>+epel-10-<ARCH>)
  --mock-uniqueext TXT    Optional mock --uniqueext suffix to isolate concurrent builds
  --result-dir PATH       Output RPM/SRPM directory (default: $result_dir)
  --log-dir PATH          Log directory (default: $log_dir)
  --skip-install          Skip dnf install + smoke tests
  --build-timestamp EPOCH Unix timestamp for deterministic builds (SOURCE_DATE_EPOCH)
USAGE
}

sub create_deterministic_mock_cfg {
    my ($base_cfg, $epoch, $dir) = @_;
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

# Image type of a PE file read from its headers, "PE32+ RISC-V 64-bit" for the grub2 UEFI
# image riscv64 firmware loads (COFF machine 0x5064, optional header magic 0x20b); anything
# else comes back as a short description for the error message.
sub pe_image_type {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "Cannot read $path: $!\n";
    my $buf = '';
    return 'not an MZ/PE file' if read($fh, $buf, 2) != 2 || $buf ne 'MZ';
    return 'truncated PE file' if !seek($fh, 0x3c, 0) || read($fh, $buf, 4) != 4;
    my $pe_off = unpack('V', $buf);
    return 'truncated PE file' if !seek($fh, $pe_off, 0) || read($fh, $buf, 26) != 26;
    close $fh;
    my ($sig, $machine, $magic) = unpack('a4 v x18 v', $buf);
    return 'not a PE file' if $sig ne "PE\0\0";
    my %machine_name = (0x5064 => 'RISC-V 64-bit', 0x5032 => 'RISC-V 32-bit',
                        0x8664 => 'x86-64', 0xaa64 => 'Aarch64', 0x014c => 'Intel 80386');
    my $format = $magic == 0x20b ? 'PE32+' : $magic == 0x10b ? 'PE32' : sprintf('PE (magic 0x%x)', $magic);
    return "$format " . ($machine_name{$machine} // sprintf('machine 0x%04x', $machine));
}

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot read $path: $!\n";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}
