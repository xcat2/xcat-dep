#!/usr/bin/perl

use strict;
use warnings;

use Cwd qw(abs_path cwd);
use File::Basename qw(dirname basename);
use File::Copy qw(copy);
use File::Find qw(find);
use File::Path qw(make_path);
use Getopt::Long qw(GetOptions);
use Parallel::ForkManager;
use POSIX qw(strftime);

my $script_dir = abs_path(dirname(__FILE__));
my $repo_root  = abs_path($script_dir);
my $xcat_src   = "$repo_root/xcat-source-code";
my $output_root = "$repo_root/build-output/mockbuild-all";
my $target     = '';
my $nproc      = 1;
my $parallel_builds;
my $run_id     = strftime('%Y%m%d-%H%M%S', localtime);
my $skip_install = 0;
my $skip_build = 0;
my $skip_xcat_dep = 0;
my $skip_perl = 0;
my $skip_xcat = 0;
my $skip_createrepo = 0;
my $skip_tarball = 0;
my $skip_dhcp = 0;
my $scrub_all_chroots = 0;
my $dry_run = 0;
my $dhcp_repo_url = 'https://github.com/VersatusHPC/rpms-dhcp.git';
my $dhcp_repo_ref = 'master';
my $dhcp_source_dir = '';
my @extra_collect_dirs;

GetOptions(
    'repo-root=s'       => \$repo_root,
    'xcat-source=s'     => \$xcat_src,
    'output-root=s'     => \$output_root,
    'target=s'          => \$target,
    'nproc=i'           => \$nproc,
    'parallel-builds=i' => \$parallel_builds,
    'run-id=s'          => \$run_id,
    'skip-install!'     => \$skip_install,
    'skip-build!'       => \$skip_build,
    'skip-xcat-dep!'    => \$skip_xcat_dep,
    'skip-perl!'        => \$skip_perl,
    'skip-xcat!'        => \$skip_xcat,
    'skip-createrepo!'  => \$skip_createrepo,
    'skip-tarball!'     => \$skip_tarball,
    'skip-dhcp!'        => \$skip_dhcp,
    'scrub-all-chroots!' => \$scrub_all_chroots,
    'dhcp-repo-url=s'   => \$dhcp_repo_url,
    'dhcp-repo-ref=s'   => \$dhcp_repo_ref,
    'dhcp-source-dir=s' => \$dhcp_source_dir,
    'collect-dir=s@'    => \@extra_collect_dirs,
    'dry-run!'          => \$dry_run,
) or die usage();

die "Run as root (uid=$>)\n" if $> != 0;
die "--parallel-builds must be >= 1\n"
    if defined($parallel_builds) && $parallel_builds < 1;

$repo_root = abs_path($repo_root);
$xcat_src  = resolve_xcat_source($xcat_src, $repo_root);

my $arch = capture('uname -m');
my %os = read_os_release('/etc/os-release');
my $os_id = $os{ID} // '';
my $version_id = $os{VERSION_ID} // '';
my ($rel) = $version_id =~ /^(\d+)/;

die "Could not resolve ID from /etc/os-release\n" if $os_id eq '';
die "Could not resolve major release from VERSION_ID='$version_id' in /etc/os-release\n"
    if !defined($rel) || $rel eq '';

if (!$target) {
    $target = "${os_id}+epel-${rel}-${arch}";
}
my $target_rel = parse_target_rel($target);
my $dhcp_auto_enabled = defined($target_rel) && $target_rel eq '10' ? 1 : 0;
my $dhcp_enabled = (!$skip_dhcp && $dhcp_auto_enabled) ? 1 : 0;
my $dhcp_effective_source = '';
my $dhcp_commit = '';
my @dhcp_srpm_collect_roots;

if (!$dhcp_auto_enabled && !$skip_dhcp) {
    print "INFO: DHCP build step disabled for non-EL10 target '$target'.\n";
}

for my $bin (qw(perl uname createrepo tar find rpm)) {
    require_command($bin);
}
require_command('mock') if $scrub_all_chroots;
if ($dhcp_enabled && !$skip_build) {
    require_command('git');
    require_command('mock');
    require_command('rpmdev-spectool');
}

my $run_root     = "$output_root/$run_id";
my $build_root   = "$run_root/build-results";
my $log_root     = "$run_root/build-logs";
my $repo_dir     = "$run_root/repo/$arch";
my $summary_file = "$run_root/summary.txt";
my $tarball      = "$output_root/mockbuild-all-$target-$run_id.tar.gz";
my $srpm_repo_dir = "$run_root/repo-src";
my $srpm_tarball  = "$output_root/mockbuild-all-$target-$run_id-srpm.tar.gz";

my @dep_builders = (
    { name => 'elilo-xcat',  script => "$repo_root/elilo/mockbuild.pl" },
    { name => 'grub2-xcat',  script => "$repo_root/grub2-xcat/mockbuild.pl" },
    { name => 'ipmitool-xcat', script => "$repo_root/ipmitool/mockbuild.pl" },
    { name => 'syslinux-xcat', script => "$repo_root/syslinux/mockbuild.pl" },
);

if ($arch eq 'x86_64') {
    push @dep_builders, { name => 'xnba-undi', script => "$repo_root/xnba/mockbuild.pl" };
}

my $perl_builder = "$repo_root/mockbuild-perl-packages.pl";

die "Missing xCAT build script: $xcat_src/buildrpms.pl\n"
    if !$skip_xcat && !-f "$xcat_src/buildrpms.pl";

my @active_dep_builders;
for my $b (@dep_builders) {
    if (-f $b->{script}) {
        push @active_dep_builders, $b;
        next;
    }
    print "WARN: missing dep builder script, skipping: $b->{script}\n";
}
die "Missing perl builder script: $perl_builder\n"
    if !$skip_perl && !$perl_builder;

if (!$dry_run) {
    make_path($build_root, $log_root, $repo_dir, $srpm_repo_dir);
}

print_step("Configuration");
print "repo_root:        $repo_root\n";
print "xcat_source:      $xcat_src\n";
print "output_root:      $output_root\n";
print "run_root:         $run_root\n";
print "arch:             $arch\n";
print "os_id:            $os_id\n";
print "version_id:       $version_id\n";
print "rel:              $rel\n";
print "target:           $target\n";
print "target_rel:       " . (defined($target_rel) ? $target_rel : 'unknown') . "\n";
print "nproc:            $nproc\n";
print "parallel_builds:  " . (defined($parallel_builds) ? $parallel_builds : 'auto') . "\n";
print "skip_build:       $skip_build\n";
print "skip_xcat_dep:    $skip_xcat_dep\n";
print "skip_perl:        $skip_perl\n";
print "skip_xcat:        $skip_xcat\n";
print "skip_dhcp:        $skip_dhcp\n";
print "dhcp_enabled:     $dhcp_enabled\n";
print "dhcp_repo_url:    $dhcp_repo_url\n";
print "dhcp_repo_ref:    $dhcp_repo_ref\n";
print "dhcp_source_dir:  " . ($dhcp_source_dir ne '' ? $dhcp_source_dir : '(auto)') . "\n";
print "skip_install:     $skip_install\n";
print "skip_createrepo:  $skip_createrepo\n";
print "skip_tarball:     $skip_tarball\n";
print "scrub_all_chroots:$scrub_all_chroots\n";
print "dry_run:          $dry_run\n";
print "perl_builder:     $perl_builder\n";
print "tarball:          $tarball\n";
print "srpm_repo_dir:    $srpm_repo_dir\n";
print "srpm_tarball:     $srpm_tarball\n";

my @collect_roots;

if ($dhcp_enabled && !$skip_build) {
    ($dhcp_effective_source, $dhcp_commit) = prepare_dhcp_source(
        run_root   => $run_root,
        log_root   => "$log_root/dhcpd",
        repo_url   => $dhcp_repo_url,
        repo_ref   => $dhcp_repo_ref,
        source_dir => $dhcp_source_dir,
    );
} elsif ($dhcp_enabled && $skip_build && $dhcp_source_dir ne '') {
    $dhcp_effective_source = eval { abs_path($dhcp_source_dir) } || $dhcp_source_dir;
    $dhcp_commit = '(skip-build)';
}

if ($dhcp_enabled) {
    print "dhcp_source:      " . ($dhcp_effective_source ne '' ? $dhcp_effective_source : '(pending)') . "\n";
    print "dhcp_commit:      " . ($dhcp_commit ne '' ? $dhcp_commit : '(pending)') . "\n";
}

if ($scrub_all_chroots) {
    run_step(
        step => "Scrub all chroots for target $target",
        cmd  => "mock -r " . sh_quote($target) . " --scrub=all",
        log  => "$log_root/scrub-all-chroots.log",
    );
}

if (!$skip_build) {
    my @build_steps;
    my $build_step_seq = 0;

    if (!$skip_xcat_dep) {
        for my $builder (@active_dep_builders) {
            my $name = $builder->{name};
            my $script = $builder->{script};
            my $step_result = "$build_root/$name";
            my $step_log    = "$log_root/$name";
            my $step_uniqueext = build_mock_uniqueext($run_id, ++$build_step_seq, $name);
            my $cmd = join(' ',
                'perl', sh_quote($script),
                '--mock-cfg', sh_quote($target),
                '--mock-uniqueext', sh_quote($step_uniqueext),
                '--result-dir', sh_quote($step_result),
                '--log-dir', sh_quote($step_log),
                ($skip_install ? '--skip-install' : ()),
            );
            push @build_steps, {
                id   => "xcat-dep:$name",
                step => "Build xcat-dep: $name",
                cmd  => $cmd,
                log  => "$log_root/$name/run.log",
            };
            push @collect_roots, $step_result;
        }
    }

    if ($dhcp_enabled) {
        my $dhcp_uniqueext = build_mock_uniqueext($run_id, ++$build_step_seq, 'dhcpd');
        my $dhcp_build_cmd = join(' && ',
            'mkdir -p build/SRPMS build/RPMS',
            'rpmdev-spectool --get-files --sources ./dhcp.spec',
            'mock -r ' . sh_quote($target) .
                ' --uniqueext ' . sh_quote($dhcp_uniqueext) .
                ' --buildsrpm --spec ./dhcp.spec --sources . --resultdir ./build/SRPMS',
            'mock -r ' . sh_quote($target) .
                ' --uniqueext ' . sh_quote($dhcp_uniqueext) .
                ' --rebuild ./build/SRPMS/*.src.rpm --resultdir ./build/RPMS',
        );
        push @build_steps, {
            id   => 'xcat-dep:dhcpd',
            step => 'Build xcat-dep: dhcpd',
            cmd  => $dhcp_build_cmd,
            cwd  => $dhcp_effective_source,
            log  => "$log_root/dhcpd/build.log",
        };
        push @collect_roots, "$dhcp_effective_source/build/RPMS";
        push @dhcp_srpm_collect_roots, "$dhcp_effective_source/build/SRPMS";
    }

    if (!$skip_perl) {
        my $perl_result = "$build_root/perl/$arch";
        my $perl_log    = "$log_root/perl/$arch";
        my $perl_uniqueext = build_mock_uniqueext($run_id, ++$build_step_seq, 'perl-list6');
        my $cmd = join(' ',
            'perl', sh_quote($perl_builder),
            '--mock-cfg', sh_quote($target),
            '--mock-uniqueext', sh_quote($perl_uniqueext),
            '--result-dir', sh_quote($perl_result),
            '--log-dir', sh_quote($perl_log),
            ($skip_install ? '--skip-install' : ()),
        );
        push @build_steps, {
            id   => 'perl',
            step => 'Build perl xcat-dep packages',
            cmd  => $cmd,
            log  => "$log_root/perl-build.log",
        };
        push @collect_roots, $perl_result;
    }

    if (!$skip_xcat) {
        my $cmd = join(' ',
            'perl', sh_quote("$xcat_src/buildrpms.pl"),
            '--target', sh_quote($target),
            '--nproc', int($nproc),
            '--force',
            '--verbose',
            '--xcat_dep_path', sh_quote($repo_root),
        );
        push @build_steps, {
            id   => 'xcat',
            step => 'Build xCAT packages',
            cmd  => $cmd,
            cwd  => $xcat_src,
            log  => "$log_root/xcat-build.log",
        };
    }

    if (@build_steps) {
        my $effective_parallel_builds = defined($parallel_builds)
            ? $parallel_builds
            : scalar(@build_steps);
        run_build_steps_parallel(
            steps         => \@build_steps,
            max_processes => $effective_parallel_builds,
        );
    }
}

my $xcat_rpms_dir = "$xcat_src/dist/$target/rpms";
my $xcat_srpms_dir = "$xcat_src/dist/$target/srpms";
push @collect_roots, $xcat_rpms_dir;

if ($skip_build) {
    push @collect_roots,
        "$repo_root/build-output/list3/elilo-xcat",
        "$repo_root/build-output/list3/grub2-xcat",
        "$repo_root/build-output/list3/ipmitool-xcat",
        "$repo_root/build-output/list3/syslinux-xcat",
        "$repo_root/build-output/list3/xnba-undi",
        "$repo_root/build-output/list5/goconserver/$arch",
        "$repo_root/goconserver-build-$arch/results/rpm",
        "$repo_root/build-output/list6/perl/$arch",
        "$repo_root/perl-list6/$arch";
}

if ($dhcp_effective_source ne '') {
    push @collect_roots, "$dhcp_effective_source/build/RPMS";
    push @dhcp_srpm_collect_roots, "$dhcp_effective_source/build/SRPMS";
}

push @collect_roots, @extra_collect_dirs;
@collect_roots = uniq(@collect_roots);
my @srpm_collect_roots = uniq(@collect_roots, $xcat_srpms_dir, @dhcp_srpm_collect_roots);

print_step('Collect RPM artifacts');
print "collection roots:\n";
print "  $_\n" for @collect_roots;

my ($copied, $skipped_src, $missing_roots) = collect_rpms(
    roots    => \@collect_roots,
    dest_dir => $repo_dir,
    dry_run  => $dry_run,
);

if (!$dry_run && $copied == 0) {
    die "No binary RPMs were collected. Check build logs and collection roots.\n";
}

print_step('Collect source RPM artifacts');
print "source collection roots:\n";
print "  $_\n" for @srpm_collect_roots;

my ($copied_srpms, $skipped_non_src, $missing_srpm_roots) = collect_srpms(
    roots    => \@srpm_collect_roots,
    dest_dir => $srpm_repo_dir,
    dry_run  => $dry_run,
);

if (!$dry_run && $copied_srpms == 0) {
    print "WARN: No source RPMs were collected. SRPM repo and tarball may be empty.\n";
}

if (!$skip_createrepo) {
    run_step(
        step => 'Run createrepo',
        cmd  => 'createrepo --update ' . sh_quote($repo_dir),
        log  => "$log_root/createrepo.log",
    );
    run_step(
        step => 'Run createrepo for SRPM repo',
        cmd  => 'createrepo --update ' . sh_quote($srpm_repo_dir),
        log  => "$log_root/createrepo-srpm.log",
    );
}

if (!$skip_tarball) {
    my $cmd = join(' ',
        'tar', '-C', sh_quote($run_root),
        '-czf', sh_quote($tarball),
        'repo'
    );
    run_step(
        step => 'Create tarball',
        cmd  => $cmd,
        log  => "$log_root/tarball.log",
    );
    my $srpm_cmd = join(' ',
        'tar', '-C', sh_quote($run_root),
        '-czf', sh_quote($srpm_tarball),
        'repo-src'
    );
    run_step(
        step => 'Create SRPM tarball',
        cmd  => $srpm_cmd,
        log  => "$log_root/tarball-srpm.log",
    );
}

if (!$dry_run) {
    open my $sfh, '>', $summary_file or die "Cannot write $summary_file: $!\n";
    print {$sfh} "run_root=$run_root\n";
    print {$sfh} "repo_dir=$repo_dir\n";
    print {$sfh} "target=$target\n";
    print {$sfh} "target_rel=" . (defined($target_rel) ? $target_rel : '') . "\n";
    print {$sfh} "arch=$arch\n";
    print {$sfh} "os_id=$os_id\n";
    print {$sfh} "version_id=$version_id\n";
    print {$sfh} "rel=$rel\n";
    print {$sfh} "dhcp_enabled=$dhcp_enabled\n";
    print {$sfh} "dhcp_repo_url=$dhcp_repo_url\n";
    print {$sfh} "dhcp_repo_ref=$dhcp_repo_ref\n";
    print {$sfh} "dhcp_source=" . ($dhcp_effective_source ne '' ? $dhcp_effective_source : '') . "\n";
    print {$sfh} "dhcp_commit=" . ($dhcp_commit ne '' ? $dhcp_commit : '') . "\n";
    print {$sfh} "copied_rpms=$copied\n";
    print {$sfh} "skipped_src_rpms=$skipped_src\n";
    print {$sfh} "missing_collection_roots=$missing_roots\n";
    print {$sfh} "srpm_repo_dir=$srpm_repo_dir\n";
    print {$sfh} "copied_srpms=$copied_srpms\n";
    print {$sfh} "skipped_non_src_rpms=$skipped_non_src\n";
    print {$sfh} "missing_srpm_collection_roots=$missing_srpm_roots\n";
    print {$sfh} "tarball=$tarball\n" if !$skip_tarball;
    print {$sfh} "srpm_tarball=$srpm_tarball\n" if !$skip_tarball;
    close $sfh;
}

print_step('Completed');
print "Collected binary RPMs: $copied\n";
print "Skipped source RPMs:   $skipped_src\n";
print "Missing roots:         $missing_roots\n";
print "Repo dir:              $repo_dir\n";
print "Collected source RPMs: $copied_srpms\n";
print "Skipped non-src RPMs:  $skipped_non_src\n";
print "Missing source roots:  $missing_srpm_roots\n";
print "SRPM repo dir:         $srpm_repo_dir\n";
print "DHCP source:           $dhcp_effective_source\n" if $dhcp_effective_source ne '';
print "DHCP ref:              $dhcp_repo_ref\n" if $dhcp_enabled;
print "DHCP commit:           $dhcp_commit\n" if $dhcp_commit ne '';
print "Summary:               $summary_file\n" if !$dry_run;
print "Tarball:               $tarball\n" if !$skip_tarball;
print "SRPM Tarball:          $srpm_tarball\n" if !$skip_tarball;
exit 0;

sub usage {
    return <<"USAGE";
Usage: $0 [options]

Build xcat-dep and xCAT RPMs, consolidate binary/source artifacts, run createrepo, and create tarballs.

Options:
  --repo-root PATH        xcat-dep repository root (default: script directory)
  --xcat-source PATH      xCAT source root with buildrpms.pl (default: <repo-root>/xcat-source-code)
  --output-root PATH      Root output directory (default: <repo-root>/build-output/mockbuild-all)
  --target NAME           Optional unified target in <ID>+epel-<REL>-<ARCH> format
  --nproc N               Parallel jobs for buildrpms.pl (default: 1)
  --parallel-builds N     Max concurrent top-level build steps (default: auto=queued steps)
  --run-id ID             Run identifier suffix (default: timestamp)
  --skip-install          Skip install/smoke tests in child builder scripts
  --skip-build            Skip all build steps and only collect/create repo/tarballs
  --skip-xcat-dep         Skip xcat-dep mockbuild.pl package steps
  --skip-perl             Skip perl package build step
  --skip-xcat             Skip xCAT buildrpms.pl step
  --skip-dhcp             Skip rpms-dhcp build step
  --skip-createrepo       Skip createrepo
  --skip-tarball          Skip binary/SRPM tarball creation
  --scrub-all-chroots     Run mock -r <target> --scrub=all before build/collect
  --dhcp-repo-url URL     rpms-dhcp git URL (default: https://github.com/VersatusHPC/rpms-dhcp.git)
  --dhcp-repo-ref REF     rpms-dhcp git ref/tag/branch to checkout (default: master)
  --dhcp-source-dir PATH  Local rpms-dhcp source directory override (skip clone/fetch)
  --collect-dir PATH      Additional directory to scan recursively for RPMs (repeatable)
  --dry-run               Print planned commands without executing

Notes:
  - Run this script as root on the build host.
  - ARCH is derived from: uname -m
  - Top-level parallel queue includes xcat-dep mockbuild.pl steps, perl builder,
    and xcat-source-code/buildrpms.pl.
  - Child mockbuild scripts are invoked with per-step mock --uniqueext values
    to avoid lock collisions on the same mock config.
  - If --target is omitted, it is deduced from /etc/os-release:
      ID + epel + int(VERSION_ID) + ARCH
  - DHCP step auto-enables only for EL10 targets, unless explicitly skipped.
USAGE
}

sub parse_target_rel {
    my ($target_name) = @_;
    return undef if !defined($target_name) || $target_name eq '';
    return $1 if $target_name =~ /\+epel-(\d+)-/;
    return undef;
}

sub prepare_dhcp_source {
    my (%args) = @_;
    my $run_root   = $args{run_root}   // die "prepare_dhcp_source missing run_root\n";
    my $log_root   = $args{log_root}   // die "prepare_dhcp_source missing log_root\n";
    my $repo_url   = $args{repo_url}   // die "prepare_dhcp_source missing repo_url\n";
    my $repo_ref   = $args{repo_ref} // 'master';
    my $source_dir = $args{source_dir} // '';

    my $clone_log = "$log_root/clone.log";
    my $source_path;

    if ($source_dir ne '') {
        $source_path = eval { abs_path($source_dir) } || $source_dir;
        die "DHCP source directory does not exist: $source_path\n"
            if !$dry_run && !-d $source_path;
        run_step(
            step => 'Prepare DHCP source',
            cmd  => 'echo Using local DHCP source directory: ' . sh_quote($source_path),
            log  => $clone_log,
        );
    } else {
        $source_path = "$run_root/sources/rpms-dhcp";
        my $prepare_cmd = join(' && ',
            'mkdir -p ' . sh_quote("$run_root/sources"),
            'if [ -d ' . sh_quote("$source_path/.git") . ' ]; then ' .
                'cd ' . sh_quote($source_path) . ' && ' .
                'git remote set-url origin ' . sh_quote($repo_url) . ' && ' .
                'git fetch --tags origin' .
            '; else ' .
                'git clone ' . sh_quote($repo_url) . ' ' . sh_quote($source_path) .
            '; fi',
            'cd ' . sh_quote($source_path),
            'git fetch --tags origin',
            'git checkout --force ' . sh_quote($repo_ref),
        );
        run_step(
            step => 'Prepare DHCP source',
            cmd  => $prepare_cmd,
            log  => $clone_log,
        );
    }

    if (!$dry_run && !-f "$source_path/dhcp.spec") {
        die "Missing dhcp.spec in DHCP source: $source_path/dhcp.spec\n";
    }

    my $commit = '';
    if ($dry_run) {
        $commit = '(dry-run)';
    } elsif (-d "$source_path/.git") {
        $commit = capture("cd " . sh_quote($source_path) . " && git rev-parse HEAD");
    } else {
        $commit = '(local-source-no-git)';
    }

    return ($source_path, $commit);
}

sub print_step {
    my ($msg) = @_;
    print "\n== $msg ==\n";
}

sub require_command {
    my ($cmd) = @_;
    run_simple("command -v " . sh_quote($cmd) . " >/dev/null 2>&1");
}

sub run_simple {
    my ($cmd) = @_;
    my $rc = system($cmd);
    if ($rc != 0) {
        my $exit = $rc == -1 ? 255 : ($rc >> 8);
        die "Command failed (rc=$exit): $cmd\n";
    }
}

sub capture {
    my ($cmd) = @_;
    my $out = `$cmd`;
    my $rc = $?;
    if ($rc != 0) {
        my $exit = $rc == -1 ? 255 : ($rc >> 8);
        die "Command failed (rc=$exit): $cmd\n$out\n";
    }
    chomp $out;
    return $out;
}

sub run_step {
    my (%args) = @_;
    my $step = $args{step} // 'Run command';
    my $cmd  = $args{cmd}  // die "run_step missing cmd\n";
    my $cwd  = $args{cwd};
    my $log  = $args{log};

    print_step($step);
    print "+ $cmd\n";
    if ($cwd) {
        print "  (cwd: $cwd)\n";
    }
    if ($log) {
        print "  (log: $log)\n";
    }

    return if $dry_run;

    my $full_cmd = $cmd;
    if ($cwd) {
        $full_cmd = "cd " . sh_quote($cwd) . " && $cmd";
    }
    if ($log) {
        my $log_dir = dirname($log);
        make_path($log_dir) if !-d $log_dir;
        $full_cmd .= " > " . sh_quote($log) . " 2>&1";
    }

    my $rc = system($full_cmd);
    if ($rc != 0) {
        my $exit = $rc == -1 ? 255 : ($rc >> 8);
        die "Step failed (rc=$exit): $step\nCommand: $cmd\n";
    }
}

sub run_build_steps_parallel {
    my (%args) = @_;
    my $steps = $args{steps} // [];
    my $max_processes = $args{max_processes} // 1;
    return if !@{$steps};

    if ($dry_run || $max_processes <= 1 || @{$steps} == 1) {
        for my $step (@{$steps}) {
            run_step(%{$step});
        }
        return;
    }

    my $workers = $max_processes;
    $workers = scalar(@{$steps}) if $workers > scalar(@{$steps});

    print_step('Run build steps in parallel');
    print "max_processes: $workers\n";
    print "queued steps:\n";
    print "  - $_->{step}\n" for @{$steps};

    my %failed;
    my $pm = Parallel::ForkManager->new($workers);
    $pm->run_on_finish(
        sub {
            my ($pid, $exit_code, $ident, $signal, $core_dump) = @_;
            return if $exit_code == 0 && $signal == 0 && !$core_dump;
            my $key = defined($ident) ? $ident : "pid:$pid";
            $failed{$key} = {
                exit      => $exit_code,
                signal    => $signal,
                core_dump => $core_dump ? 1 : 0,
            };
        }
    );

    for my $step (@{$steps}) {
        my %step_copy = %{$step};
        my $ident = delete $step_copy{id};
        $ident = $step_copy{step} if !defined($ident) || $ident eq '';

        my $pid = $pm->start($ident);
        next if $pid;

        my $ok = eval {
            run_step(%step_copy);
            1;
        };
        if (!$ok) {
            my $err = $@;
            $err = "unknown error\n" if !defined($err) || $err eq '';
            print STDERR "ERROR [$ident] $err";
            $pm->finish(1);
        }
        $pm->finish(0);
    }
    $pm->wait_all_children;

    if (%failed) {
        my @lines;
        for my $id (sort keys %failed) {
            my $f = $failed{$id};
            push @lines,
                "$id (exit=$f->{exit}, signal=$f->{signal}, core_dump=$f->{core_dump})";
        }
        die "Parallel build steps failed:\n  " . join("\n  ", @lines) . "\n";
    }
}

sub collect_rpms {
    my (%args) = @_;
    my $roots = $args{roots} // [];
    my $dest  = $args{dest_dir} // die "collect_rpms missing dest_dir\n";
    my $is_dry = $args{dry_run} ? 1 : 0;

    my %seen;
    my $copied = 0;
    my $skipped_src = 0;
    my $missing_roots = 0;

    for my $root (@{$roots}) {
        if (!$root || !-d $root) {
            $missing_roots++;
            print "WARN: missing collection root: $root\n";
            next;
        }
        my @rpms;
        find(
            sub {
                return if !-f $_;
                return if $_ !~ /\.rpm$/;
                push @rpms, $File::Find::name;
            },
            $root,
        );
        @rpms = sort uniq(@rpms);
        for my $rpm (@rpms) {
            next if !-f $rpm;
            if ($rpm =~ /\.src\.rpm$/) {
                $skipped_src++;
                next;
            }
            my $base = basename($rpm);
            next if $seen{$base}++;
            if ($is_dry) {
                print "DRY-RUN copy: $rpm -> $dest/$base\n";
                $copied++;
                next;
            }
            copy($rpm, "$dest/$base")
                or die "Failed to copy $rpm to $dest/$base: $!\n";
            $copied++;
        }
    }

    return ($copied, $skipped_src, $missing_roots);
}

sub collect_srpms {
    my (%args) = @_;
    my $roots = $args{roots} // [];
    my $dest  = $args{dest_dir} // die "collect_srpms missing dest_dir\n";
    my $is_dry = $args{dry_run} ? 1 : 0;

    my %seen;
    my $copied = 0;
    my $skipped_non_src = 0;
    my $missing_roots = 0;

    for my $root (@{$roots}) {
        if (!$root || !-d $root) {
            $missing_roots++;
            print "WARN: missing source collection root: $root\n";
            next;
        }
        my @rpms;
        find(
            sub {
                return if !-f $_;
                return if $_ !~ /\.rpm$/;
                push @rpms, $File::Find::name;
            },
            $root,
        );
        @rpms = sort uniq(@rpms);
        for my $rpm (@rpms) {
            next if !-f $rpm;
            if ($rpm !~ /\.src\.rpm$/) {
                $skipped_non_src++;
                next;
            }
            my $base = basename($rpm);
            next if $seen{$base}++;
            if ($is_dry) {
                print "DRY-RUN copy source: $rpm -> $dest/$base\n";
                $copied++;
                next;
            }
            copy($rpm, "$dest/$base")
                or die "Failed to copy $rpm to $dest/$base: $!\n";
            $copied++;
        }
    }

    return ($copied, $skipped_non_src, $missing_roots);
}

sub build_mock_uniqueext {
    my ($run, $seq, $label) = @_;

    my $run_part = defined($run) ? $run : 'run';
    $run_part =~ s/[^A-Za-z0-9_.-]+/-/g;
    $run_part =~ s/^-+|-+$//g;
    $run_part = 'run' if $run_part eq '';
    $run_part = substr($run_part, -24) if length($run_part) > 24;

    my $label_part = defined($label) ? $label : 'step';
    $label_part =~ s/[^A-Za-z0-9_.-]+/-/g;
    $label_part =~ s/^-+|-+$//g;
    $label_part = 'step' if $label_part eq '';
    $label_part = substr($label_part, 0, 20) if length($label_part) > 20;

    my $idx = defined($seq) ? int($seq) : 0;
    $idx = 0 if $idx < 0;

    return sprintf("mba-%02d-%s-%s", $idx, $run_part, $label_part);
}

sub resolve_xcat_source {
    my ($requested, $root) = @_;
    my @candidates = (
        $requested,
        "$root/xcat-source-code",
        "$root/../xCAT3",
        '/home/build/xCAT3',
    );
    for my $c (@candidates) {
        next if !defined($c) || $c eq '';
        my $abs = eval { abs_path($c) };
        next if !$abs;
        return $abs if -f "$abs/buildrpms.pl";
    }
    return eval { abs_path($requested) } || $requested;
}

sub read_os_release {
    my ($path) = @_;
    my %vals;
    open my $fh, '<', $path or die "Cannot open $path: $!\n";
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /^\s*#/;
        next if $line !~ /=/;
        my ($k, $v) = split /=/, $line, 2;
        $v =~ s/^"(.*)"$/$1/;
        $v =~ s/^'(.*)'$/$1/;
        $vals{$k} = $v;
    }
    close $fh;
    return %vals;
}

sub uniq {
    my %seen;
    return grep { defined($_) && !$seen{$_}++ } @_;
}

sub sh_quote {
    my ($s) = @_;
    $s = '' if !defined $s;
    $s =~ s/'/'"'"'/g;
    return "'$s'";
}
