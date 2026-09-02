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
my $noarch_mock_cfg = '';
my $target_arch = '';
my $mock_uniqueext = '';
my $keep_buildroots = 0;
my $result_dir = '';
my $log_dir    = '';
my $packages_csv = '';
my $epel_gap = 0;
my $jobs = 0;
my $build_timestamp;
# CD version bump: appended to the Release of the srpm-mode packages (HTML-Form, IO-Stty,
# Net-Telnet), which build from a committed .src.rpm and so are NOT covered by mockbuild-all's
# in-tree spec bump. Spec-mode packages get bumped in-tree upstream, so we leave those alone.
my $release_suffix = '';

GetOptions(
    'work-dir=s'      => \$work_dir,
    'mock-cfg=s'      => \$mock_cfg,
    'noarch-mock-cfg=s' => \$noarch_mock_cfg,
    'target-arch=s'   => \$target_arch,
    'mock-uniqueext=s' => \$mock_uniqueext,
    'keep-buildroots!' => \$keep_buildroots,
    'result-dir=s'    => \$result_dir,
    'log-dir=s'       => \$log_dir,
    'packages=s'      => \$packages_csv,
    'epel-gap!'       => \$epel_gap,
    'jobs=i'          => \$jobs,
    'build-timestamp=i' => \$build_timestamp,
    'release-suffix=s'  => \$release_suffix,
) or die usage();

die "Run as root (current uid=$>)\n" if $> != 0;

for my $bin (qw(mock rpmbuild rpm dnf perl bash grep)) {
    run("command -v " . sh_quote($bin) . " >/dev/null 2>&1");
}

my $arch = capture('uname -m');
if (!$mock_cfg) {
    my $os_id = capture(q{bash -lc 'source /etc/os-release; echo $ID'});
    $mock_cfg = resolve_mock_cfg($os_id, $arch);
}
# Arch of the rpms --mock-cfg produces: the host arch unless the config is a forcearch (cross)
# one, e.g. rocky-10-riscv64-xcat built on x86_64 (see BUILD.md "riscv64"). The noarch packages
# may be built in a native chroot of the same release instead of the emulated one (their rpms
# are identical for every arch and emulated builds are slow).
$target_arch = $arch if $target_arch eq '';
$noarch_mock_cfg = $mock_cfg if $noarch_mock_cfg eq '';
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

if (!$result_dir) {
    $result_dir = "$repo_root/build-output/list6/perl/$target_arch";
}
if (!$log_dir) {
    $log_dir = "$repo_root/build-logs/list6/perl/$target_arch";
}

my %meta = (
    'perl-Crypt-Blowfish' => {
        mode       => 'srpm',
        pkg_dir    => "$repo_root/perl-Crypt-Blowfish",
        srpm_globs => [
            "$repo_root/perl-Crypt-Blowfish/perl-Crypt-Blowfish-2.14-25.el10_0.src.rpm",
            "$repo_root/perl-Crypt-Blowfish/perl-Crypt-Blowfish-*.src.rpm",
        ],
        rpm_name   => 'perl-Crypt-Blowfish',
        rpm_arch   => 'native',
        module     => 'Crypt::Blowfish',
        needs      => ['perl-Crypt-CBC'],   # optional tests (BuildRequires)
    },
    'perl-Crypt-CBC' => {
        mode      => 'spec',
        pkg_dir   => "$repo_root/perl-Crypt-CBC",
        spec      => "$repo_root/perl-Crypt-CBC/perl-Crypt-CBC.spec",
        rpm_name  => 'perl-Crypt-CBC',
        rpm_arch  => 'noarch',
        module    => 'Crypt::CBC',
    },
    'perl-Crypt-Rijndael' => {
        mode       => 'srpm',
        pkg_dir    => "$repo_root/perl-Crypt-Rijndael",
        srpm_globs => [
            "$repo_root/perl-Crypt-Rijndael/perl-Crypt-Rijndael-1.13-10.fc29.src.rpm",
            "$repo_root/perl-Crypt-Rijndael/perl-Crypt-Rijndael-*.src.rpm",
        ],
        rpm_name   => 'perl-Crypt-Rijndael',
        rpm_arch   => 'native',
        module     => 'Crypt::Rijndael',
    },
    'perl-Crypt-SSLeay' => {
        mode      => 'spec',
        pkg_dir   => "$repo_root/perl-Crypt-SSLeay",
        spec      => "$repo_root/perl-Crypt-SSLeay/perl-Crypt-SSLeay.spec",
        rpm_name  => 'perl-Crypt-SSLeay',
        rpm_arch  => 'native',
        module    => 'Crypt::SSLeay',
        needs     => ['perl-Path-Class'],   # Makefile.PL (configure_requires), EPEL-only on EL
    },
    'perl-Digest-SHA1' => {
        mode       => 'srpm',
        pkg_dir    => "$repo_root/perl-Digest-SHA1",
        srpm_globs => [
            "$repo_root/perl-Digest-SHA1/perl-Digest-SHA1-2.13-23.fc28.src.rpm",
            "$repo_root/perl-Digest-SHA1/perl-Digest-SHA1-*.src.rpm",
        ],
        rpm_name   => 'perl-Digest-SHA1',
        rpm_arch   => 'native',
        module     => 'Digest::SHA1',
    },
    'perl-Expect' => {
        mode       => 'srpm',
        pkg_dir    => "$repo_root/perl-Expect",
        srpm_globs => [
            "$repo_root/perl-Expect/perl-Expect-1.35-6.fc29.src.rpm",
            "$repo_root/perl-Expect/perl-Expect-*.src.rpm",
        ],
        rpm_name   => 'perl-Expect',
        rpm_arch   => 'noarch',
        module     => 'Expect',
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
    'perl-Mail-Sender' => {
        mode       => 'srpm',
        pkg_dir    => "$repo_root/perl-Mail-Sender",
        srpm_globs => [
            "$repo_root/perl-Mail-Sender/perl-Mail-Sender-0.903-7.fc29.src.rpm",
            "$repo_root/perl-Mail-Sender/perl-Mail-Sender-*.src.rpm",
        ],
        rpm_name   => 'perl-Mail-Sender',
        rpm_arch   => 'noarch',
        module     => 'Mail::Sender',
    },
    'perl-Net-DNS' => {
        mode      => 'spec',
        pkg_dir   => "$repo_root/perl-Net-DNS",
        spec      => "$repo_root/perl-Net-DNS/Net-DNS.spec",
        rpm_name  => 'perl-Net-DNS',
        rpm_arch  => 'noarch',
        module    => 'Net::DNS',
    },
    'perl-Net-HTTPS-NB' => {
        mode      => 'spec',
        pkg_dir   => "$repo_root/perl-Net-HTTPS-NB",
        spec      => "$repo_root/perl-Net-HTTPS-NB/perl-Net-HTTPS-NB.spec",
        rpm_name  => 'perl-Net-HTTPS-NB',
        rpm_arch  => 'noarch',
        module    => 'Net::HTTPS::NB',
    },
    'perl-Net-IP' => {
        mode       => 'srpm',
        pkg_dir    => "$repo_root/perl-Net-IP",
        srpm_globs => [
            "$repo_root/perl-Net-IP/perl-Net-IP-1.26-30.el10_0.src.rpm",
            "$repo_root/perl-Net-IP/perl-Net-IP-*.src.rpm",
        ],
        rpm_name   => 'perl-Net-IP',
        rpm_arch   => 'noarch',
        module     => 'Net::IP',
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
    'perl-Path-Class' => {
        mode       => 'srpm',
        pkg_dir    => "$repo_root/perl-Path-Class",
        srpm_globs => [
            "$repo_root/perl-Path-Class/perl-Path-Class-0.37-24.el10_0.src.rpm",
            "$repo_root/perl-Path-Class/perl-Path-Class-*.src.rpm",
        ],
        rpm_name   => 'perl-Path-Class',
        rpm_arch   => 'noarch',
        module     => 'Path::Class',
    },
    'perl-SOAP-Lite' => {
        mode       => 'srpm',
        pkg_dir    => "$repo_root/perl-SOAP-Lite",
        srpm_globs => [
            "$repo_root/perl-SOAP-Lite/perl-SOAP-Lite-1.27-3.fc29.src.rpm",
            "$repo_root/perl-SOAP-Lite/perl-SOAP-Lite-*.src.rpm",
        ],
        rpm_name   => 'perl-SOAP-Lite',
        rpm_arch   => 'noarch',
        module     => 'SOAP::Lite',
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

# xcat-dep's own perl deps of xCAT, built for every EL and arch ("list6").
my @default_order = qw(
    perl-Crypt-SSLeay
    perl-HTML-Form
    perl-HTTP-Async
    perl-IO-Stty
    perl-Net-HTTPS-NB
    perl-Net-Telnet
    perl-Sys-Virt
);

# The perl deps of xCAT that EL takes from EPEL. Built only where there is no EPEL (riscv64,
# --epel-gap); the x86_64/ppc64le repos keep getting them from EPEL. perl-Path-Class is a
# build dep of perl-Crypt-SSLeay only. Not here although in the table: perl-SOAP-Lite (its
# fc29 BuildRequires IO::SessionData, MIME::Lite, XML::Parser::Lite, Test::XML are EPEL-only
# too, so it cannot be built or installed without EPEL; xCAT uses it for HP blades only).
my @epel_gap_order = qw(
    perl-Crypt-Blowfish
    perl-Crypt-CBC
    perl-Crypt-Rijndael
    perl-Digest-SHA1
    perl-Expect
    perl-Mail-Sender
    perl-Net-DNS
    perl-Net-IP
    perl-Path-Class
);

my @packages = @default_order;
push @packages, @epel_gap_order if $epel_gap;
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

make_path($result_dir);
make_path($log_dir);
make_path($work_dir);

print_step("Configuration");
print "repo_root:   $repo_root\n";
print "work_dir:    $work_dir\n";
print "result_dir:  $result_dir\n";
print "log_dir:     $log_dir\n";
print "arch:        $arch\n";
print "target_arch: $target_arch\n";
print "mock_cfg:    $mock_cfg\n";
print "noarch_mock_cfg: $noarch_mock_cfg\n";
print "mock_uniqueext: " . ($mock_uniqueext ne '' ? $mock_uniqueext : '(none)') . "\n";
print "epel_gap:    $epel_gap\n";
print "packages:    " . join(', ', @packages) . "\n";
print "jobs:        $jobs\n";
print "release_suffix:" . ($release_suffix ne '' ? $release_suffix : '(none)') . "\n";

print_step("Mock config check");
run("mock -r " . sh_quote($mock_cfg) . $mock_uniqueext_opt . " --print-root-path >/dev/null");
run("mock -r " . sh_quote($noarch_mock_cfg) . $mock_uniqueext_opt . " --print-root-path >/dev/null")
    if $noarch_mock_cfg ne $mock_cfg;

my @failed;
my @passed;
my @summary_lines;
my @built_roots;   # pkg + mock cfg + uniqueext of every chroot this run made

print_step("Build packages");
print "parallel jobs: $jobs\n";
my %child_rc;   # pkg => child exit code; the AUTHORITATIVE pass/fail for that build
my $pm = Parallel::ForkManager->new($jobs);
$pm->run_on_finish(
    sub {
        my ($pid, $exit_code, $ident) = @_;
        my $label = defined $ident ? $ident : "pid=$pid";
        $child_rc{$ident} = $exit_code if defined $ident;   # record it; do not trust status.txt alone
        my $state = $exit_code == 0 ? 'PASS' : "FAIL(rc=$exit_code)";
        print "[$label] $state\n";
    }
);

# A package that 'needs' others (see %meta) is built after them, with their rpms installed into
# its chroot, so the waves run one after the other; the packages of a wave build in parallel.
my %selected = map { $_ => 1 } @packages;
my $idx = 0;
for my $wave (build_waves(\@packages)) {
    for my $pkg (@{$wave}) {
        my $cfg = $meta{$pkg};
        my $pkg_uniqueext = package_uniqueext($mock_uniqueext, ++$idx, $pkg);
        my @needs = grep { $selected{$_} } @{ $cfg->{needs} // [] };

        # The noarch packages of a forcearch target build in the native chroot, so scrub the
        # chroot the package was actually built in.
        my $pkg_mock_cfg = $cfg->{rpm_arch} eq 'noarch' ? $noarch_mock_cfg : $mock_cfg;
        push @built_roots, { pkg => $pkg, mock_cfg => $pkg_mock_cfg, uniqueext => $pkg_uniqueext };

        my $pid = $pm->start($pkg);
        next if $pid;
        my $ok = build_package(
            pkg           => $pkg,
            cfg           => $cfg,
            work_dir      => $work_dir,
            result_dir    => $result_dir,
            log_dir       => $log_dir,
            mock_cfg      => $pkg_mock_cfg,
            mock_uniqueext => $pkg_uniqueext,
            arch          => $target_arch,
            host_arch     => $arch,
            needs         => \@needs,
            release_suffix => $release_suffix,
        );
        unless ($keep_buildroots) {
            # Reclaim ONLY this package's build chroot here (it's the ~GB disk hog). --scrub=chroot
            # is uniqueext-local, so it never touches a concurrent sibling. Do NOT --scrub=bootstrap
            # here: despite the --uniqueext, mock's bootstrap scrub removes the CONFIG-LEVEL shared
            # bootstrap cache (/var/cache/mock/<cfg>-bootstrap/, keyed by config name, NOT
            # uniqueext). Doing that mid-batch deletes the cache a still-starting sibling is about to
            # bind-mount into its own bootstrap root -> `mount rc=32` and a spurious build failure
            # (observed: perl-Sys-Virt's buildsrpm raced a faster sibling's post-build bootstrap
            # scrub). The shared bootstrap is reclaimed once below, after ALL workers finish, when
            # nothing can be binding it.
            (my $ps = $pkg) =~ s/[^\w.-]+/-/g;
            system("mock -r " . sh_quote($pkg_mock_cfg) . " --uniqueext " . sh_quote($pkg_uniqueext)
                 . " --scrub=chroot > " . sh_quote("$log_dir/scrub-$ps.log") . " 2>&1");
        }
        $pm->finish($ok ? 0 : 1);
    }
    $pm->wait_all_children;
}

# Now that every worker has exited, reclaim the per-uniqueext bootstrap roots + the shared
# config-level bootstrap cache. Serialized and post-join, so no scrub can race a concurrent
# bind (that race is exactly what the per-package note above avoids). Best-effort: the first
# scrub drops /var/cache/mock/<cfg>-bootstrap; each also removes its uniqueext bootstrap root.
unless ($keep_buildroots) {
    for my $root (@built_roots) {
        (my $ps = $root->{pkg}) =~ s/[^\w.-]+/-/g;
        system("mock -r " . sh_quote($root->{mock_cfg}) . " --uniqueext " . sh_quote($root->{uniqueext})
             . " --scrub=bootstrap >> " . sh_quote("$log_dir/scrub-$ps.log") . " 2>&1");
    }
}

for my $pkg (@packages) {
    my $status_file = "$log_dir/$pkg/status.txt";
    # The child exit code is authoritative: a package is PASS only if its worker exited 0 AND wrote
    # a PASS status this run. A missing/non-zero child result is FAIL regardless of any status.txt
    # (which could be a stale PASS left in a reused log dir, or unwritten because the worker crashed).
    my $rc = $child_rc{$pkg};
    if (!defined $rc || $rc != 0) {
        push @failed, $pkg;
        push @summary_lines, defined $rc
            ? "$pkg FAIL worker exited rc=$rc"
            : "$pkg FAIL no worker result recorded";
        next;
    }
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
print {$sfh} "noarch_mock_cfg=$noarch_mock_cfg\n" if $noarch_mock_cfg ne $mock_cfg;
print {$sfh} "mock_uniqueext=$mock_uniqueext\n" if $mock_uniqueext ne '';
print {$sfh} "arch=$target_arch\n";
print {$sfh} "result_dir=$result_dir\n";
print {$sfh} "log_dir=$log_dir\n";
print {$sfh} "epel_gap=$epel_gap\n";
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
    my $host_arch      = $args{host_arch} // $arch;
    my $needs          = $args{needs} // [];
    my $release_suffix = $args{release_suffix};

    my $pkg_run_dir = "$work_dir/$pkg";
    my $pkg_result  = "$result_dir/$pkg";
    my $pkg_log     = "$log_dir/$pkg";
    my $status_file = "$pkg_log/status.txt";

    remove_tree($pkg_run_dir) if -d $pkg_run_dir;
    make_path($pkg_run_dir);
    make_path($pkg_result);
    make_path($pkg_log);
    # Clear any status/error left by an earlier run in a reused log dir BEFORE building, so a crash
    # between here and the status write below can never leave a stale PASS the aggregate would trust.
    unlink $status_file, "$pkg_log/error.txt";

    my $det_mock_cfg = create_deterministic_mock_cfg($mock_cfg, $SOURCE_DATE_EPOCH, $pkg_run_dir);

    my $run_log = "$pkg_log/run.log";
    open my $runfh, '>', $run_log or die "Cannot write $run_log: $!\n";
    open STDOUT, '>&', $runfh or die "Cannot redirect stdout to $run_log: $!\n";
    open STDERR, '>&', $runfh or die "Cannot redirect stderr to $run_log: $!\n";
    select(STDOUT);
    $| = 1;

    my $mock_uniqueext_opt = ' --uniqueext ' . sh_quote($mock_uniqueext);
    print_step("Build $pkg");
    print "mock_cfg: $mock_cfg\n";
    print "mock_uniqueext: $mock_uniqueext\n";
    print "needs: " . (@{$needs} ? join(', ', @{$needs}) : '(none)') . "\n";

    my $summary = '';
    my $ok = 0;

    my $srpm_path = '';
    my $rebuild_result = "$pkg_run_dir/rpm";
    make_path($rebuild_result);

    eval {
        if ($cfg->{mode} eq 'srpm') {
            $srpm_path = select_srpm($cfg->{srpm_globs});
            die "Could not locate source RPM for $pkg\n" if !$srpm_path;
            # CD version bump: these packages build from a committed .src.rpm, so the in-tree
            # spec Release bump (mockbuild-all) never reaches them. Re-stamp here: unpack the
            # srpm, append the suffix to its spec's Release (KEEPING %{?dist}, exactly like the
            # spec-mode packages -> e.g. 19%{?dist} -> 19%{?dist}.snap...N), and roll a fresh
            # srpm. With no suffix (non-CD run), rebuild the committed srpm unchanged.
            if ($release_suffix ne '') {
                my $ext = "$pkg_run_dir/restamp";
                for my $d (qw(BUILD BUILDROOT RPMS SOURCES SPECS SRPMS)) { make_path("$ext/$d"); }
                run("rpm -i --define " . sh_quote("_topdir $ext") . ' ' . sh_quote($srpm_path)
                    . " > " . sh_quote("$pkg_log/srpm-unpack.log") . " 2>&1");
                my ($espec) = sort glob("$ext/SPECS/*.spec");
                die "No spec found after unpacking srpm for $pkg\n" if !$espec;
                append_release_suffix($espec, $release_suffix);
                my $restamp_result = "$pkg_run_dir/restamp-srpm";
                make_path($restamp_result);
                run(
                    "mock -r " . sh_quote($det_mock_cfg) . $mock_uniqueext_opt .
                    " --buildsrpm --spec " . sh_quote($espec) .
                    " --sources " . sh_quote("$ext/SOURCES") .
                    " --define " . sh_quote("use_source_date_epoch_as_buildtime 1") .
                    " --define " . sh_quote("clamp_mtime_to_source_date_epoch 1") .
                    " --define " . sh_quote("_buildhost xcat-build") .
                    " --resultdir " . sh_quote($restamp_result) .
                    " > " . sh_quote("$pkg_log/mock-restamp-buildsrpm.log") . " 2>&1"
                );
                my @restamped = sort glob("$restamp_result/*.src.rpm");
                die "No re-stamped SRPM produced for $pkg in $restamp_result\n" if !@restamped;
                $srpm_path = $restamped[-1];
            }
        } else {
            my $spec = $cfg->{spec};
            die "Missing spec for $pkg: $spec\n" if !-f $spec;
            my $source_dir = $cfg->{pkg_dir};
            die "Missing source directory for $pkg: $source_dir\n" if !-d $source_dir;

            my ($version, @assets) = parse_spec($spec);
            die "Could not parse Version from $spec\n" if !$version;
            my %source_urls = resolve_source_urls($spec);
            for my $asset (@assets) {
                my $asset_path = "$source_dir/$asset";
                if (!-f $asset_path && exists $source_urls{$asset}) {
                    my $url = $source_urls{$asset};
                    print "Downloading $asset from $url\n";
                    my $rc = system("wget -q -O " . sh_quote($asset_path) . " " . sh_quote($url));
                    if ($rc != 0) {
                        unlink $asset_path if -f $asset_path;
                        die "Failed to download Source asset for $pkg: wget $url (rc=" . ($rc >> 8) . ")\n";
                    }
                }
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
            run_mock(
                "mock -r " . sh_quote($det_mock_cfg) . $mock_uniqueext_opt .
                " --buildsrpm --spec " . sh_quote($spec) .
                " --sources " . sh_quote($source_dir) .
                " --define " . sh_quote("use_source_date_epoch_as_buildtime 1") .
                " --define " . sh_quote("clamp_mtime_to_source_date_epoch 1") .
                " --define " . sh_quote("_buildhost xcat-build") .
                " --resultdir " . sh_quote($srpm_result) .
                " > " . sh_quote("$pkg_log/mock-buildsrpm.log") . " 2>&1"
            );
            my @srpms = sort glob("$srpm_result/*.src.rpm");
            die "No SRPM produced for $pkg in $srpm_result\n" if !@srpms;
            $srpm_path = $srpms[-1];
        }

        # The rpms of the packages this one needs (built in an earlier wave) go into the chroot
        # on top of the build requirements the chroot resolves itself.
        my $additional_opt = '';
        for my $need (@{$needs}) {
            my @need_rpms = grep { !/\.src\.rpm$/ && !/-debug(?:info|source)-/ }
                            sort glob("$result_dir/$need/*.rpm");
            die "Needed package $need left no rpms in $result_dir/$need (build failed?)\n" if !@need_rpms;
            $additional_opt .= " --additional-package " . sh_quote($_) for @need_rpms;
        }

        run_mock(
            "mock -r " . sh_quote($det_mock_cfg) . $mock_uniqueext_opt .
            " --rebuild " . sh_quote($srpm_path) . $additional_opt .
            " --define " . sh_quote("use_source_date_epoch_as_buildtime 1") .
            " --define " . sh_quote("clamp_mtime_to_source_date_epoch 1") .
            " --define " . sh_quote("_buildhost xcat-build") .
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

        if ($cfg->{rpm_arch} eq 'native' && $arch ne $host_arch) {
            # A cross-built XS module cannot be loaded on this host: install the rpm into the
            # (emulated) build chroot and import the module there.
            my $module = $cfg->{module};
            run_mock(
                "mock -r " . sh_quote($det_mock_cfg) . $mock_uniqueext_opt .
                " --install " . sh_quote($main_rpm) .
                " > " . sh_quote("$pkg_log/smoke-chroot-install.log") . " 2>&1"
            );
            my $rc_mod = run_capture_rc(
                "mock -r " . sh_quote($det_mock_cfg) . $mock_uniqueext_opt .
                " -q --chroot -- perl -M$module -e 1",
                "$pkg_log/smoke-perl-module.log");
            die "Perl module import failed for $pkg ($module) in the $arch chroot, rc=$rc_mod\n" if $rc_mod != 0;
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

# Order the selected packages in waves: a package comes after the selected packages it 'needs'
# (installed into its chroot, see %meta). Needs outside the selection are ignored: the chroot
# then has to provide the module itself (e.g. from EPEL).
sub build_waves {
    my ($pkgs) = @_;
    my %selected = map { $_ => 1 } @{$pkgs};
    my %done;
    my @waves;
    my @left = @{$pkgs};
    while (@left) {
        my @ready = grep {
            my $p = $_;
            !grep { $selected{$_} && !$done{$_} } @{ $meta{$p}{needs} // [] };
        } @left;
        die "Circular 'needs' among packages: @left\n" if !@ready;
        push @waves, \@ready;
        $done{$_} = 1 for @ready;
        @left = grep { !$done{$_} } @left;
    }
    return @waves;
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
  --noarch-mock-cfg NAME  Mock config for the noarch packages (default: --mock-cfg); with a
                       forcearch --mock-cfg, a native config of the same release builds them
                       without emulation
  --target-arch ARCH   Arch of the rpms --mock-cfg produces (default: uname -m); a forcearch
                       config such as rocky-10-riscv64-xcat needs it
  --mock-uniqueext TXT Optional mock --uniqueext suffix to isolate concurrent builds
  --jobs N             Number of parallel package workers (default: selected package count)
  --result-dir PATH    Output directory (default: build-output/list6/perl/<ARCH>)
  --log-dir PATH       Log directory (default: build-logs/list6/perl/<ARCH>)
  --packages LIST      Comma-separated subset of packages to build
  --epel-gap           Also build the perl deps of xCAT that EL takes from EPEL (for an arch
                       without EPEL, e.g. riscv64)
  --build-timestamp EPOCH  Unix epoch for SOURCE_DATE_EPOCH (deterministic builds)
  --release-suffix STR CD bump appended to the Release of the srpm-mode packages that build
                       from a committed .src.rpm (HTML-Form, IO-Stty, Net-Telnet)
USAGE
}

# Append $suffix (e.g. ".snap202607161200.57") to the first Release: line of $spec, in place.
# Mirrors mockbuild-all's bump_dep_release_suffix: case-insensitive (some specs use lowercase
# `release:`), preserves any %{?dist} macro on the line, and is idempotent (a line already
# carrying this exact suffix is left as-is).
sub append_release_suffix {
    my ($spec, $suffix) = @_;
    my $qs = quotemeta($suffix);
    open my $in, '<', $spec or die "open $spec: $!\n";
    my @lines = <$in>;
    close $in;
    my $changed = 0;
    for my $line (@lines) {
        next unless $line =~ /^Release:\s*\S/i;
        last if $line =~ /$qs\s*$/;          # already stamped
        $line =~ s/(^Release:\s*\S+)/$1$suffix/i;
        $changed = 1;
        last;                                 # only the first Release: line
    }
    die "No Release: line to stamp in $spec\n" if !$changed && !grep { /^Release:\s*\S/i } @lines;
    return if !$changed;
    open my $out, '>', $spec or die "open> $spec: $!\n";
    print {$out} @lines;
    close $out;
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
    my ($os_id, $arch) = @_;
    my %short_forms = (
        almalinux => 'alma',
        centos    => 'centos-stream',
        rocky     => 'rocky',
        fedora    => 'fedora',
    );
    my $candidate = "${os_id}+epel-10-${arch}";
    my $rc = system("mock -r " . sh_quote($candidate) . " --print-root-path >/dev/null 2>&1");
    if ($rc == 0) {
        print "Mock config resolved: $candidate\n";
        return $candidate;
    }
    if (exists $short_forms{$os_id}) {
        my $short = $short_forms{$os_id};
        $candidate = "${short}+epel-10-${arch}";
        $rc = system("mock -r " . sh_quote($candidate) . " --print-root-path >/dev/null 2>&1");
        if ($rc == 0) {
            print "Mock config resolved (short form): $candidate\n";
            return $candidate;
        }
    }
    $candidate = "${os_id}+epel-10-${arch}";
    print "WARN: Could not verify mock config, using default: $candidate\n";
    return $candidate;
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

sub resolve_source_urls {
    my ($spec_path) = @_;
    open my $fh, '<', $spec_path or return ();

    my $version = '';
    my %macros;
    my %urls;
    while (my $line = <$fh>) {
        if ($line =~ /^\s*%(?:global|define)\s+([A-Za-z0-9_]+)\s+(.+?)\s*$/) {
            my ($k, $v) = ($1, $2);
            $v =~ s/\s+#.*$//;
            $macros{$k} = $v;
        }
        if ($line =~ /^Version:\s*(\S+)/i) {
            $version = $1;
        }
        if ($line =~ /^Source\d*:\s*(\S+)/i) {
            my $raw = $1;
            if ($raw =~ m{^[a-zA-Z][a-zA-Z0-9+.-]*://}) {
                my $url = $raw;
                $macros{version} = $version if $version ne '';
                $macros{ver} = $version if $version ne '';
                for my $i (1 .. 6) {
                    my $changed = 0;
                    for my $k (keys %macros) {
                        my $before = $url;
                        $url =~ s/%\{$k\}/$macros{$k}/g;
                        $changed = 1 if $url ne $before;
                    }
                    last if !$changed;
                }
                my $filename = basename($url);
                $filename =~ s/\?.*$//;
                $urls{$filename} = $url;
            }
        }
    }
    close $fh;
    return %urls;
}
