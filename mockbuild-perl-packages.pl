#!/usr/bin/perl

use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname basename);
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
use Getopt::Long qw(GetOptions);
use Parallel::ForkManager;

my $repo_root = abs_path(dirname(__FILE__));
my $work_dir  = '/tmp/perl-list6-mockbuild';
my $mock_cfg  = '';
my $mock_uniqueext = '';
my $result_dir = '';
my $log_dir    = '';
my $packages_csv = '';
my $jobs = 0;
my $skip_install = 0;
my $allow_erasing = 0;

GetOptions(
    'work-dir=s'      => \$work_dir,
    'mock-cfg=s'      => \$mock_cfg,
    'mock-uniqueext=s' => \$mock_uniqueext,
    'result-dir=s'    => \$result_dir,
    'log-dir=s'       => \$log_dir,
    'packages=s'      => \$packages_csv,
    'jobs=i'          => \$jobs,
    'skip-install!'   => \$skip_install,
    'allow-erasing!'  => \$allow_erasing,
) or die usage();

die "Run as root (current uid=$>)\n" if $> != 0;

for my $bin (qw(mock rpmbuild rpm dnf perl bash grep)) {
    run("command -v " . sh_quote($bin) . " >/dev/null 2>&1");
}

my $arch = capture('uname -m');
if (!$mock_cfg) {
    my $os_id = capture(q{bash -lc 'source /etc/os-release; echo $ID'});
    $mock_cfg = "${os_id}+epel-10-${arch}";
}
my $mock_uniqueext_opt = $mock_uniqueext ne ''
    ? ' --uniqueext ' . sh_quote($mock_uniqueext)
    : '';
if (!$result_dir) {
    $result_dir = "$repo_root/build-output/list6/perl/$arch";
}
if (!$log_dir) {
    $log_dir = "$repo_root/build-logs/list6/perl/$arch";
}

my %meta = (
    'perl-Crypt-SSLeay' => {
        mode      => 'spec',
        pkg_dir   => "$repo_root/perl-Crypt-SSLeay",
        spec      => "$repo_root/perl-Crypt-SSLeay/perl-Crypt-SSLeay.spec",
        rpm_name  => 'perl-Crypt-SSLeay',
        rpm_arch  => 'native',
        module    => 'Crypt::SSLeay',
    },
    'perl-HTML-Form' => {
        mode       => 'srpm',
        pkg_dir    => "$repo_root/perl-HTML-Form",
        srpm_globs => [
            "$repo_root/perl-HTML-Form/perl-HTML-Form-6.07-4.fc34.src.rpm",
            "$repo_root/perl-HTML-Form/perl-HTML-Form-*.src.rpm",
        ],
        rpm_name   => 'perl-HTML-Form',
        rpm_arch   => 'noarch',
        module     => 'HTML::Form',
    },
    'perl-HTTP-Async' => {
        mode      => 'spec',
        pkg_dir   => "$repo_root/perl-HTTP-Async",
        spec      => "$repo_root/perl-HTTP-Async/perl-HTTP-Async.spec",
        rpm_name  => 'perl-HTTP-Async',
        rpm_arch  => 'noarch',
        module    => 'HTTP::Async',
    },
    'perl-IO-Stty' => {
        mode       => 'srpm',
        pkg_dir    => "$repo_root/perl-IO-Stty",
        srpm_globs => [
            "$repo_root/perl-IO-Stty/perl-IO-Stty-0.04-5.fc34.src.rpm",
            "$repo_root/perl-IO-Stty/perl-IO-Stty-*.src.rpm",
        ],
        rpm_name   => 'perl-IO-Stty',
        rpm_arch   => 'noarch',
        module     => 'IO::Stty',
    },
    'perl-Net-HTTPS-NB' => {
        mode      => 'spec',
        pkg_dir   => "$repo_root/perl-Net-HTTPS-NB",
        spec      => "$repo_root/perl-Net-HTTPS-NB/perl-Net-HTTPS-NB.spec",
        rpm_name  => 'perl-Net-HTTPS-NB',
        rpm_arch  => 'noarch',
        module    => 'Net::HTTPS::NB',
    },
    'perl-Net-Telnet' => {
        mode       => 'srpm',
        pkg_dir    => "$repo_root/perl-Net-Telnet",
        srpm_globs => [
            "$repo_root/perl-Net-Telnet/perl-Net-Telnet-3.04-16.fc34.src.rpm",
            "$repo_root/perl-Net-Telnet/perl-Net-Telnet-*.src.rpm",
        ],
        rpm_name   => 'perl-Net-Telnet',
        rpm_arch   => 'noarch',
        module     => 'Net::Telnet',
    },
    'perl-Sys-Virt' => {
        mode      => 'spec',
        pkg_dir   => "$repo_root/perl-Sys-Virt",
        spec      => "$repo_root/perl-Sys-Virt/Sys-Virt.spec",
        rpm_name  => 'perl-Sys-Virt',
        rpm_arch  => 'native',
        module    => 'Sys::Virt',
    },
);

my @default_order = qw(
    perl-Crypt-SSLeay
    perl-HTML-Form
    perl-HTTP-Async
    perl-IO-Stty
    perl-Net-HTTPS-NB
    perl-Net-Telnet
    perl-Sys-Virt
);

my @packages = @default_order;
if ($packages_csv ne '') {
    @packages = grep { $_ ne '' } map { s/^\s+|\s+$//gr } split /,/, $packages_csv;
}

for my $pkg (@packages) {
    die "Unknown package in --packages: $pkg\n" if !exists $meta{$pkg};
}

if ($jobs <= 0) {
    $jobs = scalar(@packages);
}
$jobs = 1 if $jobs < 1;
if (@packages && $jobs > scalar(@packages)) {
    $jobs = scalar(@packages);
}
if (!$skip_install && $jobs > 1) {
    print "INFO: --skip-install is disabled; forcing --jobs 1 to avoid host dnf lock contention\n";
    $jobs = 1;
}

make_path($result_dir);
make_path($log_dir);
make_path($work_dir);

print_step("Configuration");
print "repo_root:   $repo_root\n";
print "work_dir:    $work_dir\n";
print "result_dir:  $result_dir\n";
print "log_dir:     $log_dir\n";
print "arch:        $arch\n";
print "mock_cfg:    $mock_cfg\n";
print "mock_uniqueext: " . ($mock_uniqueext ne '' ? $mock_uniqueext : '(none)') . "\n";
print "packages:    " . join(', ', @packages) . "\n";
print "jobs:        $jobs\n";
print "skip_install:$skip_install\n";
print "allow_erasing:$allow_erasing\n";

print_step("Mock config check");
run("mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt . " --print-root-path >/dev/null");

my @failed;
my @passed;
my @summary_lines;

print_step("Build packages");
print "parallel jobs: $jobs\n";
my $pm = Parallel::ForkManager->new($jobs);
$pm->run_on_finish(
    sub {
        my ($pid, $exit_code, $ident) = @_;
        my $label = defined $ident ? $ident : "pid=$pid";
        my $state = $exit_code == 0 ? 'PASS' : "FAIL(rc=$exit_code)";
        print "[$label] $state\n";
    }
);

for my $idx (0 .. $#packages) {
    my $pkg = $packages[$idx];
    my $cfg = $meta{$pkg};
    my $pkg_uniqueext = package_uniqueext($mock_uniqueext, $idx + 1, $pkg);

    my $pid = $pm->start($pkg);
    next if $pid;
    my $ok = build_package(
        pkg           => $pkg,
        cfg           => $cfg,
        work_dir      => $work_dir,
        result_dir    => $result_dir,
        log_dir       => $log_dir,
        mock_cfg      => $mock_cfg,
        mock_uniqueext => $pkg_uniqueext,
        arch          => $arch,
        skip_install  => $skip_install,
        allow_erasing => $allow_erasing,
    );
    $pm->finish($ok ? 0 : 1);
}
$pm->wait_all_children;

for my $pkg (@packages) {
    my $status_file = "$log_dir/$pkg/status.txt";
    if (!-f $status_file) {
        push @failed, $pkg;
        push @summary_lines, "$pkg FAIL missing status file ($status_file)";
        next;
    }
    my $line = slurp($status_file);
    $line =~ s/\r?\n.*$//s;
    my ($status, $summary) = split /\t/, $line, 2;
    if (!defined $status || !defined $summary || ($status ne 'PASS' && $status ne 'FAIL')) {
        $status = 'FAIL';
        $summary = "$pkg FAIL malformed status line in $status_file";
    }
    if ($status eq 'PASS') {
        push @passed, $pkg;
    } else {
        push @failed, $pkg;
    }
    push @summary_lines, $summary;
}

open my $sfh, '>', "$log_dir/build-summary.txt"
    or die "Cannot write $log_dir/build-summary.txt: $!\n";
print {$sfh} "mock_cfg=$mock_cfg\n";
print {$sfh} "mock_uniqueext=$mock_uniqueext\n" if $mock_uniqueext ne '';
print {$sfh} "arch=$arch\n";
print {$sfh} "result_dir=$result_dir\n";
print {$sfh} "log_dir=$log_dir\n";
print {$sfh} "packages=" . join(',', @packages) . "\n";
print {$sfh} "passed=" . join(',', @passed) . "\n";
print {$sfh} "failed=" . join(',', @failed) . "\n";
print {$sfh} "$_\n" for @summary_lines;
close $sfh;

print_step("Completed");
print "Passed: " . join(', ', @passed) . "\n" if @passed;
print "Failed: " . join(', ', @failed) . "\n" if @failed;
print "Artifacts: $result_dir\n";
print "Logs: $log_dir\n";

exit(@failed ? 1 : 0);

sub build_package {
    my (%args) = @_;
    my $pkg            = $args{pkg};
    my $cfg            = $args{cfg};
    my $work_dir       = $args{work_dir};
    my $result_dir     = $args{result_dir};
    my $log_dir        = $args{log_dir};
    my $mock_cfg       = $args{mock_cfg};
    my $mock_uniqueext = $args{mock_uniqueext};
    my $arch           = $args{arch};
    my $skip_install   = $args{skip_install};
    my $allow_erasing  = $args{allow_erasing};

    my $pkg_run_dir = "$work_dir/$pkg";
    my $pkg_result  = "$result_dir/$pkg";
    my $pkg_log     = "$log_dir/$pkg";
    my $status_file = "$pkg_log/status.txt";

    remove_tree($pkg_run_dir) if -d $pkg_run_dir;
    make_path($pkg_run_dir);
    make_path($pkg_result);
    make_path($pkg_log);

    my $run_log = "$pkg_log/run.log";
    open my $runfh, '>', $run_log or die "Cannot write $run_log: $!\n";
    open STDOUT, '>&', $runfh or die "Cannot redirect stdout to $run_log: $!\n";
    open STDERR, '>&', $runfh or die "Cannot redirect stderr to $run_log: $!\n";
    select(STDOUT);
    $| = 1;

    my $mock_uniqueext_opt = ' --uniqueext ' . sh_quote($mock_uniqueext);
    print_step("Build $pkg");
    print "mock_uniqueext: $mock_uniqueext\n";

    my $summary = '';
    my $ok = 0;

    my $srpm_path = '';
    my $rebuild_result = "$pkg_run_dir/rpm";
    make_path($rebuild_result);

    eval {
        if ($cfg->{mode} eq 'srpm') {
            $srpm_path = select_srpm($cfg->{srpm_globs});
            die "Could not locate source RPM for $pkg\n" if !$srpm_path;
        } else {
            my $spec = $cfg->{spec};
            die "Missing spec for $pkg: $spec\n" if !-f $spec;
            my $source_dir = $cfg->{pkg_dir};
            die "Missing source directory for $pkg: $source_dir\n" if !-d $source_dir;

            my ($version, @assets) = parse_spec($spec);
            die "Could not parse Version from $spec\n" if !$version;
            for my $asset (@assets) {
                my $asset_path = "$source_dir/$asset";
                die "Missing Source/Patch asset for $pkg: $asset_path\n" if !-f $asset_path;
            }

            my $prep_top = "$pkg_run_dir/prep";
            for my $d (qw(BUILD BUILDROOT RPMS SOURCES SPECS SRPMS)) {
                make_path("$prep_top/$d");
            }
            my $prep_spec = "$prep_top/SPECS/" . basename($spec);
            copy($spec, $prep_spec) or die "Failed to copy prep spec for $pkg: $!\n";
            for my $asset (@assets) {
                copy("$source_dir/$asset", "$prep_top/SOURCES/$asset")
                    or die "Failed to stage prep asset $asset for $pkg: $!\n";
            }
            run(
                "rpmbuild --define " . sh_quote("_topdir $prep_top") .
                " -bp --nodeps " . sh_quote($prep_spec) .
                " > " . sh_quote("$pkg_log/prep.log") . " 2>&1"
            );

            my $srpm_result = "$pkg_run_dir/srpm";
            make_path($srpm_result);
            run(
                "mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt .
                " --buildsrpm --spec " . sh_quote($spec) .
                " --sources " . sh_quote($source_dir) .
                " --resultdir " . sh_quote($srpm_result) .
                " > " . sh_quote("$pkg_log/mock-buildsrpm.log") . " 2>&1"
            );
            my @srpms = sort glob("$srpm_result/*.src.rpm");
            die "No SRPM produced for $pkg in $srpm_result\n" if !@srpms;
            $srpm_path = $srpms[-1];
        }

        run(
            "mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt .
            " --rebuild " . sh_quote($srpm_path) .
            " --resultdir " . sh_quote($rebuild_result) .
            " > " . sh_quote("$pkg_log/mock-rebuild.log") . " 2>&1"
        );

        my @rpms = sort glob("$rebuild_result/*.rpm");
        die "No RPMs generated for $pkg in $rebuild_result\n" if !@rpms;

        my $main_rpm = '';
        for my $rpm (@rpms) {
            next if $rpm =~ /\.src\.rpm$/;
            my $name  = capture("rpm -qp --qf '%{NAME}' " . sh_quote($rpm));
            my $rarch = capture("rpm -qp --qf '%{ARCH}' " . sh_quote($rpm));
            next if $name ne $cfg->{rpm_name};
            if ($cfg->{rpm_arch} eq 'noarch' && $rarch eq 'noarch') {
                $main_rpm = $rpm;
                last;
            }
            if ($cfg->{rpm_arch} eq 'native' && $rarch eq $arch) {
                $main_rpm = $rpm;
                last;
            }
        }
        die "Could not find main RPM for $pkg in $rebuild_result\n" if !$main_rpm;

        run("rpm -qpl " . sh_quote($main_rpm) . " > " . sh_quote("$pkg_log/payload.list"));
        my $payload = slurp("$pkg_log/payload.list");
        die "Empty payload list for $pkg main RPM\n" if $payload !~ m{^/}m;

        for my $rpm (@rpms) {
            copy($rpm, $pkg_result) or die "Failed to copy $rpm to $pkg_result: $!\n";
        }
        copy($srpm_path, $pkg_result) or die "Failed to copy $srpm_path to $pkg_result: $!\n";

        for my $log (qw(build.log root.log state.log hw_info.log installed_pkgs.log)) {
            my $src = "$rebuild_result/$log";
            next if !-f $src;
            copy($src, "$pkg_log/$log") or die "Failed to copy $src to $pkg_log: $!\n";
        }
        if (-d "$pkg_run_dir/srpm") {
            for my $log (qw(build.log root.log state.log hw_info.log installed_pkgs.log)) {
                my $src = "$pkg_run_dir/srpm/$log";
                next if !-f $src;
                copy($src, "$pkg_log/srpm-$log") or die "Failed to copy $src to $pkg_log: $!\n";
            }
        }

        if (!$skip_install) {
            my $install_cmd = "dnf -y install ";
            $install_cmd .= "--allowerasing " if $allow_erasing;
            run($install_cmd . sh_quote($main_rpm));
            my $module = $cfg->{module};
            my $rc_mod = run_capture_rc("perl -M$module -e 1", "$pkg_log/smoke-perl-module.log");
            die "Perl module import failed for $pkg ($module), rc=$rc_mod\n" if $rc_mod != 0;
        }

        $summary = "$pkg PASS main_rpm=" . basename($main_rpm);
        $ok = 1;
    };

    if ($@) {
        my $err = $@;
        chomp $err;
        $err =~ s/\s+/ /g;
        $summary = "$pkg FAIL $err";
        open my $efh, '>', "$pkg_log/error.txt" or die "Cannot write $pkg_log/error.txt: $!\n";
        print {$efh} "$err\n";
        close $efh;
        print "ERROR: $err\n";
    }

    open my $sfh, '>', $status_file or die "Cannot write $status_file: $!\n";
    print {$sfh} (($ok ? 'PASS' : 'FAIL') . "\t$summary\n");
    close $sfh;
    return $ok;
}

sub package_uniqueext {
    my ($base, $index, $pkg) = @_;
    my $tag = lc $pkg;
    $tag =~ s/[^a-z0-9]+/-/g;
    $tag =~ s/^-+|-+$//g;
    $tag = "pkg$index" if $tag eq '';
    my $prefix = $base ne '' ? $base : "perl-list6-$$";
    my $value = "${prefix}-${index}-${tag}";
    $value =~ s/[^A-Za-z0-9_.-]+/-/g;
    return $value;
}

sub usage {
    return <<"USAGE";
Usage: $0 [options]
  --work-dir PATH      Temporary work dir (default: $work_dir)
  --mock-cfg NAME      Mock config (default: <ID>+epel-10-<ARCH>)
  --mock-uniqueext TXT Optional mock --uniqueext suffix to isolate concurrent builds
  --jobs N             Number of parallel package workers (default: selected package count)
  --result-dir PATH    Output directory (default: build-output/list6/perl/<ARCH>)
  --log-dir PATH       Log directory (default: build-logs/list6/perl/<ARCH>)
  --packages LIST      Comma-separated subset of packages to build
  --skip-install       Skip dnf install + perl module import checks
  --allow-erasing      Allow dnf to erase conflicting packages during install smoke tests
USAGE
}

sub select_srpm {
    my ($globs_ref) = @_;
    for my $g (@{$globs_ref}) {
        my @matches = sort glob($g);
        next if !@matches;
        return $matches[-1];
    }
    return '';
}

sub parse_spec {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot open spec $path: $!\n";

    my $version = '';
    my %macros;
    my @assets;
    while (my $line = <$fh>) {
        if ($line =~ /^\s*%(?:global|define)\s+([A-Za-z0-9_]+)\s+(.+?)\s*$/) {
            my ($k, $v) = ($1, $2);
            $v =~ s/\s+#.*$//;
            $macros{$k} = $v;
        }
        if ($line =~ /^Version:\s*(\S+)/i) {
            $version = $1;
        }
        if ($line =~ /^(?:Source|Patch)\d*:\s*(\S+)/i) {
            my $asset = $1;
            push @assets, $asset;
        }
    }
    close $fh;

    $macros{version} = $version if $version ne '';
    $macros{ver} = $version if $version ne '';

    @assets = map {
        my $v = $_;
        for my $i (1 .. 6) {
            my $changed = 0;
            for my $k (keys %macros) {
                my $before = $v;
                $v =~ s/%\{$k\}/$macros{$k}/g;
                $changed = 1 if $v ne $before;
            }
            last if !$changed;
        }
        if ($v =~ m{^[a-zA-Z][a-zA-Z0-9+.-]*://}) {
            $v = basename($v);
        }
        $v =~ s/\?.*$//;
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
