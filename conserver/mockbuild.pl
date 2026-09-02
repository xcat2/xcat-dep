#!/usr/bin/perl
#
# mockbuild.pl - build conserver-xcat (the traditional C conserver, 8.2.1) for one
# mock target. Mirrors the other xcat-dep
# builders (goconserver/mockbuild.pl, ipmitool/mockbuild.pl): stage sources + spec,
# build a SRPM, `mock --rebuild` it in the target chroot, and copy the RPMs to
# --result-dir.
#
# conserver is NOT part of the default mockbuild-all.pl dep set (xCAT uses goconserver),
# so this builder is standalone. Usage:
#   ./mockbuild.pl --mock-cfg alma+epel-9-x86_64 --result-dir /path/out
#
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname basename);
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use Getopt::Long qw(GetOptions);

my $script_dir = abs_path(dirname(__FILE__));
my $pkg_dir    = $script_dir;            # tarball + patches + spec live alongside this script
my $version    = '8.2.1';

my $work_dir       = '/tmp/conserver-mockbuild';
my $mock_cfg       = '';
my $target_arch    = '';
my $mock_uniqueext = '';
my $result_dir     = "$script_dir/../build-output/list-conserver/conserver";
my $log_dir        = "$script_dir/../build-logs/list-conserver/conserver";
my $build_timestamp;

GetOptions(
    'work-dir=s'        => \$work_dir,
    'mock-cfg=s'        => \$mock_cfg,
    'target-arch=s'     => \$target_arch,
    'mock-uniqueext=s'  => \$mock_uniqueext,
    'result-dir=s'      => \$result_dir,
    'log-dir=s'         => \$log_dir,
    'build-timestamp=i' => \$build_timestamp,
) or die usage();

die "Run as root (current uid=$>)\n" if $> != 0;
for my $bin (qw(mock rpmbuild rpm)) {
    run("command -v " . sh_quote($bin) . " >/dev/null 2>&1");
}

# Deterministic builds: honor --build-timestamp (else Gitepoch, else git HEAD time),
# matching the other xcat-dep builders so mockbuild-all.pl can drive this one.
my $repo_root = abs_path("$script_dir/..");
my $sde = $build_timestamp;
if (!$sde && -f "$repo_root/Gitepoch") { $sde = capture("cat " . sh_quote("$repo_root/Gitepoch")); }
if (!$sde || $sde !~ /^\d+$/) {
    $sde = capture("git -C " . sh_quote($repo_root) . " log -1 --format=%ct HEAD 2>/dev/null");
}
$ENV{SOURCE_DATE_EPOCH} = $sde if defined $sde && $sde =~ /^\d+$/;

my $arch = capture('uname -m');
if (!$mock_cfg) {
    my $os_id = capture(q{bash -lc 'source /etc/os-release; echo $ID'});
    $os_id = 'alma' if $os_id eq 'almalinux';
    my ($rel) = capture('rpm -E %rhel');
    $mock_cfg = "${os_id}+epel-${rel}-${arch}";
}
# Arch of the rpms --mock-cfg produces: the host arch unless the config is a forcearch (cross)
# one, e.g. rocky-10-riscv64-xcat built on x86_64 (see BUILD.md "riscv64").
$target_arch = $arch if $target_arch eq '';
my $uniq = $mock_uniqueext ne '' ? ' --uniqueext ' . sh_quote($mock_uniqueext) : '';

make_path($result_dir, $log_dir);
print "package:    conserver-xcat\n";
print "version:    $version\n";
print "arch:       $arch\n";
print "target-arch:$target_arch\n";
print "mock-cfg:   $mock_cfg\n";
print "result-dir: $result_dir\n";

# ---- stage sources + spec into a private rpmbuild tree -----------------------
remove_tree($work_dir) if -d $work_dir;
make_path("$work_dir/SOURCES", "$work_dir/SPECS");
copy("$pkg_dir/conserver-$version.tar.gz", "$work_dir/SOURCES/")
    or die "FATAL: cannot stage conserver-$version.tar.gz: $!\n";
for my $p (glob("$pkg_dir/*.patch")) {
    copy($p, "$work_dir/SOURCES/") or die "FATAL: cannot stage patch $p: $!\n";
}
copy("$pkg_dir/conserver.spec", "$work_dir/SPECS/")
    or die "FATAL: cannot stage conserver.spec: $!\n";

# ---- build the SRPM (host rpm just packages sources+spec; no %prep here) ------
print "== Build SRPM ==\n";
run("rpmbuild -bs --define " . sh_quote("_topdir $work_dir")
    . " " . sh_quote("$work_dir/SPECS/conserver.spec")
    . " > " . sh_quote("$log_dir/srpm.log") . " 2>&1");
my ($srpm) = glob("$work_dir/SRPMS/conserver-xcat-$version-*.src.rpm");
die "FATAL: SRPM not produced (see $log_dir/srpm.log)\n" unless $srpm && -f $srpm;
print "SRPM: $srpm\n";

# ---- mock rebuild in the target chroot --------------------------------------
print "== mock --rebuild ($mock_cfg) ==\n";
my $mock_result = "$work_dir/mock-result";
make_path($mock_result);
run_mock("mock -r " . sh_quote($mock_cfg) . $uniq
    . " --rebuild " . sh_quote($srpm)
    . " --resultdir " . sh_quote($mock_result)
    . " > " . sh_quote("$log_dir/mock-rebuild.log") . " 2>&1");

my @rpms = grep { $_ !~ /\.src\.rpm$/ && $_ !~ /-debug(info|source)-/ }
           glob("$mock_result/*.rpm");
die "FATAL: no binary RPM produced (see $log_dir/mock-rebuild.log)\n" unless @rpms;
my ($main) = grep { basename($_) =~ /^conserver-xcat-\Q$version\E-.*\.(?:$target_arch|noarch)\.rpm$/ } @rpms;
die "FATAL: main conserver-xcat RPM not found among: @rpms\n" unless $main;

for my $r (@rpms) {
    copy($r, $result_dir) or die "FATAL: cannot copy $r -> $result_dir: $!\n";
}
print "built: " . join(', ', map { basename($_) } @rpms) . "\n";

print "DONE: conserver-xcat $version for $mock_cfg -> $result_dir\n";

# ---- helpers ----------------------------------------------------------------
sub run {
    my ($cmd) = @_;
    my $rc = system('bash', '-c', $cmd);
    die "FATAL: command failed (rc=" . ($rc >> 8) . "): $cmd\n" if $rc != 0;
    return 1;
}
sub capture {
    my ($cmd) = @_;
    my $out = `$cmd`;
    chomp $out if defined $out;
    return $out // '';
}
# mock exits 30 when its package manager failed (chroot init, build deps), which against public
# mirrors is most often a transient download error (stale mirror metadata): retry such a run once.
sub run_mock {
    my ($cmd) = @_;
    my $rc = system('bash', '-c', $cmd);
    if ($rc != -1 && ($rc >> 8) == 30) {
        print "mock failed with rc=30 (package manager); retrying once\n";
        $rc = system('bash', '-c', $cmd);
    }
    die "FATAL: command failed (rc=" . ($rc >> 8) . "): $cmd\n" if $rc != 0;
    return 1;
}
sub sh_quote { my ($s) = @_; $s =~ s/'/'\\''/g; return "'$s'"; }
sub usage {
    return "usage: mockbuild.pl --mock-cfg <cfg> [--target-arch ARCH] [--result-dir DIR]\n"
         . "                    [--work-dir DIR] [--log-dir DIR] [--mock-uniqueext EXT]\n";
}
