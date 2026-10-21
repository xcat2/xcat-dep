#!/usr/bin/perl
# uftp/mockbuild.pl -- build the uftp RPM with mock from the committed UFTP release archive. The
# staged archive is checked against SHA256SUMS before the build, and the archive is never fetched.
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(basename);
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
use FindBin qw($RealBin);
use Getopt::Long qw(GetOptions);
use lib "$RealBin/..", "$RealBin/../lib";
use MockBuildUtils qw(resolve_mock_cfg);
use XCAT::BuildUtils qw(capture_command print_step require_command run_command shell_quote);

my $pkg_dir   = abs_path($RealBin);
my $repo_root = abs_path("$pkg_dir/..");
my $spec_file = "$pkg_dir/uftp.spec";

my $work_dir       = '/tmp/uftp-mockbuild';
my $mock_cfg       = '';
my $target_arch    = '';
my $mock_uniqueext = '';
my $result_dir     = "$repo_root/build-output/list3/uftp";
my $log_dir        = "$repo_root/build-logs/list3/uftp";
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
require_command($_) for qw(mock rpm bash sha256sum);

my ($version, @sources) = spec_sources($spec_file);
die "Could not parse Version from $spec_file\n" if !$version;

my $host_arch = capture_command('uname', '-m');
if (!$mock_cfg) {
    my $os_id = capture_command('bash', '-c', 'source /etc/os-release; echo $ID');
    $mock_cfg = resolve_mock_cfg($os_id, 10, $host_arch);
}
# A forcearch config such as rocky-10-riscv64-xcat builds rpms of another arch (BUILD.md "riscv64").
$target_arch = $host_arch if $target_arch eq '';
my @uniqueext = $mock_uniqueext ne '' ? ('--uniqueext', $mock_uniqueext) : ();

my $epoch = $build_timestamp;
if (!defined $epoch) {
    $epoch = `git -C \Q$repo_root\E log -1 --format=%ct HEAD 2>/dev/null` // '';
    chomp $epoch;
    $epoch = time() if $epoch !~ /^\d+$/;
}
$ENV{SOURCE_DATE_EPOCH} = $epoch;

print_step('Configuration');
print "pkg_dir:     $pkg_dir\n";
print "version:     $version\n";
print "work_dir:    $work_dir\n";
print "result_dir:  $result_dir\n";
print "log_dir:     $log_dir\n";
print "mock_cfg:    $mock_cfg\n";
print "target_arch: $target_arch\n";

print_step('Stage the sources');
remove_tree($work_dir) if -d $work_dir;
my $sources_dir = "$work_dir/sources";
make_path($sources_dir, $result_dir, $log_dir);
for my $source (@sources) {
    copy("$pkg_dir/$source", "$sources_dir/$source")
        or die "Failed to copy $pkg_dir/$source: $!\n";
}
run_command('bash', '-c', 'cd ' . shell_quote($sources_dir)
    . ' && sha256sum --check --strict ' . shell_quote("$pkg_dir/SHA256SUMS"));

my $det_cfg = "$work_dir/mock-deterministic.cfg";
open(my $cfg_fh, '>', $det_cfg) or die "Cannot write $det_cfg: $!\n";
print {$cfg_fh} "include('/etc/mock/${mock_cfg}.cfg')\n";
print {$cfg_fh} "config_opts['environment']['SOURCE_DATE_EPOCH'] = '$epoch'\n";
close($cfg_fh) or die "Cannot write $det_cfg: $!\n";
my @defines = map { ('--define', $_) }
    ('use_source_date_epoch_as_buildtime 1', 'clamp_mtime_to_source_date_epoch 1', '_buildhost xcat-build');

print_step('Build the SRPM with mock');
my $srpm_out = "$work_dir/srpm";
make_path($srpm_out);
run_mock('mock', '-r', $det_cfg, @uniqueext, '--buildsrpm', '--spec', $spec_file,
    '--sources', $sources_dir, '--resultdir', $srpm_out, @defines);
my @srpms = glob("$srpm_out/uftp-$version-*.src.rpm");
die "Expected one SRPM in $srpm_out, found " . scalar(@srpms) . "\n" if @srpms != 1;

print_step('Rebuild the RPM with mock');
my $rpm_out = "$work_dir/rpm";
make_path($rpm_out);
run_mock('mock', '-r', $det_cfg, @uniqueext, '--rebuild', $srpms[0], '--resultdir', $rpm_out, @defines);
my @rpms = glob("$rpm_out/*.$target_arch.rpm");
my @main = glob("$rpm_out/uftp-$version-*.$target_arch.rpm");
die "Expected one uftp $target_arch RPM in $rpm_out, found " . scalar(@main) . "\n" if @main != 1;

print_step('Check the RPM');
my $arch = capture_command('rpm', '-qp', '--qf', '%{ARCH}', $main[0]);
die "Unexpected RPM arch: $arch (expected $target_arch)\n" if $arch ne $target_arch;
my %payload = map { $_ => 1 } split(/\n/, capture_command('rpm', '-qpl', $main[0]));
my @missing = grep { !$payload{$_} } map { "/usr/bin/$_" } qw(uftp uftpd uftpproxyd uftp_keymgt);
die "Missing from the RPM payload: @missing\n" if @missing;
print "Checked: $main[0]\n";

print_step('Collect the results');
for my $file (@rpms, $srpms[0]) {
    copy($file, $result_dir) or die "Failed to copy $file to $result_dir: $!\n";
    print "Copied: $result_dir/" . basename($file) . "\n";
}
for my $log (qw(build.log root.log state.log)) {
    copy("$rpm_out/$log", "$log_dir/$log") if -f "$rpm_out/$log";
    copy("$srpm_out/$log", "$log_dir/srpm-$log") if -f "$srpm_out/$log";
}
print_step('Completed');
exit 0;

sub usage {
    return <<"USAGE";
Usage: $0 [options]
  --work-dir PATH          Temporary work directory (default: $work_dir)
  --mock-cfg NAME          Mock config (default: the EL10 config of this host)
  --target-arch ARCH       Arch of the rpms --mock-cfg produces (default: uname -m); a forcearch
                           config such as rocky-10-riscv64-xcat needs it
  --mock-uniqueext TEXT    mock --uniqueext suffix for concurrent builds
  --result-dir PATH        Output directory for the RPMs and SRPM
  --log-dir PATH           Output directory for the mock logs
  --build-timestamp EPOCH  SOURCE_DATE_EPOCH for a reproducible build
USAGE
}

sub spec_sources {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "Cannot read $path: $!\n";
    my ($version, @sources) = ('');
    while (my $line = <$fh>) {
        $version = $1 if $line =~ /^Version:\s*(\S+)/;
        push @sources, $1 if $line =~ /^(?:Source|Patch)\d*:\s*(\S+)/;
    }
    close($fh);
    s/%\{version\}/$version/g for @sources;
    return ($version, @sources);
}

# mock exits 30 when its package manager failed, most often a transient mirror error: retry once.
sub run_mock {
    my (@command) = @_;
    my $ok = eval { run_command(@command) };
    return 1 if $ok;
    die $@ if $@ !~ /\(rc=30\)/;
    print "mock failed with rc=30 (package manager); retrying once\n";
    return run_command(@command);
}
