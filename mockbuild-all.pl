#!/usr/bin/perl

use strict;
use warnings;

use Cwd qw(abs_path cwd);
use File::Basename qw(dirname basename);
use File::Copy qw(copy);
use File::Find qw(find);
use File::Glob qw(bsd_glob);
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir tempfile);
use FindBin;
use Getopt::Long qw(GetOptions);
use Parallel::ForkManager;
use POSIX qw(strftime);
use lib "$FindBin::Bin/lib";
use XCAT::BuildUtils qw(
  capture_command
  every_step_failed
  hashes_equal
  print_step
  read_lines
  require_command
  run_command
  shell_quote
);
use XCAT::GenesisRelease qw(
  validated_release_checksums
  verify_release_file
);

my $script_dir = abs_path(dirname(__FILE__));
my $repo_root  = abs_path($script_dir);
my $xcat_src   = "$repo_root/../xcat-core";
# Single knob for all NFS-shared output; --output-root/--repo-dep derive from it below
# unless explicitly overridden. Empty means "not set on the command line".
my $output     = '';
my $output_root = '';
my $target     = '';
my $nproc      = 1;
my $parallel_builds;
my $parallel_targets = 1;   # 1 = serial (default; safe). 0/auto = all EL targets at once; N = cap.
                            # NOTE: parallel targets need every per-package mockbuild.pl to avoid
                            # shared-path writes (repo tarballs, $HOME/rpmbuild); serial is safe today.
my $max_parallel = 0;       # 0/auto = host nproc: global cap on concurrent mock builds (all targets)
my $run_id     = '';
my $build_timestamp;
my $skip_install = 0;
my $skip_build = 0;
my $skip_xcat_dep = 0;
my $skip_perl = 0;
my $skip_xcat = 0;
my $skip_genesis = 0;
my $skip_createrepo = 0;
my $skip_tarball = 0;
my $genesis_release = '';
my $genesis_release_checksums;
my $scrub_all_chroots = 0;
my $dry_run = 0;
my @extra_collect_dirs;
my $repo_dep = '';
my $gpg_sign = 0;
my $gpg_key_name = 'xCAT Signing Key';
my $gpg_home = '';
my $gpg_program = '';
my $force_unlock = 0;
my @HELD_LOCKS;
my $LOCK_OWNER_PID;
my ($COMMON_STAGE, $COMMON_DESTINATION, $COMMON_BACKUP);
for my $sig (qw(INT TERM HUP)) {
    $SIG{$sig} = sub { exit 1; };
}

GetOptions(
    'repo-root=s'       => \$repo_root,
    'xcat-source=s'     => \$xcat_src,
    'output=s'          => \$output,
    'output-root=s'     => \$output_root,
    'repo-dep=s'        => \$repo_dep,
    'gpg-sign!'         => \$gpg_sign,
    'gpg-key-name=s'    => \$gpg_key_name,
    'gpg-home=s'        => \$gpg_home,
    'force-unlock!'     => \$force_unlock,
    'target=s'          => \$target,
    'nproc=i'           => \$nproc,
    'parallel-builds=i' => \$parallel_builds,
    'parallel-targets=i' => \$parallel_targets,
    'max-parallel=i'    => \$max_parallel,
    'run-id=s'          => \$run_id,
    'build-timestamp=i' => \$build_timestamp,
    'skip-install!'     => \$skip_install,
    'skip-build!'       => \$skip_build,
    'skip-xcat-dep!'    => \$skip_xcat_dep,
    'skip-perl!'        => \$skip_perl,
    'skip-xcat!'        => \$skip_xcat,
    'skip-genesis!'     => \$skip_genesis,
    'skip-createrepo!'  => \$skip_createrepo,
    'skip-tarball!'     => \$skip_tarball,
    'genesis-release=s' => \$genesis_release,
    'scrub-all-chroots!' => \$scrub_all_chroots,
    'collect-dir=s@'    => \@extra_collect_dirs,
    'dry-run!'          => \$dry_run,
) or die usage();

die "Run as root (uid=$>)\n" if $> != 0;
die "--parallel-builds must be >= 1\n"
    if defined($parallel_builds) && $parallel_builds < 1;

$repo_root = abs_path($repo_root);

my $SOURCE_DATE_EPOCH;
$SOURCE_DATE_EPOCH = $build_timestamp if defined $build_timestamp;
if (!$SOURCE_DATE_EPOCH && -f "$repo_root/Gitepoch") {
    my @gitepoch = read_lines("$repo_root/Gitepoch");
    $SOURCE_DATE_EPOCH = $gitepoch[0] // '';
}
unless ($SOURCE_DATE_EPOCH && $SOURCE_DATE_EPOCH =~ /^\d+$/) {
    $SOURCE_DATE_EPOCH = `git -C \Q$repo_root\E log -1 --format=%ct HEAD 2>/dev/null`;
    chomp $SOURCE_DATE_EPOCH;
}
$SOURCE_DATE_EPOCH = time() unless $SOURCE_DATE_EPOCH =~ /^\d+$/;
$ENV{SOURCE_DATE_EPOCH} = $SOURCE_DATE_EPOCH;

if ($run_id eq '') {
    $run_id = strftime('%Y%m%d-%H%M%S', gmtime($SOURCE_DATE_EPOCH));
}

# Single output base for every NFS-shared write. Two hosts build in parallel on one NFS by
# passing distinct --output paths. --output-root/--repo-dep, if given, override the derived
# values. Default keeps the historical layout so existing callers are unaffected.
# Create the dir first, THEN abs_path -- abs_path() on a not-yet-existing path returns undef,
# and abs_path(undef) silently resolves to cwd, which would misdirect all output.
my $output_base = $output ne '' ? $output : "$repo_root/build-output";
make_path($output_base) if !-d $output_base;
$output_base = abs_path($output_base)
    or die "Cannot resolve --output base directory\n";
$output_root = "$output_base/mockbuild-all" if $output_root eq '';
# Deployable per-EL xcat-dep repo root (rh8/rh9/rh10/<arch> assembled here).
$repo_dep = "$output_base/xcat-dep" if $repo_dep eq '';
make_path($repo_dep) if !-d $repo_dep;
$repo_dep = abs_path($repo_dep)
    or die "Cannot resolve --repo-dep directory\n";

# Fail-fast lock on the output base so a second run against the same --output aborts instead of
# racing on the shared NFS tree. Held for the whole invocation; released by the exit handlers.
acquire_output_lock($output_base, $force_unlock);
acquire_repository_lock($repo_dep, $force_unlock)
    if $repo_dep ne $output_base;

$xcat_src  = resolve_xcat_source($xcat_src, $repo_root);

my $host_arch = capture_command('uname', '-m');
# Arch of the target being built: the host arch, except for the forcearch targets below, which
# cross-build another arch on this host. Set per target in build_one_target; the deploy and
# the repo metadata take the arch from the target profile instead of this variable.
my $arch = $host_arch;
my %os = read_os_release('/etc/os-release');
my $os_id = $os{ID} // '';
my $version_id = $os{VERSION_ID} // '';
my ($rel) = $version_id =~ /^(\d+)/;

die "Could not resolve ID from /etc/os-release\n" if $os_id eq '';
die "Could not resolve major release from VERSION_ID='$version_id' in /etc/os-release\n"
    if !defined($rel) || $rel eq '';

for my $bin (qw(perl uname createrepo_c tar find rpm)) {
    require_command($bin);
}
require_command('mock') if $scrub_all_chroots;
require_command('rpmsign') if $gpg_sign;
$gpg_program = require_command('gpg') if $gpg_sign;

if ($genesis_release ne '') {
    $genesis_release = abs_path($genesis_release)
        or die "Cannot resolve --genesis-release directory\n";
    die "Genesis release directory not found: $genesis_release\n"
        unless -d $genesis_release;
    my $verifier = "$script_dir/genesis-openembedded/verify-release";
    die "Genesis release verifier not found: $verifier\n" unless -x $verifier;
    # Checksum, verify, checksum again. The verifier reads the tree it validates, so a
    # release rewritten together with its SHA256SUMS while the verifier runs would satisfy
    # both the verifier and any single pass taken afterwards; comparing the pass taken
    # before with the one taken after is what closes that window.
    my $checksums_before = validated_release_checksums($genesis_release);
    run_command($^X, $verifier, '--complete', '--format', 'rpm', $genesis_release);
    my $checksums_after = validated_release_checksums($genesis_release);
    die "Genesis release changed during verification\n"
      unless hashes_equal($checksums_before, $checksums_after);
    $genesis_release_checksums = $checksums_before;
}

# An explicit --target builds just that target; otherwise build the current host
# arch across rh8/rh9/rh10 into a deployable per-EL xcat-dep repo. This script builds
# ONLY the host arch (uname -m) -- the other arch is produced on its own build host --
# except for the forcearch targets (%forcearch_targets, --target only), which are
# cross-built here through qemu-user-static.
my @build_targets = $target
    ? ($target)
    : map { resolve_mock_cfg($os_id, $_, $host_arch) } (8, 9, 10);

# What a target builds. The mock-core-configs targets (<os>+epel-<rel>-<arch>) build every
# dep natively on the host arch. The forcearch targets shipped in mock-configs/ cross-build
# another arch that has no EPEL: the x86-only bootloaders are not built for it, the EPEL-only
# perl deps of xCAT are (mockbuild-perl-packages.pl --epel-gap), and the noarch deps are built
# in the native, EPEL-free chroot of the same release (the rpms are identical for every arch
# and an emulated build is an order of magnitude slower). See BUILD.md ("riscv64").
my %forcearch_targets = (
    'rocky-10-riscv64-xcat' => {
        rel          => 10,
        arch         => 'riscv64',
        noarch_cfg   => "rocky-10-$host_arch",
        dep_builders => [qw(grub2-xcat ipmitool-xcat goconserver conserver-xcat)],
        required     => [qw(ipmitool-xcat grub2-xcat perl-IO-Stty perl-HTTP-Async perl-Net-HTTPS-NB)],
    },
);

# NOTE: no dhcp- packages are built here. DHCP backend selection is an install-time
# rich dep in xCAT.spec (kea if system-release>=10 else /usr/sbin/dhcpd), so there is
# nothing arch/EL-specific to build or to exclude for el10.

print_step('Targets to build');
print "  $_\n" for @build_targets;
print "output_base:      $output_base\n";
print "deploy repo-dep:  $repo_dep\n";
print "output lock:      $output_base/.lock (held)\n";
print "repository lock:  $repo_dep/.lock (held)\n";
print "gpg_sign:         $gpg_sign\n";
print "gpg_key_name:     $gpg_key_name\n" if $gpg_sign;
print "gpg_home:         " . ($gpg_home ne '' ? $gpg_home : '(default keyring)') . "\n" if $gpg_sign;
print "genesis_release:  " . ($genesis_release || '(legacy builder)') . "\n";

# Build (and deploy) EL targets concurrently. Each target is fully isolated -- distinct run_id
# (target-folded), mock --uniqueext, /tmp work dir, xcat_src/dist/<target>, and deploy dir
# rh<rel>/<arch> -- so there is no cross-target contention. 0/auto = all at once; 1 = serial.
my $tgt_workers = $parallel_targets > 0 ? $parallel_targets : scalar(@build_targets);
$tgt_workers = scalar(@build_targets) if $tgt_workers > scalar(@build_targets);
# Global cap on concurrent mock builds so parallel targets don't oversubscribe the host. Each
# mock build already gets a unique --uniqueext (separate chroot), so the only limit needed is
# hardware: total concurrent builds across all targets stays <= $cap (default host nproc). The
# per-target build-step concurrency is therefore the cap divided across the active targets.
my $cap = $max_parallel > 0 ? $max_parallel : (capture_command('nproc') || 4);
my $per_target_builds = defined($parallel_builds) ? $parallel_builds : int($cap / $tgt_workers);
$per_target_builds = 1 if $per_target_builds < 1;
print "parallel_targets: " . ($parallel_targets > 0 ? $parallel_targets : "auto($tgt_workers)") . "\n";
print "max_parallel:     $cap (per-target build workers: $per_target_builds)\n";
my $tgt_pm = Parallel::ForkManager->new($tgt_workers <= 1 ? 0 : $tgt_workers);
my $tgt_fail = 0;
$tgt_pm->run_on_finish(sub {
    my ($pid, $exit) = @_;
    $tgt_fail++ if $exit;
});
for my $tgt (@build_targets) {
    $tgt_pm->start and next;
    my $rc = 0;
    eval {
        my $info = build_one_target($tgt, $run_id, $per_target_builds);
        deploy_target($tgt, $info);
        1;
    } or do { warn "ERROR: target $tgt failed: $@"; $rc = 1; };
    $tgt_pm->finish($rc);
}
$tgt_pm->wait_all_children;
die "FATAL: $tgt_fail target(s) failed\n" if $tgt_fail;

publish_genesis_common_repo() if $genesis_release;

print_step('All targets completed');
exit 0;

# Build a single target into its own build-output/<target-runid> tree and return
# { repo_dir, rel }. Everything below through the summary is per-target work.
sub build_one_target {
    my ($target, $run_id, $max_build_workers) = @_;
    # The build output identity must be per-target (os version + arch). SOURCE_DATE_EPOCH
    # is the same across targets for a given commit, so a timestamp-only run_id makes
    # different targets (e.g. alma+epel-8 vs -9) share build-output/<run_id> and
    # cross-contaminate. Fold the target into run_id so each target gets its own tree.
    $run_id = "$target-$run_id" unless index($run_id, $target) >= 0;
    my $profile = target_profile($target);
    my $rel = $profile->{rel};
    $arch = $profile->{arch};

my $run_root     = "$output_root/$run_id";
my $build_root   = "$run_root/build-results";
my $log_root     = "$run_root/build-logs";
my $repo_dir     = "$run_root/repo/$arch";
my $summary_file = "$run_root/summary.txt";
my $tarball      = "$output_root/mockbuild-all-$target-$run_id.tar.gz";
my $srpm_repo_dir = "$run_root/repo-src";
my $srpm_tarball  = "$output_root/mockbuild-all-$target-$run_id-srpm.tar.gz";

# All dep builders run natively on every arch. xnba-undi and grub2-xcat are noarch packagings of
# committed artifacts (an x86 UNDI ROM / the grub2 resource tarball) with no arch-specific build
# step, so ppc builds them the same as x86 -- no cross-arch import. A forcearch target builds
# only the builders its profile lists; the noarch ones run in the profile's native chroot.
my @dep_builders = (
    { name => 'elilo-xcat',  script => "$repo_root/elilo/mockbuild.pl", noarch => 1 },
    { name => 'grub2-xcat',  script => "$repo_root/grub2-xcat/mockbuild.pl", noarch => 1 },
    { name => 'ipmitool-xcat', script => "$repo_root/ipmitool/mockbuild.pl" },
    { name => 'syslinux-xcat', script => "$repo_root/syslinux/mockbuild.pl" },
    { name => 'goconserver', script => "$repo_root/goconserver/mockbuild.pl" },
    { name => 'conserver-xcat', script => "$repo_root/conserver/mockbuild.pl" },
    { name => 'xnba-undi',   script => "$repo_root/xnba/mockbuild.pl", noarch => 1 },
);
my %profile_builds = map { $_ => 1 } @{ $profile->{dep_builders} };

my $perl_builder = "$repo_root/mockbuild-perl-packages.pl";

die "Missing xCAT build script: $xcat_src/buildrpms.pl\n"
    if !$skip_xcat && !-f "$xcat_src/buildrpms.pl";

my @active_dep_builders;
for my $b (@dep_builders) {
    next if !$profile_builds{$b->{name}};
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
    # The staging repositories hold what THIS invocation produces. A reused --run-id, or a
    # rerun after a failed invocation, otherwise leaves an earlier run's packages in them,
    # where collection never sees them, createrepo indexes them and deploy_target publishes
    # them as this run's output.
    reset_staging_repo($repo_dir);
    reset_staging_repo($srpm_repo_dir);
    # Same for the builder results when this run is going to build them: a reused --run-id
    # otherwise leaves a previous run's packages there, and a step that fails this time is
    # collected from the last time it succeeded. --skip-build deliberately collects earlier
    # output, from the repository-level build-output tree, and must keep what is there.
    if (!$skip_build) {
        remove_tree($build_root);
        make_path($build_root);
    }
}

print_step("Configuration");
print "repo_root:        $repo_root\n";
print "xcat_source:      $xcat_src\n";
print "output_root:      $output_root\n";
print "run_root:         $run_root\n";
print "arch:             $arch\n";
print "host_arch:        $host_arch\n";
print "forcearch:        $profile->{forcearch}\n";
print "noarch_cfg:       $profile->{noarch_cfg}\n";
print "epel:             $profile->{epel}\n";
print "os_id:            $os_id\n";
print "version_id:       $version_id\n";
print "rel:              $rel\n";
print "target:           $target\n";
print "nproc:            $nproc\n";
print "parallel_builds:  " . (defined($parallel_builds) ? $parallel_builds : 'auto') . "\n";
print "skip_build:       $skip_build\n";
print "skip_xcat_dep:    $skip_xcat_dep\n";
print "skip_perl:        $skip_perl\n";
print "skip_xcat:        $skip_xcat\n";
print "skip_genesis:     $skip_genesis\n";
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

install_mock_cfg($target);

if ($scrub_all_chroots) {
    run_step(
        step => "Scrub all chroots for target $target",
        cmd  => "mock -r " . shell_quote($target) . " --scrub=all",
        log  => "$log_root/scrub-all-chroots.log",
    );
    run_step(
        step => "Scrub all chroots for noarch config $profile->{noarch_cfg}",
        cmd  => "mock -r " . shell_quote($profile->{noarch_cfg}) . " --scrub=all",
        log  => "$log_root/scrub-all-chroots-noarch.log",
    ) if $profile->{noarch_cfg} ne $target;
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
                'perl', shell_quote($script),
                '--mock-cfg', shell_quote($builder->{noarch} ? $profile->{noarch_cfg} : $target),
                ($profile->{forcearch} && !$builder->{noarch} ? ('--target-arch', shell_quote($arch)) : ()),
                '--mock-uniqueext', shell_quote($step_uniqueext),
                '--result-dir', shell_quote($step_result),
                '--log-dir', shell_quote($step_log),
                # host-local, run-scoped work dir so /tmp doesn't collide between runs
                '--work-dir', shell_quote("/tmp/mockbuild-all-$run_id/$name"),
                '--build-timestamp', $SOURCE_DATE_EPOCH,
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

    if (!$skip_perl) {
        my $perl_result = "$build_root/perl/$arch";
        my $perl_log    = "$log_root/perl/$arch";
        my $perl_uniqueext = build_mock_uniqueext($run_id, ++$build_step_seq, 'perl-list6');
        # Bound the perl builder's OWN internal parallelism to this target's budget; otherwise it
        # forks one mock build per perl package (~7), which -- multiplied by parallel EL targets --
        # oversubscribes the host.
        my $cmd = join(' ',
            'perl', shell_quote($perl_builder),
            '--mock-cfg', shell_quote($target),
            ($profile->{forcearch}
                ? ('--target-arch', shell_quote($arch), '--noarch-mock-cfg', shell_quote($profile->{noarch_cfg}))
                : ()),
            ($profile->{epel} ? () : ('--epel-gap')),
            '--mock-uniqueext', shell_quote($perl_uniqueext),
            '--result-dir', shell_quote($perl_result),
            '--log-dir', shell_quote($perl_log),
            '--work-dir', shell_quote("/tmp/mockbuild-all-$run_id/perl-list6"),
            (($max_build_workers && $max_build_workers >= 1) ? ('--jobs', $max_build_workers) : ()),
            '--build-timestamp', $SOURCE_DATE_EPOCH,
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
        # Own HOME per target (buildrpms.pl uses $HOME/rpmbuild) so parallel targets don't race.
        my $xcat_home = "/tmp/mockbuild-all-$run_id/xcat-home";
        my $mktree = join(' ', map { shell_quote("$xcat_home/rpmbuild/$_") } qw(SOURCES SPECS BUILD BUILDROOT RPMS SRPMS));
        my $cmd = "mkdir -p $mktree && HOME=" . shell_quote($xcat_home) . ' ' . join(' ',
            'perl', shell_quote("$xcat_src/buildrpms.pl"),
            '--target', shell_quote($target),
            '--nproc', int($nproc),
            '--force',
            '--verbose',
            '--xcat_dep_path', shell_quote($repo_root),
        );
        push @build_steps, {
            id   => 'xcat',
            step => 'Build xCAT packages',
            cmd  => $cmd,
            cwd  => $xcat_src,
            log  => "$log_root/xcat-build.log",
        };
    }

    # xCAT-genesis-base is OS-dependent (its initramfs bundles the build chroot's
    # kernel + glibc/busybox/perl), so it is built here, per target, and shipped
    # in this per-EL xcat-dep repo rather than in the flat xcat-core. buildrpms.pl
    # (run in the xcat-core dir) derives the same snapYYYYMMDDHHMM Release from
    # xcat-core's Gitepoch, so it matches xCAT-genesis-scripts (built in core) and
    # the exact-version dependency genesis-scripts -> genesis-base resolves.
    if (!$skip_genesis) {
        # buildrpms.pl stages sources in $HOME/rpmbuild (via rpmdev-setuptree). Give each
        # per-target genesis build its own HOME so parallel EL targets don't race on the shared
        # /root/rpmbuild tree (that race is what made concurrent genesis builds fail).
        my $genesis_home = "/tmp/mockbuild-all-$run_id/genesis-home";
        # buildrpms.pl's rpmdev-setuptree only runs during env setup, not per build, so create the
        # rpmbuild tree ourselves for this per-target HOME (else $HOME/rpmbuild/SOURCES is missing).
        my $mktree = join(' ', map { shell_quote("$genesis_home/rpmbuild/$_") } qw(SOURCES SPECS BUILD BUILDROOT RPMS SRPMS));
        my $cmd = "mkdir -p $mktree && HOME=" . shell_quote($genesis_home) . ' ' . join(' ',
            'perl', shell_quote("$xcat_src/buildrpms.pl"),
            '--package', 'xCAT-genesis-base',
            '--target', shell_quote($target),
            '--nproc', int($nproc),
            '--force',
            '--verbose',
            '--xcat_dep_path', shell_quote($repo_root),
        );
        push @build_steps, {
            id   => 'genesis',
            step => 'Build xCAT-genesis-base (per-target, OS-dependent)',
            cmd  => $cmd,
            cwd  => $xcat_src,
            log  => "$log_root/genesis-build.log",
        };
    }

    if (@build_steps) {
        # Prefer the caller-supplied cap (global budget / active targets). Fall back to the old
        # behaviour (all steps at once) only when unset.
        my $effective_parallel_builds =
              ($max_build_workers && $max_build_workers >= 1) ? $max_build_workers
            : defined($parallel_builds)                       ? $parallel_builds
            :                                                   scalar(@build_steps);
        run_build_steps_parallel(
            steps         => \@build_steps,
            max_processes => $effective_parallel_builds,
        );
    }
}

my $xcat_rpms_dir = "$xcat_src/dist/$target/rpms";
my $xcat_srpms_dir = "$xcat_src/dist/$target/srpms";

# In monolithic mode (no --skip-xcat) the whole xCAT core built here (incl.
# genesis-base) is collected into this repo. In the split pipeline (--skip-xcat,
# core built separately) the orchestrator (cluster-test.pl) routes
# xCAT-genesis-base from the xCAT dist tree into the per-EL dep repo itself --
# robust to this script exiting non-zero on tolerated dep-builder failures -- so
# we deliberately do NOT collect the xCAT dist tree here.
if (!$skip_xcat) {
    push @collect_roots, $xcat_rpms_dir;
}

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

push @collect_roots, @extra_collect_dirs;
@collect_roots = uniq(@collect_roots);
my @srpm_collect_roots = (!$skip_xcat)
    ? uniq(@collect_roots, $xcat_srpms_dir)
    : uniq(@collect_roots);

if ($genesis_release && !$dry_run) {
    remove_genesis_packages($repo_dir, 0);
    remove_genesis_packages($srpm_repo_dir, 1);
}

print_step('Collect RPM artifacts');
print "collection roots:\n";
print "  $_\n" for @collect_roots;

my ($copied, $skipped_src, $missing_roots) = collect_rpms(
    roots    => \@collect_roots,
    dest_dir => $repo_dir,
    dry_run  => $dry_run,
);

# Assert on what this run BUILT, before the Genesis release is added: the release is
# installed from a verified directory rather than built here, so counting it first would
# let a run whose builders all failed reach createrepo and the deployable tree, and fail
# much later in assert_required_deps naming packages instead of the failed builds.
if (!$dry_run && $copied == 0) {
    die "No binary RPMs were collected. Check build logs and collection roots.\n";
}

# Ensure the OS-dependent xCAT-genesis-base rpm (built by the genesis step above)
# lands in the dep repo even when the full xCAT core is built elsewhere (--skip-xcat).
if (!$skip_genesis && !$dry_run) {
    for my $g (bsd_glob("$xcat_rpms_dir/xCAT-genesis-base-*.rpm")) {
        next if $g =~ /\.src\.rpm$/;
        copy($g, "$repo_dir/" . basename($g))
            or die "Failed to copy genesis-base $g -> $repo_dir: $!\n";
        $copied++;
    }
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
        cmd  => createrepo_c_cmd($repo_dir),
        log  => "$log_root/createrepo.log",
    );
    run_step(
        step => 'Run createrepo for SRPM repo',
        cmd  => createrepo_c_cmd($srpm_repo_dir),
        log  => "$log_root/createrepo-srpm.log",
    );
}

if (!$skip_tarball) {
    my $cmd = join(' ',
        'tar', '--sort=name', '--owner=0', '--group=0',
        "--mtime=\@$SOURCE_DATE_EPOCH",
        '-C', shell_quote($run_root),
        '-czf', shell_quote($tarball),
        'repo'
    );
    run_step(
        step => 'Create tarball',
        cmd  => $cmd,
        log  => "$log_root/tarball.log",
    );
    my $srpm_cmd = join(' ',
        'tar', '--sort=name', '--owner=0', '--group=0',
        "--mtime=\@$SOURCE_DATE_EPOCH",
        '-C', shell_quote($run_root),
        '-czf', shell_quote($srpm_tarball),
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
    print {$sfh} "arch=$profile->{arch}\n";
    print {$sfh} "os_id=$os_id\n";
    print {$sfh} "version_id=$version_id\n";
    print {$sfh} "rel=$rel\n";
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
print "Summary:               $summary_file\n" if !$dry_run;
print "Tarball:               $tarball\n" if !$skip_tarball;
print "SRPM Tarball:          $srpm_tarball\n" if !$skip_tarball;

    return { repo_dir => $repo_dir, rel => $rel, profile => $profile };
}

# The build profile of a target: EL release, arch of the rpms, where its noarch deps are built,
# which dep builders run and which rpms the deployed repo must contain.
sub target_profile {
    my ($target) = @_;
    if (my $fa = $forcearch_targets{$target}) {
        return {
            %{$fa},
            forcearch => 1,
            epel      => 0,
        };
    }
    my ($rel) = $target =~ /epel-(\d+)-/;
    die "Could not parse EL release from target '$target'\n" unless defined $rel;
    return {
        rel          => $rel,
        arch         => $host_arch,
        noarch_cfg   => $target,
        forcearch    => 0,
        epel         => 1,
        dep_builders => [qw(elilo-xcat grub2-xcat ipmitool-xcat syslinux-xcat goconserver conserver-xcat xnba-undi)],
        # xCAT Requires all of these on every arch, and every one of them builds natively on
        # every arch (the noarch deps -- grub2-xcat, xnba-undi -- just repackage committed
        # artifacts), so a self-sufficient per-arch build produces the whole set.
        required     => [qw(ipmitool-xcat syslinux-xcat grub2-xcat xnba-undi
                            perl-IO-Stty perl-HTTP-Async perl-Net-HTTPS-NB)],
    };
}

# The forcearch targets are shipped in mock-configs/; mock, and the include('/etc/mock/<cfg>.cfg')
# overlays of the per-package builders, need them in /etc/mock. Install a missing one; never
# overwrite one the host already has.
sub install_mock_cfg {
    my ($cfg) = @_;
    my $src = "$repo_root/mock-configs/$cfg.cfg";
    return if !-f $src;
    my $dst = "/etc/mock/$cfg.cfg";
    if (-f $dst) {
        die "$dst differs from $src: the build would not use the configuration shipped in this"
          . " tree. Remove or update the host copy (it is never overwritten here) and rerun.\n"
            if system("cmp -s " . shell_quote($src) . ' ' . shell_quote($dst)) != 0;
        return;
    }
    print "Installing mock config $src -> $dst\n";
    return if $dry_run;
    copy($src, $dst) or die "Failed to install $src -> $dst: $!\n";
    chmod 0644, $dst;
}

# Assemble the built per-target repo into the deployable, signed per-EL layout
# <repo-dep>/rh<rel>/<arch>: copy the binary rpms, sign, createrepo, and drop the
# xcat-dep.repo / mklocalrepo.sh / buildinfo.txt (ready to push to xcat.org).
sub deploy_target {
    my ($tgt, $info) = @_;
    my $rel   = $info->{rel};
    my $src   = $info->{repo_dir};
    my $tarch = $info->{profile}{arch};
    my $dest  = "$repo_dep/rh$rel/$tarch";
    print_step("Deploy $tgt -> $dest");
    return if $dry_run;
    make_path($dest);
    for my $rpm (bsd_glob("$src/*.rpm")) {
        next if $rpm =~ /\.src\.rpm$/;
        my $destination = "$dest/" . basename($rpm);
        publish_file($rpm, $destination);
    }
    remove_genesis_packages($dest, 0) if $genesis_release;
    assert_required_deps($dest, $info->{profile}{required});
    sign_and_index_repo($dest);
    write_dep_repo_metadata($dest, $rel, $tarch);
    my $n = scalar(grep { !/\.src\.rpm$/ } bsd_glob("$dest/*.rpm"));
    print "Deployed rh$rel/$tarch: $n rpms\n";
}

sub publish_genesis_common_repo {
    my $dest = "$repo_dep/common";
    print_step("Publish OpenEmbedded Genesis -> $dest");

    if ($dry_run) {
        preview_genesis_release_packages('rpm', $dest);
        return;
    }

    $COMMON_STAGE = tempdir('.common.XXXXXXXX', DIR => $repo_dep, CLEANUP => 0);
    my $published = publish_genesis_release_packages('rpm', $COMMON_STAGE);
    verify_genesis_release_packages('rpm', $COMMON_STAGE);
    sign_and_index_repo($COMMON_STAGE);
    write_common_repo_metadata($COMMON_STAGE);
    chmod(0755, $COMMON_STAGE)
      or die "Cannot make $COMMON_STAGE traversable: $!\n";
    replace_common_repository($COMMON_STAGE, $dest);
    print "Published common Genesis repository: $published rpms\n";
}

sub replace_common_repository {
    my ($staged, $destination) = @_;
    my $backup = "$repo_dep/.common.previous.$$";
    remove_tree($backup) if -e $backup || -l $backup;

    $COMMON_DESTINATION = $destination;
    if (-e $destination || -l $destination) {
        $COMMON_BACKUP = $backup;
        rename($destination, $backup)
          or die "Cannot preserve $destination before publication: $!\n";
    }
    unless (rename($staged, $destination)) {
        my $error = $!;
        rename($backup, $destination) if $COMMON_BACKUP && -d $backup;
        die "Cannot publish $destination: $error\n";
    }
    undef($COMMON_STAGE);
    undef($COMMON_DESTINATION);
    remove_tree($backup) if $COMMON_BACKUP && -d $backup;
    undef($COMMON_BACKUP);
}

sub publish_file {
    my ($source, $destination) = @_;
    my ($temporary_fh, $temporary) = tempfile(
        '.xcat-deploy.XXXXXX',
        DIR    => dirname($destination),
        UNLINK => 0,
    );
    close($temporary_fh) or die "Cannot close deployment staging file: $!\n";

    my $mode = (stat($source))[2];
    die "Cannot read mode from $source: $!\n" unless defined($mode);
    my $published = eval {
        copy($source, $temporary)
          or die "Failed to stage $source -> $temporary: $!\n";
        chmod($mode & 0x0fff, $temporary)
          or die "Failed to set mode on $temporary: $!\n";
        rename($temporary, $destination)
          or die "Failed to publish $temporary -> $destination: $!\n";
        1;
    };
    return if $published;

    my $error = $@ || "Failed to publish $source\n";
    unlink($temporary) if -e $temporary || -l $temporary;
    die $error;
}

# createrepo_c command with upstream-matching, deterministic metadata. The tool's
# defaults emit primary/filelists/other as *.xml.zst plus *.sqlite.bz2 (--database),
# exactly the upstream shape; --set-timestamp-to-revision pins repomd to SOURCE_DATE_EPOCH.
sub createrepo_c_cmd {
    my ($dir) = @_;
    return 'createrepo_c --update --database '
        . '--revision ' . shell_quote($SOURCE_DATE_EPOCH) . ' --set-timestamp-to-revision '
        . shell_quote($dir);
}

sub sign_and_index_repo {
    my ($dir) = @_;
    my @rpms = grep { !/\.src\.rpm$/ } bsd_glob("$dir/*.rpm");
    if ($gpg_sign && @rpms) {
        local $ENV{GNUPGHOME} = $gpg_home if $gpg_home;
        run_simple('rpmsign --define ' . shell_quote("%_gpg_name $gpg_key_name")
            . ' --define ' . shell_quote("%__gpg $gpg_program") . ' --addsign '
            . join(' ', map { shell_quote($_) } @rpms));
    }
    run_simple(createrepo_c_cmd($dir));
    if ($gpg_sign) {
        local $ENV{GNUPGHOME} = $gpg_home if $gpg_home;
        my $repomd = "$dir/repodata/repomd.xml";
        unlink "$repomd.asc" if -f "$repomd.asc";
        run_simple(qq(gpg -a --detach-sign --default-key "$gpg_key_name" ) . shell_quote($repomd));
        run_simple(qq(gpg -a --export "$gpg_key_name" > ) . shell_quote("$repomd.key"));
    }
}

sub write_dep_repo_metadata {
    my ($dir, $rel, $tarch) = @_;
    my $baseurl = "https://xcat.org/files/xcat/repos/yum/devel/xcat-dep/rh$rel/$tarch";
    my $gpgcheck = $gpg_sign ? 1 : 0;
    my $gpgkey_line = $gpg_sign ? "gpgkey=$baseurl/repodata/repomd.xml.key" : "# gpgkey=";
    open my $r, '>', "$dir/xcat-dep.repo" or die "Cannot write $dir/xcat-dep.repo: $!\n";
    print {$r} <<"EOF";
[xcat-dep]
name=xCAT 2 dependencies (rh$rel $tarch)
baseurl=$baseurl
enabled=1
gpgcheck=$gpgcheck
$gpgkey_line
EOF
    close $r;

    write_local_repo_helper($dir);
    write_buildinfo($dir, "rh$rel/$tarch");
}

sub write_common_repo_metadata {
    my ($dir) = @_;
    my $baseurl = "https://xcat.org/files/xcat/repos/yum/devel/xcat-dep/common";
    my $gpgcheck = $gpg_sign ? 1 : 0;
    my $gpgkey_line = $gpg_sign ? "gpgkey=$baseurl/repodata/repomd.xml.key" : "# gpgkey=";
    open my $r, '>', "$dir/xcat-dep-common.repo"
      or die "Cannot write $dir/xcat-dep-common.repo: $!\n";
    print {$r} <<"EOF";
[xcat-dep-common]
name=xCAT 2 common dependencies
baseurl=$baseurl
enabled=1
gpgcheck=$gpgcheck
repo_gpgcheck=$gpgcheck
skip_if_unavailable=1
$gpgkey_line
EOF
    close $r;

    write_local_repo_helper($dir);
    write_buildinfo($dir, 'common');
}

sub write_local_repo_helper {
    my ($dir) = @_;

    open my $m, '>', "$dir/mklocalrepo.sh" or die "Cannot write $dir/mklocalrepo.sh: $!\n";
    print {$m} <<'EOS';
#!/bin/sh
SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIRECTORY" || exit 1
set -- xcat-*.repo
if [ "$#" -ne 1 ] || [ "$1" = "xcat-*.repo" ]; then
    echo "ERROR: Execute $0 in an xcat-dep repository directory"
    exit 1
fi
REPOFILE=$1
DIRECTORY="/etc/yum.repos.d"
if [ ! -d "$DIRECTORY" ]; then
    DIRECTORY="/etc/zypp/repos.d"
fi
CURRENT_DIRECTORY=$(pwd)
sed -e 's|baseurl=.*|baseurl=file://'"$CURRENT_DIRECTORY"'|' "$REPOFILE" \
  | sed -e 's|gpgkey=.*|gpgkey=file://'"$CURRENT_DIRECTORY"'/repodata/repomd.xml.key|' \
  > "$DIRECTORY/$REPOFILE"
EOS
    close $m;
    chmod 0775, "$dir/mklocalrepo.sh";
}

sub write_buildinfo {
    my ($dir, $target) = @_;
    my $build_time = strftime("%a %b %e %H:%M:%S %Z %Y", gmtime($SOURCE_DATE_EPOCH));
    my $build_machine = `hostname`; chomp $build_machine;
    my $commit = `git -C "$repo_root" rev-parse HEAD 2>/dev/null`; chomp $commit;
    $commit ||= 'unknown';
    my $commit_short = substr($commit, 0, 7);
    my $release = strftime('snap%Y%m%d%H%M', gmtime($SOURCE_DATE_EPOCH));
    open my $b, '>', "$dir/buildinfo.txt" or die "Cannot write $dir/buildinfo.txt: $!\n";
    print {$b} <<"EOF";
TARGET=$target
RELEASE=$release
BUILD_TIME=$build_time
BUILD_MACHINE=$build_machine
COMMIT_ID=$commit_short
COMMIT_ID_LONG=$commit
SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH
EOF
    close $b;
}

sub usage {
    return <<"USAGE";
Usage: $0 [options]

Build xcat-dep and xCAT RPMs, consolidate binary/source artifacts, run createrepo, and create tarballs.

Options:
  --repo-root PATH        xcat-dep repository root (default: script directory)
  --xcat-source PATH      xCAT source root with buildrpms.pl (default: <repo-root>/../xcat-core)
  --output PATH           Single base for ALL output; --output-root and --repo-dep derive from
                          it. A fail-fast lock is held at <PATH>/.lock, so pass distinct paths
                          to run on two hosts in parallel on one NFS (default: <repo-root>/build-output)
  --output-root PATH      Override the derived build tree root (default: <output>/mockbuild-all)
  --repo-dep PATH         Override the deployable output root; rh8/rh9/rh10/<arch> and common
                          are assembled and signed here (default: <output>/xcat-dep)
  --force-unlock          Remove a stale <output>/.lock before acquiring it
  --gpg-sign              Sign RPMs and repomd.xml in every published repository
  --gpg-key-name NAME     GPG key name (default: "xCAT Signing Key")
  --gpg-home PATH         GNUPGHOME for signing (default: system keyring)
  --target NAME           Build only this target (<ID>+epel-<REL>-<ARCH>, or a forcearch
                          config from mock-configs/ such as rocky-10-riscv64-xcat, which
                          cross-builds that arch on this host); default is the host arch
                          across rh8, rh9 and rh10
  --nproc N               Parallel jobs for buildrpms.pl (default: 1)
  --parallel-builds N     Max concurrent top-level build steps within one EL target (default: auto)
  --parallel-targets N    Concurrent EL targets (rh8/rh9/rh10). 0/auto = all at once, 1 = serial,
                          N = cap at N. Each target is fully output-isolated (default: auto)
  --max-parallel N        Global cap on concurrent mock builds across ALL targets, to avoid
                          oversubscribing the host. Split evenly across active targets.
                          0/auto = host nproc (default: auto)
  --run-id ID             Run identifier suffix (default: derived from build timestamp)
  --build-timestamp EPOCH Unix epoch for deterministic builds (default: Gitepoch or git log)
  --skip-install          Skip install/smoke tests in child builder scripts
  --skip-build            Skip all build steps and only collect/create repo/tarballs
  --skip-xcat-dep         Skip xcat-dep mockbuild.pl package steps
  --skip-perl             Skip perl package build step
  --skip-xcat             Skip xCAT buildrpms.pl step
  --skip-genesis          Skip the existing per-EL Genesis image build
  --skip-createrepo       Skip createrepo
  --skip-tarball          Skip binary/SRPM tarball creation
  --genesis-release PATH  Publish a verified OpenEmbedded Genesis RPM release in common
  --scrub-all-chroots     Run mock -r <target> --scrub=all before build/collect
  --collect-dir PATH      Additional directory to scan recursively for RPMs (repeatable)
  --dry-run               Print planned commands without executing

Notes:
  - Run this script as root on the build host.
  - ARCH is derived from: uname -m (or from the forcearch target)
  - Top-level parallel queue includes xcat-dep mockbuild.pl steps, perl builder,
    and ../xcat-core/buildrpms.pl.
  - Child mockbuild scripts are invoked with per-step mock --uniqueext values
    to avoid lock collisions on the same mock config.
  - If --target is omitted, it is deduced from /etc/os-release:
      ID + epel + int(VERSION_ID) + ARCH
USAGE
}

sub run_simple {
    my ($cmd) = @_;
    my $rc = system($cmd);
    if ($rc != 0) {
        my $exit = $rc == -1 ? 255 : ($rc >> 8);
        die "Command failed (rc=$exit): $cmd\n";
    }
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
        $full_cmd = "cd " . shell_quote($cwd) . " && $cmd";
    }
    if ($log) {
        my $log_dir = dirname($log);
        make_path($log_dir) if !-d $log_dir;
        $full_cmd .= " > " . shell_quote($log) . " 2>&1";
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

    # Individual dep-builder failures are TOLERATED (some packages are el-/arch-pinned or
    # have dead upstream source URLs, e.g. elilo on el10, perl-Sys-Virt on el8, a moved grub2
    # src.rpm). We collect whatever built and assert the REQUIRED set later (assert_required_deps),
    # matching the historical build behaviour.
    if ($dry_run || $max_processes <= 1 || @{$steps} == 1) {
        my $serial_failures = 0;
        for my $step (@{$steps}) {
            my $ok = eval { run_step(%{$step}); 1 };
            next if $ok;
            $serial_failures++;
            warn "WARN: build step failed (tolerated): $step->{step}\n" . ($@ // '');
        }
        assert_build_progress(scalar(@{$steps}), $serial_failures);
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
        # Tolerated: warn, don't die. The REQUIRED set is asserted after collection/deploy.
        warn "WARN: some build steps failed (tolerated; required deps asserted after deploy):\n  "
            . join("\n  ", @lines) . "\n";
    }

    assert_build_progress(scalar(@{$steps}), scalar(keys %failed));
}

# Individual failures are tolerated because some packages are el- or arch-pinned. ALL of them
# failing is a different thing: the builder itself is unusable (no mock, a broken chroot, no
# network), this invocation produced nothing, and every package the run would go on to publish
# would come from somewhere other than this build.
sub assert_build_progress {
    my ($attempted, $failures) = @_;
    return unless every_step_failed($attempted, $failures);
    die "FATAL: every build step failed ($failures/$attempted). Check the build logs.\n";
}

# have_rpm: is there a non-src rpm named <name>-... under $dir?
sub have_rpm {
    my ($dir, $name) = @_;
    my @m = grep { !/\.src\.rpm$/ } bsd_glob("$dir/${name}-*.rpm");
    return scalar(@m) > 0;
}

# assert_required_deps: the per-EL dep repo is unusable without these (the target profile's
# required set), so a MISSING one is fatal even though individual builder failures are
# tolerated above. genesis-base is required unless --skip-genesis.
sub assert_required_deps {
    my ($dir, $required) = @_;
    my @req = @{$required};
    push @req, 'xCAT-genesis-base' unless $skip_genesis;
    my @missing = grep { !have_rpm($dir, $_) } @req;
    die "FATAL: required deps missing from $dir: @missing\n" if @missing;
    print "[deps] required set present in $dir: @req\n";
}

sub reset_staging_repo {
    my ($directory) = @_;
    return unless -d $directory;
    opendir(my $dh, $directory) or die "Cannot read $directory: $!\n";
    my @stale = grep { /\.rpm\z/ } readdir($dh);
    closedir($dh) or die "Cannot close $directory: $!\n";
    return unless @stale;
    print "Removing " . scalar(@stale) . " package(s) left in $directory by an earlier run\n";
    for my $name (@stale) {
        unlink("$directory/$name")
            or die "Cannot remove stale package $directory/$name: $!\n";
    }
    return;
}

sub remove_genesis_packages {
    my ($directory, $source, $keep_names) = @_;
    return unless -d $directory;
    my %keep = map { $_ => 1 } @{ $keep_names // [] };
    opendir(my $dh, $directory) or die "Cannot read $directory: $!\n";
    my @names = grep { /^xCAT-genesis-openembedded-.*\.rpm\z/ } readdir($dh);
    closedir($dh) or die "Cannot close $directory: $!\n";
    for my $name (@names) {
        next if $keep{$name};
        my $path = "$directory/$name";
        next if $source && $path !~ /\.src\.rpm\z/;
        next if !$source && $path =~ /\.src\.rpm\z/;
        unlink($path) or die "Cannot remove stale Genesis package $path: $!\n";
    }
}

sub publish_genesis_release_packages {
    my ($prefix, $destination_root) = @_;
    remove_genesis_packages($destination_root, $prefix eq 'srpm');
    remove_genesis_packages($destination_root, 1) if $prefix eq 'rpm';

    my $copied = 0;
    for my $relative (genesis_release_files($prefix)) {
        my $source = "$genesis_release/$relative";
        my $destination = "$destination_root/" . basename($relative);
        publish_file($source, $destination);
        verify_release_file($genesis_release_checksums, $relative, $destination);
        $copied++;
    }
    die "Genesis release has no $prefix packages\n" unless $copied;
    return $copied;
}

# Dry runs copy nothing, but they must still report the shared packages a real run publishes.
sub preview_genesis_release_packages {
    my ($prefix, $destination_root) = @_;
    my @files = genesis_release_files($prefix);
    die "Genesis release has no $prefix packages\n" unless @files;
    for my $relative (@files) {
        print "DRY-RUN publish Genesis release package: $genesis_release/$relative"
          . " -> $destination_root/" . basename($relative) . "\n";
    }
    return scalar(@files);
}

sub genesis_release_files {
    my ($prefix) = @_;
    my @files = sort grep {
        /^\Q$prefix\E\/xCAT-genesis-openembedded-[^\/]+\.rpm\z/
    } keys %{$genesis_release_checksums};
    return @files;
}

sub verify_genesis_release_packages {
    my ($prefix, $destination_root) = @_;
    my @files = genesis_release_files($prefix);
    die "Genesis release has no $prefix packages\n" unless @files;
    for my $relative (@files) {
        my $destination = "$destination_root/" . basename($relative);
        verify_release_file($genesis_release_checksums, $relative, $destination);
    }
    return scalar(@files);
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
            next if $genesis_release
              && $base =~ /^xCAT-genesis-openembedded-/;
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
            next if $genesis_release
              && $base =~ /^xCAT-genesis-openembedded-/;
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

sub resolve_mock_cfg {
    my ($os_id, $rel, $arch) = @_;
    my %short_forms = (
        almalinux      => 'alma',
        'centos-stream' => 'centos-stream',
        rocky          => 'rocky',
    );
    my $candidate = "${os_id}+epel-${rel}-${arch}";
    my $rc = system("mock -r " . shell_quote($candidate) . " --print-root-path >/dev/null 2>&1");
    if ($rc == 0) {
        return $candidate;
    }
    if (exists $short_forms{$os_id}) {
        my $short = $short_forms{$os_id};
        $candidate = "${short}+epel-${rel}-${arch}";
        $rc = system("mock -r " . shell_quote($candidate) . " --print-root-path >/dev/null 2>&1");
        if ($rc == 0) {
            print "Mock config resolved (short form): $candidate\n";
            return $candidate;
        }
    }
    die "Could not find mock config for ${os_id}+epel-${rel}-${arch}\n";
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
    # Prefer the sibling ../xcat-core (the real layout: source/xcat-core beside source/xcat-dep)
    # before the legacy xcat-source-code location.
    my @candidates = (
        $requested,
        "$root/../xcat-core",
        "$root/xcat-source-code",
    );
    for my $c (@candidates) {
        next if !defined($c) || $c eq '';
        my $abs = eval { abs_path($c) };
        next if !$abs;
        return $abs if -f "$abs/buildrpms.pl";
    }
    return eval { abs_path($requested) } || $requested;
}

# Fail-fast advisory lock on the output base. Uses an atomic mkdir (portable and reliable over
# NFS, unlike flock) of "<base>/.lock". A second run against the same --output dies immediately
# rather than racing on the shared tree. Only the process that created the lock removes it.
sub acquire_named_lock {
    my ($base, $label, $force) = @_;
    my $lock = "$base/.lock";
    if ($force && -d $lock) {
        print "force-unlock: removing stale lock $lock\n";
        _rmdir_lock($lock);
    }
    if (mkdir $lock) {
        push(@HELD_LOCKS, $lock);
        $LOCK_OWNER_PID //= $$;
        my $host = capture_command('uname', '-n') || 'unknown';
        if (open my $fh, '>', "$lock/owner") {
            print {$fh} "host=$host\npid=$$\nepoch=" . time() . "\n";
            close $fh;
        }
        return;
    }
    # mkdir failed: either it already exists (locked) or a real error.
    if (-d $lock) {
        my $info = '';
        if (open my $fh, '<', "$lock/owner") { local $/; $info = <$fh>; close $fh; }
        $info =~ s/\s+/ /g;
        die "$label $base is locked ($lock): $info\n"
          . "another mockbuild-all run owns it; use a different destination or --force-unlock if stale.\n";
    }
    die "Cannot create lock $lock: $!\n";
}

sub acquire_output_lock {
    my ($base, $force) = @_;
    acquire_named_lock($base, 'output', $force);
}

sub acquire_repository_lock {
    my ($base, $force) = @_;
    _recover_common_repository($base) if $force;
    acquire_named_lock($base, 'repository', $force);
}

sub _recover_common_repository {
    my ($base) = @_;
    my $destination = "$base/common";
    my @backups = sort {
        ((stat($a))[9] // 0) <=> ((stat($b))[9] // 0)
    } grep { -d $_ && !-l $_ } bsd_glob("$base/.common.previous.*");

    if (!-e $destination && !-l $destination && @backups) {
        my $backup = pop(@backups);
        rename($backup, $destination)
          or die "Cannot restore interrupted common repository $backup: $!\n";
    }
    remove_tree($_) for grep { -d $_ && !-l $_ } @backups;

    for my $staging (bsd_glob("$base/.common.*")) {
        next if $staging =~ m{/\.common\.previous\.};
        remove_tree($staging) if -d $staging && !-l $staging;
    }
}

sub _rmdir_lock {
    my ($lock) = @_;
    unlink "$lock/owner";
    rmdir $lock;
}

# Release locks on every exit path, but only from the process that acquired them.
# Forked build workers inherit the lock list and must leave the parent's locks alone.
sub _restore_common_repository {
    return unless defined($LOCK_OWNER_PID) && $$ == $LOCK_OWNER_PID;
    remove_tree($COMMON_STAGE)
      if $COMMON_STAGE && -d $COMMON_STAGE && !-l $COMMON_STAGE;
    if ($COMMON_DESTINATION && $COMMON_BACKUP
        && !-e $COMMON_DESTINATION && -d $COMMON_BACKUP) {
        rename($COMMON_BACKUP, $COMMON_DESTINATION);
    } elsif ($COMMON_DESTINATION && $COMMON_BACKUP
        && -d $COMMON_DESTINATION && -d $COMMON_BACKUP) {
        remove_tree($COMMON_BACKUP);
    }
}

sub _release_locks_if_owner {
    return unless defined($LOCK_OWNER_PID) && $$ == $LOCK_OWNER_PID;
    for my $lock (reverse(@HELD_LOCKS)) {
        _rmdir_lock($lock) if -d $lock;
    }
}
END {
    _restore_common_repository();
    _release_locks_if_owner();
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
