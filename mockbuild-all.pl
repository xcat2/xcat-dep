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
use Getopt::Long qw(GetOptions);
use Parallel::ForkManager;
use POSIX qw(strftime);
use FindBin qw($RealBin);
use lib $RealBin, "$RealBin/lib";
use MockBuildUtils qw(sh_quote print_step version_matches required_pkgs
                      install_deps_packages install_deps_command missing_perl_modules
                      read_manifest verify_repo_packages verify_repo_signature verify_rpm_signatures
                      rpm_version rpm_release rpm_sigmd5 restamp_release_line
                      cross_copy_genesis finalize_xcat_dep bump_dep_release_suffix
                      build_mock_uniqueext rpmkeys_checksig_problem);
# print_step and sh_quote come from MockBuildUtils above; XCAT::BuildUtils carries the same
# print_step, so it is deliberately NOT imported here (one definition, no redefinition warning).
use XCAT::BuildUtils qw(
  capture_command
  every_step_failed
  hashes_equal
  read_lines
  emulated_build_timeout
  require_command
  run_bounded
  run_command
  shell_quote
);
use XCAT::GenesisRelease qw(
  validated_release_checksums
  verify_release_file
);

# --- Mount-namespace isolation: guard the host cgroup against mock teardown propagation ----------
# mock mounts /sys/fs/cgroup into every build chroot. On these systemd build hosts every mount is
# `shared`, so the chroot's cgroup joins the HOST's cgroup peer group. When mock tears a chroot down
# -- its post-build --scrub, or an aborted build's cleanup -- the unmount PROPAGATES back through the
# shared peer group and unmounts the HOST's /sys/fs/cgroup, after which every later mock (and even new
# login sessions) dies with "Failed to determine whether the unified cgroups hierarchy is used: No
# medium found". This bit ppc hardest (it leaks corpse chroot mounts on abort) but x86 shares the same
# shared-cgroup exposure. Re-exec inside a private mount namespace made rslave
# (`unshare --mount --propagation slave`): the namespace still sees host mounts (slave = one-way), but
# nothing mock mounts/unmounts can propagate OUT to the host. As a bonus the namespace tears down every
# mount mock leaks when we exit, so an aborted build can no longer leave corpse mounts under
# /var/lib/mock. Best-effort: only as root (needs CAP_SYS_ADMIN) and only if `unshare` exists;
# otherwise warn loudly and continue unisolated. MOCKBUILD_ALL_MOUNTNS guards against a re-exec loop.
# Build-free modes (--verify-repo, --finalize-xcat-dep) run no mock and are documented no-root, so they
# skip the re-exec entirely -- no cgroup exposure, and no spurious non-root warning.
my $mountns_build_free = grep { /^--(?:verify-repo|finalize-xcat-dep|install-deps)(?:=|$)/ } @ARGV;
unless ($ENV{MOCKBUILD_ALL_MOUNTNS} || $mountns_build_free) {
    if ($> != 0) {
        warn "WARN: not root -- skipping mount-namespace isolation (host-cgroup propagation guard); "
           . "run as root in CI so mock chroot teardown cannot unmount the host /sys/fs/cgroup\n";
    } elsif (system('sh', '-c', 'command -v unshare >/dev/null 2>&1') != 0) {
        warn "WARN: 'unshare' not found -- skipping mount-namespace isolation; mock chroot teardown "
           . "may unmount the host /sys/fs/cgroup on a shared-propagation host\n";
    } else {
        $ENV{MOCKBUILD_ALL_MOUNTNS} = 1;
        # Absolute path to self (resolved against cwd, which unshare preserves) so the re-exec'd perl
        # finds a relative $0. A bare $PATH-only $0 isn't resolved (abs_path doesn't search $PATH), but
        # a shell invocation yields a full $0 there anyway.
        my $self = abs_path($0) // $0;
        my @reexec = ('unshare', '--mount', '--propagation', 'slave', '--', $^X, $self, @ARGV);
        exec { $reexec[0] } @reexec;
        # exec only returns on failure -- fall through and run unisolated rather than abort the build.
        warn "WARN: exec unshare failed ($!) -- continuing without mount-namespace isolation\n";
        delete $ENV{MOCKBUILD_ALL_MOUNTNS};
    }
}

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
# Per-build-step wall-clock bound for the dep and perl steps. undef = derived from the target arch
# (a forcearch target is cross-built through qemu-user); an explicit 0 removes the bound.
my $build_timeout;
my $run_id     = '';
my $build_timestamp;
# CD version bump: when set, every xcat-dep package spec's Release gets a
# ".snap<YYYYMMDDHHMM>.<build_number>" suffix so each pipeline run publishes a
# fresh, monotonic NVR (deploy's additive rsync is a no-op otherwise). NOT applied
# to xCAT-genesis-base (built from xcat-core, kept in lockstep with genesis-scripts).
my $build_number;
# Pinned goconserver upstream commit (xcat2/goconserver). goconserver 0.3.3 is unreleased (the
# newest tag is v0.3.2), so it exists only on master -- pin an immutable SHA instead of the moving
# branch so the build is reproducible. Bump this deliberately when uptaking a new goconserver.
my $GOCONSERVER_REF = '6166fe5ec1c5b3c20475e322a9f0e8e93c87e45f';
my $skip_build = 0;
my $skip_xcat_dep = 0;
my $skip_perl = 0;
my $install_deps = 0;
my $skip_genesis = 0;
my $skip_createrepo = 0;
my $skip_tarball = 0;
my $genesis_release = '';
my $genesis_release_checksums;
my $scrub_all_chroots = 0;
my $keep_buildroots = 0;   # keep per-step mock chroots after build (default: --scrub=chroot each)
my $dry_run = 0;
my @extra_collect_dirs;
my $repo_dep = '';
my $gpg_sign = 0;
my $gpg_key_name = 'xCAT Signing Key';
my $gpg_home = '';
my $gpg_program = '';
my $force_unlock = 0;
# --finalize-xcat-dep: post-build cross-arch genesis provisioning (issue #7610). Takes the two
# per-arch repo roots and cross-populates the noarch xCAT-genesis-base between them.
my $finalize_xcat_dep = 0;
my $x86_64_repo = '';
my $ppc64le_repo = '';
# --verify-repo=<repo>: standalone, build-free completeness + signature gate over one already-built
# per-target repo (see verify_target_repo). Empty means "not in standalone verify mode". The target
# is derived from the repo path (.../rh<N>/<arch> -> alma+epel-<N>-<arch>) or taken from --target.
my $verify_repo = '';
# --no-verify-repo suppresses the AUTOMATIC post-build gate deploy_target runs after each target is
# finalized+signed (for iteration/debug). Verification is ON by default.
my $no_verify_repo = 0;
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
    'finalize-xcat-dep!' => \$finalize_xcat_dep,
    'x86_64-repo=s'     => \$x86_64_repo,
    'ppc64le-repo=s'    => \$ppc64le_repo,
    'verify-repo=s'     => \$verify_repo,
    'no-verify-repo!'   => \$no_verify_repo,
    'target=s'          => \$target,
    'nproc=i'           => \$nproc,
    'parallel-builds=i' => \$parallel_builds,
    'parallel-targets=i' => \$parallel_targets,
    'max-parallel=i'    => \$max_parallel,
    'build-timeout=i'   => \$build_timeout,
    'run-id=s'          => \$run_id,
    'build-timestamp=i' => \$build_timestamp,
    'build-number=i'    => \$build_number,
    'skip-build!'       => \$skip_build,
    'skip-xcat-dep!'    => \$skip_xcat_dep,
    'skip-perl!'        => \$skip_perl,
    'install-deps!'     => \$install_deps,
    'skip-genesis!'     => \$skip_genesis,
    'skip-createrepo!'  => \$skip_createrepo,
    'skip-tarball!'     => \$skip_tarball,
    'genesis-release=s' => \$genesis_release,
    'scrub-all-chroots!' => \$scrub_all_chroots,
    'keep-buildroots!'  => \$keep_buildroots,
    'collect-dir=s@'    => \@extra_collect_dirs,
    'dry-run!'          => \$dry_run,
) or die usage();

die "Run as root (uid=$>)\n" if $> != 0 && !$finalize_xcat_dep && !$verify_repo;
# --skip-build collects a prior build's artifacts from that build's per-target tree, so it must
# know the target. Without --target the default is "all three EL targets", and each would collect
# the same artifacts and cross-publish them into every repo (foreign-EL / foreign-arch rpms).
die "--skip-build requires an explicit --target (collection is per-target)\n"
    if $skip_build && $target eq '';
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

# --verify-repo=<repo>: a distinct, build-free completeness + signature gate over ONE already-built
# per-target repo. The value is just the repo dir; the manifest comes from the script's existing
# resolution (repo_root/packages-manifest.conf) and the gpg key/home from --gpg-key-name/--gpg-home.
# The target is derived from the repo path (.../rh<N>/<arch> -> alma+epel-<N>-<arch>) unless --target
# is given. Delegates the whole check to verify_target_repo (the SAME gate the auto-run uses), so it
# exits 0 when complete or dies listing every problem. Runs alone -- no build, no lock, no root.
if ($verify_repo ne '') {
    require_command('rpm');
    my $rdir = abs_path($verify_repo) or die "--verify-repo repo '$verify_repo' not found\n";
    die "--verify-repo repo '$rdir' is not a directory\n" if !-d $rdir;
    my $tgt = $target ne '' ? $target : derive_target_from_repo_path($rdir);
    die "--verify-repo: cannot derive a target from repo path '$rdir'; pass --target\n"
        if !defined($tgt) || $tgt eq '';
    # sig_required=1: a standalone verify MUST assert the repomd signature (its documented contract),
    # never silently skip it when no gpg key/home is configured (that would be a false PASS on sigs).
    verify_target_repo($rdir, $tgt, undef, 1);   # manifest defaults to repo_root/packages-manifest.conf
    exit 0;
}

# --finalize-xcat-dep: a distinct, build-free mode. After BOTH arch build hosts have
# produced their per-EL repos (each carrying only its own xCAT-genesis-base), the x86_64
# repo must ALSO ship the noarch xCAT-genesis-base-ppc64 (so an x86_64 MN can netboot ppc
# nodes) and the ppc64le repo must ship xCAT-genesis-base-x86_64 -- the 2.17 behaviour
# that issue #7610 regressed. This mode ONLY cross-copies the genesis-base rpm(s) between
# the two repos (dropping any stale foreign-arch genesis) and re-indexes + re-signs the
# affected repomd; it builds nothing and holds no output lock.
if ($finalize_xcat_dep) {
    die "--finalize-xcat-dep requires --x86_64-repo and --ppc64le-repo\n"
        if $x86_64_repo eq '' || $ppc64le_repo eq '';
    require_command('createrepo_c');
    require_command('rpm');
    require_command('rpmsign') if $gpg_sign;
    require_command('gpg')     if $gpg_sign;
    my $x86 = abs_path($x86_64_repo) or die "--x86_64-repo '$x86_64_repo' not found\n";
    my $ppc = abs_path($ppc64le_repo) or die "--ppc64le-repo '$ppc64le_repo' not found\n";
    die "--x86_64-repo '$x86' is not a directory\n" if !-d $x86;
    die "--ppc64le-repo '$ppc' is not a directory\n" if !-d $ppc;
    # Inject the per-rpm gpg re-sign and the repo re-index as callbacks so the finalize logic in
    # MockBuildUtils stays free of this script's gpg/createrepo state.
    finalize_xcat_dep($x86, $ppc,
        sign => ($gpg_sign ? sub {
            my ($rpm) = @_;
            local $ENV{GNUPGHOME} = $gpg_home if $gpg_home;
            run_simple("rpmsign --define " . sh_quote("%_gpg_name $gpg_key_name") . " --addsign " . sh_quote($rpm));
        } : undef),
        reindex => \&reindex_and_sign_repo,
    );

    # finalize just RE-INDEXED + RE-SIGNED each per-EL repo and cross-copied the foreign-arch genesis
    # in -- i.e. it produced the FINAL shipped state, which the per-target gate in deploy_target (run
    # earlier, pre-finalize) never saw. So run the SAME manifest completeness + signature gate here, on
    # every finalized cell, so the build script verifies its own final output by default (no external
    # --verify-repo needed). Suppressible with --no-verify-repo.
    unless ($no_verify_repo) {
        my %seen;
        for my $root ($x86, $ppc) {
            my @cells = (glob("$root/rh*/x86_64"), glob("$root/rh*/ppc64le"));
            for my $d (sort @cells) {
                next unless -d $d;
                my $abs = abs_path($d);
                next if $seen{$abs}++;
                my $tgt = derive_target_from_repo_path($abs)
                    or die "FATAL: finalize verify -- cannot derive target from '$abs'\n";
                verify_target_repo($abs, $tgt);
            }
        }
    }
    exit 0;
}

# CD version bump. Rewrite every xcat-dep package spec's Release line in this
# (freshly-checked-out, git-clean) tree so the built rpms carry a fresh, monotonic
# NVR each run. Runs BEFORE any child builder is invoked. genesis-base lives under
# xcat-core, not $repo_root, so it is untouched (stays in lockstep with the deployed
# core's genesis-scripts).
my $RELEASE_BUMP = '';
if (defined $build_number) {
    die "--build-number must be a non-negative integer\n" if $build_number < 0;
    $RELEASE_BUMP = strftime('.snap%Y%m%d%H%M', gmtime($SOURCE_DATE_EPOCH)) . ".$build_number";
    # A dry run must not touch the tree. Report what would be stamped and leave the specs alone;
    # $RELEASE_BUMP is still set so the rest of the (no-op) dry-run plan reflects it.
    if ($dry_run) {
        print "[dry-run] would stamp Release suffix '$RELEASE_BUMP' on xcat-dep specs under $repo_root (no files written)\n";
    } else {
        bump_dep_release_suffix($repo_root, $RELEASE_BUMP);
    }
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

# --install-deps: make THIS host able to run the script, then exit. It has to come before the
# require_command checks below -- those are the very things it installs, and a host that lacks them
# would die here with no way to fix itself. Run once per build host, as root.
#
# The perl modules are re-checked by LOADING them afterwards rather than trusting the package
# manager: a module that is still missing is exactly the failure this mode exists to prevent, and it
# aborted CD runs mid-build twice (perl-File-Slurper on xcat-master-ub, perl-IPC-Cmd on
# xcat-master-ppc), each time as a compile-time error inside XCAT::BuildUtils.
if ($install_deps) {
    die "--install-deps must run as root (uid=$>)\n" if $> != 0;
    my @cmd = install_deps_command($os_id);
    print_step("Install build prerequisites ($os_id)");
    print "  " . join(' ', @cmd) . "\n";
    run_command(@cmd);
    my @modules = qw(File::Slurper IPC::Cmd Parallel::ForkManager Digest::SHA);
    my @missing = missing_perl_modules(@modules);
    die "FATAL: still missing after install: " . join(', ', @missing) . "\n" if @missing;
    print "  perl modules present: " . join(', ', @modules) . "\n";
    print "  host is ready\n";
    exit 0;
}

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

    # Per-target required set from packages-manifest.conf: build ONLY these packages, and fail the
    # run if any of them fails. A package absent from this target's section is not built for it.
    my %MANIFEST = read_manifest("$repo_root/packages-manifest.conf");
    my %req = %{ $MANIFEST{$target} // {} };
    die "FATAL: no manifest section for target '$target' in packages-manifest.conf\n"
        if !%req;

my $run_root     = "$output_root/$run_id";
my $build_root   = "$run_root/build-results";
my $log_root     = "$run_root/build-logs";
my $repo_dir     = "$run_root/repo/$arch";
my $summary_file = "$run_root/summary.txt";
my $tarball      = "$output_root/mockbuild-all-$target-$run_id.tar.gz";
my $srpm_repo_dir = "$run_root/repo-src";
my $srpm_tarball  = "$output_root/mockbuild-all-$target-$run_id-srpm.tar.gz";

# Each real build must start from a clean per-target tree. run_id is derived from the deterministic
# commit timestamp, so re-runs of the same commit resolve to the SAME $run_root -- without a wipe, a
# stale rpm or a stale perl status.txt from an earlier (possibly failed) run could be reused and mask
# a failure (see mockbuild-perl-packages.pl, which reads per-package status files back). --skip-build
# deliberately KEEPS the tree (it collects a prior build's artifacts); --dry-run writes nothing.
if (!$skip_build && !$dry_run && -d $run_root) {
    print "Cleaning stale per-target tree before build: $run_root\n";
    remove_tree($run_root);
}

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

# buildrpms.pl (in xcat-core) is only needed for the OS-dependent xCAT-genesis-base
# build below; the full xCAT core is built separately by the xcat-core pipeline.
die "Missing xCAT build script: $xcat_src/buildrpms.pl\n"
    if !$skip_genesis && !-f "$xcat_src/buildrpms.pl";

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
print "skip_genesis:     $skip_genesis\n";
print "skip_createrepo:  $skip_createrepo\n";
print "skip_tarball:     $skip_tarball\n";
print "scrub_all_chroots:$scrub_all_chroots\n";
print "keep_buildroots:  $keep_buildroots\n";
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

    # Bound only what can run emulated. A forcearch target (rocky-10-riscv64-xcat) cross-builds every
    # dep through qemu-user, where a deadlock burns no CPU and never returns. Native mock steps keep
    # their present, unbounded behaviour: no measurement of them exists here, and a bound guessed for
    # a step that legitimately runs long would turn a trusted cell red for no reason.
    # --build-timeout overrides both; 0 removes the bound.
    my $step_timeout = defined $build_timeout ? $build_timeout
                     : $profile->{forcearch}  ? emulated_build_timeout($arch, $host_arch)
                     :                          0;

    if (!$skip_xcat_dep) {
        for my $builder (@active_dep_builders) {
            next unless $req{ $builder->{name} };   # manifest: build only required dep packages
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
                # goconserver generates its spec at build time (from an upstream clone), so the
                # in-tree spec Release bump above cannot reach it. Hand the CD suffix down so its
                # NVR advances per run too, and pin the clone to an immutable commit (not the moving
                # 'master') so the build is reproducible.
                ($name eq 'goconserver'
                    ? ('--go-ref', sh_quote($GOCONSERVER_REF),
                       ($RELEASE_BUMP ne '' ? ('--release-suffix', sh_quote($RELEASE_BUMP)) : ()))
                    : ()),
            );
            push @build_steps, {
                id      => "xcat-dep:$name",
                step    => "Build xcat-dep: $name",
                cmd     => $cmd,
                timeout => $step_timeout,
                log     => "$log_root/$name/run.log",
                scrub_cfg       => $target,
                scrub_uniqueext => $step_uniqueext,
            };
            push @collect_roots, $step_result;
        }
    }

    my @perl_pkgs = sort grep { /^perl-/ } keys %req;   # manifest: perl packages required here
    if (!$skip_perl && @perl_pkgs) {
        my $perl_result = "$build_root/perl/$arch";
        my $perl_log    = "$log_root/perl/$arch";
        my $perl_uniqueext = build_mock_uniqueext($run_id, ++$build_step_seq, 'perl-list6');
        # Bound the perl builder's OWN internal parallelism to this target's budget; otherwise it
        # forks one mock build per perl package (~7), which -- multiplied by parallel EL targets --
        # oversubscribes the host.
        my $cmd = join(' ',
            'perl', sh_quote($perl_builder),
            '--mock-cfg', sh_quote($target),
            ($profile->{forcearch}
                ? ('--target-arch', sh_quote($arch), '--noarch-mock-cfg', sh_quote($profile->{noarch_cfg}))
                : ()),
            ($profile->{epel} ? () : ('--epel-gap')),
            '--mock-uniqueext', sh_quote($perl_uniqueext),
            '--result-dir', sh_quote($perl_result),
            '--log-dir', sh_quote($perl_log),
            '--work-dir', sh_quote("/tmp/mockbuild-all-$run_id/perl-list6"),
            '--packages', sh_quote(join(',', @perl_pkgs)),   # manifest: only required perl pkgs
            (($max_build_workers && $max_build_workers >= 1) ? ('--jobs', $max_build_workers) : ()),
            '--build-timestamp', $SOURCE_DATE_EPOCH,
            # CD bump: the in-tree spec Release bump above only reaches the spec-mode perl
            # packages; the srpm-mode ones (HTML-Form, IO-Stty, Net-Telnet) build from a
            # committed .src.rpm, so hand the suffix down for the builder to re-stamp them.
            ($RELEASE_BUMP ne '' ? ('--release-suffix', sh_quote($RELEASE_BUMP)) : ()),
            ($keep_buildroots ? '--keep-buildroots' : ()),
        );
        push @build_steps, {
            id      => 'perl',
            step    => 'Build perl xcat-dep packages',
            cmd     => $cmd,
            # The perl builder forks its own mock jobs, so under forcearch it is emulated too. Give it
            # the per-package budget times the number of packages it builds serially per worker.
            timeout => ($step_timeout ? $step_timeout * scalar(@perl_pkgs) : 0),
            log     => "$log_root/perl-build.log",
        };
        push @collect_roots, $perl_result;
    }

    # NOTE: this script builds ONLY xcat-dep (its dep packages, the perl packages, and
    # the OS-dependent xCAT-genesis-base below). The full xCAT core is built separately
    # by the xcat-core pipeline -- mockbuild-all no longer has a monolithic core-build path.

    # xCAT-genesis-base is OS-dependent (its initramfs bundles the build chroot's
    # kernel + glibc/busybox/perl), so it is built here, per target, and shipped
    # in this per-EL xcat-dep repo rather than in the flat xcat-core. buildrpms.pl
    # (run in the xcat-core dir) derives the same snapYYYYMMDDHHMM Release from
    # xcat-core's Gitepoch, so it matches xCAT-genesis-scripts (built in core) and
    # the exact-version dependency genesis-scripts -> genesis-base resolves.
    if (!$skip_genesis && $req{'xCAT-genesis-base'}) {
        # buildrpms.pl stages sources in $HOME/rpmbuild (via rpmdev-setuptree). Give each
        # per-target genesis build its own HOME so parallel EL targets don't race on the shared
        # /root/rpmbuild tree (that race is what made concurrent genesis builds fail).
        my $genesis_home = "/tmp/mockbuild-all-$run_id/genesis-home";
        # buildrpms.pl's rpmdev-setuptree only runs during env setup, not per build, so create the
        # rpmbuild tree ourselves for this per-target HOME (else $HOME/rpmbuild/SOURCES is missing).
        my $mktree = join(' ', map { sh_quote("$genesis_home/rpmbuild/$_") } qw(SOURCES SPECS BUILD BUILDROOT RPMS SRPMS));
        # The genesis chroot (xCAT-genesis-base-<target>) is SHARED across runs -- buildrpms.pl builds it
        # without a per-run --mock-uniqueext. mock's post-build scrub only runs on SUCCESS, so a killed
        # or failFast-interrupted prior run leaves the chroot stunted (missing /bin/sh), and mock REUSES
        # the corpse on the next run -> "FileNotFoundError: '/bin/sh'". Scrub it FIRST (best-effort: a
        # no-op on the first run before the config exists) so mock recreates the chroot from the cached
        # root; --scrub=bootstrap goes too (the genesis bootstrap chroot is part of the leak; genesis
        # carries no --mock-uniqueext), so the fresh chroot re-bootstraps from the root cache. mock takes the buildroot lock for --scrub and BLOCKS (not
        # skips) if a concurrent build holds it, but within a run the scrub is sequential before the
        # build and the CD topology never runs a second same-target build at once; `timeout` bounds even
        # a pathological wait so a stale lock can never hang the build.
        my $genesis_scrub = "{ timeout 300 mock -r " . sh_quote("xCAT-genesis-base-$target")
            . " --scrub=chroot --scrub=bootstrap >/dev/null 2>&1 || true; }";
        my $cmd = "mkdir -p $mktree && $genesis_scrub && HOME=" . sh_quote($genesis_home) . ' ' . join(' ',
            'perl', sh_quote("$xcat_src/buildrpms.pl"),
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
            scrub_cfg => "xCAT-genesis-base-$target",
        };
    }

    if (@build_steps) {
        # Prefer the caller-supplied cap (global budget / active targets). Fall back to the old
        # behaviour (all steps at once) only when unset.
        my $effective_parallel_builds =
              ($max_build_workers && $max_build_workers >= 1) ? $max_build_workers
            : defined($parallel_builds)                       ? $parallel_builds
            :                                                   scalar(@build_steps);
        # Make --max-parallel a REAL cap. The perl builder is a single step that internally forks up
        # to $effective_parallel_builds mock jobs of its own, so running it concurrently with the dep
        # builders pushed live mock builds to ~2x the cap. Run it in its OWN phase, after the dep
        # builders (which are quick) -- each phase then runs at most $effective_parallel_builds mock
        # builds, so the cap holds, at a small bounded wall-clock cost. (The perl step sets no
        # scrub_cfg and scrubs its own chroots; the scrub loop below still covers the dep/genesis steps.)
        my @perl_steps    = grep { $_->{id} eq 'perl' } @build_steps;
        my @nonperl_steps = grep { $_->{id} ne 'perl' } @build_steps;
        my @failed;
        push @failed, run_build_steps_parallel(
            steps => \@nonperl_steps, max_processes => $effective_parallel_builds,
        ) if @nonperl_steps;
        push @failed, run_build_steps_parallel(
            steps => \@perl_steps, max_processes => $effective_parallel_builds,
        ) if @perl_steps;

        # Reclaim each build step's mock chroot now that the step copied its RPMs/logs out to
        # its --result-dir (collect_rpms reads those, never /var/lib/mock). mock's own cleanup
        # leaves these chroots behind -- and keeps them entirely on failure -- so /var/lib/mock
        # grows ~15-17G per run until the host fills and every dnf transaction fails for lack of
        # space. Scrub each via `mock --scrub=chroot --scrub=bootstrap` (never rm): it takes the
        # chroot lock, so a chroot still used by a concurrent build is refused and safely skipped.
        # Both the build chroot and its per-uniqueext bootstrap are removed; the root cache stays
        # for fast rebuilds. Perl packages are scrubbed inside mockbuild-perl-packages.pl (it
        # derives its own per-package uniqueexts).
        unless ($keep_buildroots) {
            for my $s (@build_steps) {
                next unless defined $s->{scrub_cfg};
                (my $slug = $s->{id}) =~ s/[^\w.-]+/-/g;
                scrub_buildroot($s->{scrub_cfg}, $s->{scrub_uniqueext}, "$log_root/scrub-$slug.log");
            }
        }

        # Zero-tolerance: any build step that failed fails the whole run -- genesis included.
        # (xcat-core #7696 is merged: buildrpms.pl now exits 0 iff it actually produced the
        # genesis rpm, so there is no cosmetic non-zero exit left to tolerate. The old workaround
        # -- ignore a genesis failure when a matching rpm already exists in dist/ -- is gone; a
        # stale artifact from a previous build must never mask a failed genesis build.)
        die "FATAL: required build step(s) failed for $target: @failed\n" if @failed;
    }
}

# The xCAT core is built by the xcat-core pipeline, NOT here -- so we deliberately do
# NOT collect the xCAT dist tree. Only the OS-dependent xCAT-genesis-base rpm (built by
# the genesis step above) is pulled out of it, individually, further below.
my $xcat_rpms_dir = "$xcat_src/dist/$target/rpms";

if ($skip_build) {
    # Collect THIS target's previously-built artifacts from its own per-target build tree -- the
    # same $build_root a normal build populates (collect_rpms recurses). NOT the legacy EL-agnostic
    # build-output/list* dirs: those are scoped only by $arch, so an el8 rpm left there would be
    # pulled into an el9/el10 repo, and with --target omitted the same rpms would be published into
    # every EL repo. (--target is now required for --skip-build, see the option check above.)
    push @collect_roots, $build_root;
}

push @collect_roots, @extra_collect_dirs;
@collect_roots = uniq(@collect_roots);
my @srpm_collect_roots = uniq(@collect_roots);

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
# much later in the repo gate (verify_target_repo), naming missing packages instead of the
# failed builds.
if (!$dry_run && $copied == 0) {
    die "No binary RPMs were collected. Check build logs and collection roots.\n";
}

# Ensure the OS-dependent xCAT-genesis-base rpm (built by the genesis step above)
# lands in the dep repo -- pull it individually out of the xcat-core dist tree (the
# rest of that tree, the full xCAT core, is built + published by the xcat-core pipeline).
if (!$skip_genesis && !$dry_run) {
    for my $g (bsd_glob("$xcat_rpms_dir/xCAT-genesis-base-*.rpm")) {
        next if $g =~ /\.src\.rpm$/;
        copy($g, "$repo_dir/" . basename($g))
            or die "Failed to copy genesis-base $g -> $repo_dir: $!\n";
        $copied++;
    }
}

# Repo completeness -- every required package present at its pinned version (a '*' pin accepts any),
# missing packages included -- is now gated ONCE, centrally, in deploy_target via verify_target_repo
# (the single consolidated gate; it also runs under --skip-build and validates the deployed repo).
# The only per-build check kept here is the CD --build-number bump: confirm it actually LANDED in the
# built rpms' Release, since validating %{VERSION} alone can't catch a silently un-bumped NVR (which
# deploy's additive rsync would then dedup away). Every built dep + perl package carries the suffix;
# xCAT-genesis-base is intentionally NOT bumped (kept in lockstep with xcat-core's genesis-scripts).
if (!$dry_run && $RELEASE_BUMP ne '') {
    my @rmiss;
    for my $pkg (required_pkgs([sort keys %req], $skip_genesis, $skip_perl, $skip_xcat_dep)) {
        next if $pkg eq 'xCAT-genesis-base';
        my $rel = rpm_release($repo_dir, $pkg);
        next if !defined $rel;   # a missing rpm is caught by the completeness gate in deploy_target
        push @rmiss, "$pkg: Release '$rel' is missing the CD bump '$RELEASE_BUMP'"
            if index($rel, $RELEASE_BUMP) < 0;
    }
    die "FATAL: --build-number bump '$RELEASE_BUMP' did not land in built rpm(s) for $target:\n  "
      . join("\n  ", @rmiss) . "\n" if @rmiss;
    print "[manifest] Release bump '$RELEASE_BUMP' present on all built dep rpms for $target\n";
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

    # Stage the cell in a sibling temp dir, sign+index+verify it THERE, then atomically swap it into
    # place. This makes the deploy self-cleaning and atomic (PR #62 review #3):
    #   - self-cleaning: the cell is rebuilt from scratch each run, so stale snap-NVR rpms from an
    #     earlier build never accumulate. Previously deploy copied ADDITIVELY into an existing $dest
    #     and relied on the pipeline pre-wiping rh<N>/<arch> -- a standalone run accumulated versions.
    #   - atomic + verify-before-replace: a failed sign/index/verify leaves the previously-published
    #     cell untouched, and no reader ever sees a half-written cell.
    # The staging dir is a sibling of $dest, so the rename is a same-filesystem (atomic) move. The
    # cross-arch genesis (--finalize-xcat-dep) runs later and re-populates the foreign-arch genesis,
    # so rebuilding this single-arch cell from $src is correct.
    make_path(dirname($dest));
    my $stage = "$dest.stage.$$";
    remove_tree($stage) if -d $stage;
    make_path($stage);
    my $ok = eval {
        for my $rpm (bsd_glob("$src/*.rpm")) {
            next if $rpm =~ /\.src\.rpm$/;
            publish_file($rpm, "$stage/" . basename($rpm));
        }
        # --genesis-release: the release itself is published ONCE into <repo-dep>/common, not into
        # each per-EL cell, so nothing from it is kept here -- drop any stale OpenEmbedded Genesis
        # rpm an earlier layout left in the collection. On the STAGE, so the published cell is
        # already correct when it is swapped in.
        remove_genesis_packages($stage, 0) if $genesis_release;
        sign_and_index_repo($stage);
        write_dep_repo_metadata($stage, $rel, $tarch);
        # Automatic completeness + signature gate on the freshly signed cell -- the single
        # consolidated gate (verify_target_repo, the same one --verify-repo runs). Asserts every
        # manifest-required package is present at its pinned version, the repomd signature verifies,
        # AND every rpm is signed by the key. Runs on the STAGE so a failure never lands in $dest.
        # Suppressible with --no-verify-repo for iteration/debug.
        verify_target_repo($stage, $tgt) unless $no_verify_repo;
        1;
    };
    if (!$ok) {
        my $err = $@;
        remove_tree($stage);   # leave the previously-published cell exactly as it was
        die $err;
    }

    # Atomic replace: rename cannot overwrite a populated dir, so move the old cell aside, swap the
    # staged cell in, then drop the old one. On a failed final rename, restore the old cell.
    my $old = "$dest.old.$$";
    remove_tree($old) if -d $old;
    if (-d $dest) {
        rename($dest, $old) or die "Failed to move old cell $dest aside: $!\n";
    }
    unless (rename($stage, $dest)) {
        my $err = $!;
        rename($old, $dest) if -d $old && !-d $dest;   # best-effort restore
        die "Failed to swap staged cell into $dest: $err\n";
    }
    remove_tree($old) if -d $old;

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
    # Gate the STAGE, so an incomplete shared repo is never swapped into place. Completeness only:
    # the packages were verified against the release checksums as they were copied, and the deploy
    # asserts every rpm's signature, but until now nothing checked that the repository being
    # published actually carries the whole architecture set the manifest says it must.
    verify_common_repo($COMMON_STAGE) unless $no_verify_repo;
    chmod(0755, $COMMON_STAGE)
      or die "Cannot make $COMMON_STAGE traversable: $!\n";
    replace_common_repository($COMMON_STAGE, $dest);
    print "Published common Genesis repository: $published rpms\n";
}

#--------------------------------------------------------------------------------

=head3 verify_common_repo

    Assert the shared OpenEmbedded Genesis repository carries every package the manifest's [common]
    section requires, at a version satisfying its pin. [common] is not a build target: it describes
    the one repository published beside the per-EL cells, which no [<target>] section covers.

    Arguments:
        $dir - the repository to check (the staging directory, before it is swapped into place)
    Returns:
        1, or dies listing every problem

=cut

#--------------------------------------------------------------------------------
sub verify_common_repo {
    my ($dir) = @_;
    my $manifest = "$repo_root/packages-manifest.conf";
    my %MAN = read_manifest($manifest);
    my %req = %{ $MAN{common} // {} };
    die "FATAL: no [common] section in $manifest -- cannot verify the shared Genesis repository\n"
        if !%req;

    my @names       = sort keys %req;
    my %present     = repo_present_versions($dir, \@names);
    my %present_evr = map { $_ => rpm_evr($dir, $_) } @names;
    my @problems    = verify_repo_packages(\%req, \%present, \%present_evr, \&rpm_vercmp_segment);
    if (@problems) {
        print "  - $_\n" for @problems;
        die "FATAL: shared Genesis repo INCOMPLETE at $dir (" . scalar(@problems) . " problem(s))\n";
    }
    print "[verify-repo] common complete: " . scalar(@names)
        . " packages present + EVR-satisfied in $dir\n";
    return 1;
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
        run_simple("gpg -a --detach-sign --default-key " . sh_quote($gpg_key_name) . ' ' . sh_quote($repomd));
        run_simple("gpg -a --export " . sh_quote($gpg_key_name) . " > " . sh_quote("$repomd.key"));
    }
}

sub write_dep_repo_metadata {
    my ($dir, $rel, $tarch) = @_;
    my $baseurl = "https://xcat.org/files/xcat/repos/yum/devel/xcat-dep/rh$rel/$tarch";
    my $gpgcheck = $gpg_sign ? 1 : 0;
    my $gpgkey_line = $gpg_sign ? "gpgkey=$baseurl/repodata/repomd.xml.key" : "# gpgkey=";
    # repo_gpgcheck=1 makes clients verify the DETACHED repomd.xml signature (repomd.xml.asc) against
    # gpgkey before trusting the metadata -- sign_and_index_repo produces both, so enforce it. Mirrors
    # gpgcheck: off when the repo is unsigned.
    open my $r, '>', "$dir/xcat-dep.repo" or die "Cannot write $dir/xcat-dep.repo: $!\n";
    print {$r} <<"EOF";
[xcat-dep]
name=xCAT 2 dependencies (rh$rel $tarch)
baseurl=$baseurl
enabled=1
gpgcheck=$gpgcheck
repo_gpgcheck=$gpgcheck
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



# Re-run createrepo_c on a repo whose rpm set changed, and (under --gpg-sign) re-sign +
# re-export repomd. Does NOT re-sign the rpms (cross_copy_genesis already did the copied
# one; the rest keep their build-time signatures).
sub reindex_and_sign_repo {
    my ($dir) = @_;
    run_simple(createrepo_c_cmd($dir));
    if ($gpg_sign) {
        local $ENV{GNUPGHOME} = $gpg_home if $gpg_home;
        my $repomd = "$dir/repodata/repomd.xml";
        unlink "$repomd.asc" if -f "$repomd.asc";
        run_simple("gpg -a --detach-sign --default-key " . sh_quote($gpg_key_name) . ' ' . sh_quote($repomd));
        run_simple("gpg -a --export " . sh_quote($gpg_key_name) . " > " . sh_quote("$repomd.key"));
    }
}

sub usage {
    return <<"USAGE";
Usage: $0 [options]

Build xcat-dep RPMs (dep packages, perl packages, and the OS-dependent xCAT-genesis-base),
consolidate binary/source artifacts, run createrepo, and create tarballs. The full xCAT core
is built separately by the xcat-core pipeline, not here.

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
  --finalize-xcat-dep     Post-build cross-arch genesis mode (builds nothing). Requires
                          --x86_64-repo and --ppc64le-repo. For each matching <os>/x86_64 and
                          <os>/ppc64le repo pair, copies the noarch xCAT-genesis-base-ppc64
                          (the ppc64le genesis; xCAT names it -ppc64 via tarch, no big-endian
                          code) into the x86_64 repo and xCAT-genesis-base-x86_64 into the
                          ppc64le repo (dropping any stale foreign-arch genesis), then
                          re-indexes + re-signs. Restores the 2.17 cross-arch genesis
                          (issue #7610). Honors --gpg-sign/--gpg-key-name/--gpg-home. Use alone.
  --x86_64-repo PATH      (finalize) x86_64 repo root holding <os>/x86_64 (e.g. rh9/x86_64)
  --ppc64le-repo PATH     (finalize) ppc64le repo root holding <os>/ppc64le
  --verify-repo PATH      Standalone completeness + signature gate over the per-target repo at PATH
                          (builds nothing). Asserts every package packages-manifest.conf requires for
                          the target is present at a version satisfying its pin AND that the repomd
                          is signed by --gpg-key-name; exits 0 if complete, or lists each MISSING/
                          VERSION/UNSIGNED/WRONGKEY problem and fails. The target is derived from the path
                          (.../rh<N>/<arch> -> alma+epel-<N>-<arch>) unless --target is given; the
                          manifest and gpg key/home come from the usual options. Use alone.
  --no-verify-repo        Suppress the AUTOMATIC post-build completeness+signature gate that runs
                          after each target's repo is finalized (default: verification ON)
  --gpg-sign              Sign RPMs and repomd.xml in every published repository
  --gpg-key-name NAME     GPG key name (default: "xCAT Signing Key")
  --gpg-home PATH         GNUPGHOME for signing (default: system keyring)
  --target NAME           Build only this target (<ID>+epel-<REL>-<ARCH>, or a forcearch
                          config from mock-configs/ such as rocky-10-riscv64-xcat, which
                          cross-builds that arch on this host); default is the host arch
                          across rh8, rh9 and rh10
  --nproc N               Parallel jobs for buildrpms.pl (default: 1)
  --build-timeout SECONDS Wall-clock bound for one build step. Default: none for a native
                          target, and 9000 for a forcearch (qemu-user) target, which runs at
                          roughly a tenth of native speed. 0 removes the bound. On expiry the
                          run prints the step's process tree, each pid's wchan and stack, and
                          a 20-second CPU sample -- a deadlocked build uses no ticks -- then
                          kills the whole process group.
  --parallel-builds N     Max concurrent top-level build steps within one EL target (default: auto)
  --parallel-targets N    Concurrent EL targets (rh8/rh9/rh10). 0/auto = all at once, 1 = serial,
                          N = cap at N. Each target is fully output-isolated (default: 1 = serial)
  --max-parallel N        Global cap on concurrent mock builds across ALL targets, to avoid
                          oversubscribing the host. Split evenly across active targets.
                          0/auto = host nproc (default: auto)
  --run-id ID             Run identifier suffix (default: derived from build timestamp)
  --build-timestamp EPOCH Unix epoch for deterministic builds (default: Gitepoch or git log)
  --skip-build            Skip all build steps and only collect/create repo/tarballs
  --skip-xcat-dep         Skip xcat-dep mockbuild.pl package steps
  --skip-perl             Skip perl package build step
  --install-deps          Install this host's build prerequisites (package manager + the perl
                          modules the script loads), verify each module now loads, then exit.
                          Run once per build host, as root. Use alone.
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
  - Top-level parallel queue includes xcat-dep mockbuild.pl steps, the perl builder,
    and the xCAT-genesis-base build (../xcat-core/buildrpms.pl --package xCAT-genesis-base).
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

    # A forcearch step cross-builds through qemu-user, where a deadlocked build consumes no CPU and
    # never exits. Bound the steps that can run emulated, and report why the build stopped.
    my $timeout = $args{timeout} || 0;
    my $r = run_bounded(cmd => $full_cmd, timeout => $timeout, label => $step, out => \*STDOUT);
    die "Step TIMED OUT after $r->{elapsed}s (budget ${timeout}s): $step\nCommand: $cmd\n"
      . "  See the stall report above" . ($log ? " and $log" : '') . ".\n"
        if $r->{timed_out};
    if ($r->{ec} != 0) {
        my $exit = $r->{ec} == -1 ? 255 : $r->{ec};
        die "Step failed (rc=$exit): $step\nCommand: $cmd\n";
    }
}

# Scrub a single mock buildroot via mock's own --scrub (never rm). mock takes the buildroot lock for
# the scrub, so a concurrent build holding it makes mock BLOCK until release rather than corrupt a live
# chroot (this can never rm a chroot out from under a running build). Failures (already scrubbed or
# config missing) are tolerated -- a cleanup hiccup must never fail the build. Scrubs both the
# build chroot and its per-uniqueext bootstrap chroot (each build step gets its own bootstrap, so
# both must go or /var/lib/mock still leaks). The shared root cache under /var/cache/mock is kept,
# so rebuilds stay fast. $uniqueext is optional (genesis has none).
sub scrub_buildroot {
    my ($cfg, $uniqueext, $log) = @_;
    return if !defined $cfg || $cfg eq '';
    my $ext = (defined $uniqueext && $uniqueext ne '')
        ? ' --uniqueext ' . sh_quote($uniqueext) : '';
    eval {
        run_step(
            step => "Scrub chroot $cfg$ext",
            cmd  => "mock -r " . sh_quote($cfg) . $ext . " --scrub=chroot --scrub=bootstrap",
            log  => $log,
        );
        1;
    } or do {
        warn "WARN: chroot scrub failed (tolerated) for $cfg$ext: $@";
    };
}

sub run_build_steps_parallel {
    my (%args) = @_;
    my $steps = $args{steps} // [];
    my $max_processes = $args{max_processes} // 1;
    return if !@{$steps};

    # Returns the ids of any steps that failed; the caller (build_one_target) enforces
    # zero-tolerance -- ANY failed step fails the whole run, genesis included, with no special-case.
    # We build only packages required for the target (per packages-manifest.conf), so there is no
    # "expected to fail on this arch/el" case left to tolerate. There is likewise no genesis
    # exception: since xcat-core #7696, buildrpms.pl exits 0 iff it produced the genesis rpm, so a
    # non-zero genesis exit is a real failure (the old "tolerate if the rpm is already present"
    # workaround is gone -- a stale artifact must never mask a failed build).
    if ($dry_run || $max_processes <= 1 || @{$steps} == 1) {
        my @failed;
        for my $step (@{$steps}) {
            my $ok = eval { run_step(%{$step}); 1 };
            next if $ok;
            warn "ERROR: build step failed: $step->{step}\n" . ($@ // '');
            push @failed, (defined($step->{id}) && $step->{id} ne '' ? $step->{id} : $step->{step});
        }
        assert_build_progress(scalar(@{$steps}), scalar(@failed));
        return @failed;
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
        warn "ERROR: build step(s) failed:\n  " . join("\n  ", @lines) . "\n";
    }

    assert_build_progress(scalar(@{$steps}), scalar(keys %failed));
    my @failed_ids = sort keys %failed;
    return @failed_ids;
}

# The caller enforces zero tolerance per required package (verify_target_repo). ALL steps
# failing is a different thing: the builder itself is unusable (no mock, a broken chroot, no
# network), this invocation produced nothing, and every package the run would go on to publish
# would come from somewhere other than this build -- say that, instead of naming the missing
# packages later.
sub assert_build_progress {
    my ($attempted, $failures) = @_;
    return unless every_step_failed($attempted, $failures);
    die "FATAL: every build step failed ($failures/$attempted). Check the build logs.\n";
}







# repo_present_versions: thin disk layer for the repo gate. Given a built repo dir and the list of
# required package names, return %present = (name => rpm_version($dir, $name)) for each -- reusing the
# EXISTING rpm_version so genesis's arch-suffixed naming resolves exactly as the in-line manifest pin
# check does. rpm_version returns undef for an absent package, which verify_repo_packages then reports
# as MISSING. Pure disk read; the decision itself lives in verify_repo_packages.
sub repo_present_versions {
    my ($dir, $names) = @_;
    my %present;
    $present{$_} = rpm_version($dir, $_) for @$names;
    return %present;
}

# gpg_key_fingerprint: resolve a gpg key NAME (e.g. "xCAT Signing Key") to its primary-key
# fingerprint in the given keyring, so the expected and observed signing identities are compared in
# the SAME form (a fingerprint). Falls back to the name itself when it cannot be resolved.
sub gpg_key_fingerprint {
    my ($keyname, $home) = @_;
    my $h = ($home ne '') ? ' --homedir ' . sh_quote($home) : '';
    my $out = `gpg$h --with-colons --fingerprint --list-keys ${\ sh_quote($keyname)} 2>/dev/null` // '';
    # Collect the PRIMARY-key fingerprint of every key matching $keyname (the fpr line right after a
    # 'pub' record; subkey fprs follow 'sub' and are ignored). Return undef -- not a guess -- when the
    # key is absent (unresolved) or when MORE THAN ONE key matches the name (ambiguous): the caller
    # then hard-fails SIGKEY rather than comparing against a possibly-wrong key.
    my (@fprs, $want);
    for my $line (split /\n/, $out) {
        if    ($line =~ /^pub:/) { $want = 1; }
        elsif ($line =~ /^sub:/) { $want = 0; }
        elsif ($want && $line =~ /^fpr:+([0-9A-Fa-f]+):/) { push @fprs, $1; $want = 0; }
    }
    my $fingerprint;
    $fingerprint = $fprs[0] if @fprs == 1;
    return $fingerprint;
}

# gpg_key_ids: all acceptable key ids (lowercased) for a signing key NAME -- the primary key id AND
# every subkey id, in both 16-hex (long) and 8-hex (short) forms. rpm header signatures report the
# signing SUBKEY id, so the per-rpm gate accepts any id belonging to the key rather than one exact
# fingerprint. Returns a hashref set (empty if the key can't be listed).
sub gpg_key_ids {
    my ($keyname, $home) = @_;
    my $h = ($home ne '') ? ' --homedir ' . sh_quote($home) : '';
    my $out = `gpg$h --with-colons --list-keys ${\ sh_quote($keyname)} 2>/dev/null` // '';
    my %ids;
    for my $line (split /\n/, $out) {
        my @f = split /:/, $line;
        next unless ($f[0] // '') =~ /^(?:pub|sub)$/ && defined $f[4] && $f[4] ne '';
        my $id = $f[4];
        $ids{ lc $id } = 1;
        $ids{ lc substr($id, -16) } = 1 if length($id) > 16;
        $ids{ lc substr($id, -8)  } = 1 if length($id) > 8;
    }
    return \%ids;
}

# rpm_signer_keyid: the signing key id (lowercased hex) of a built rpm's header signature, or undef
# when the rpm is not signed. Reads the RSA (or DSA) header pgpsig and pulls the "Key ID <hex>" field.
sub rpm_signer_keyid {
    my ($rpm) = @_;
    my $keyid;
    for my $tag (qw(RSAHEADER DSAHEADER)) {
        my $out = `rpm -qp --qf '%{$tag:pgpsig}' ${\ sh_quote($rpm)} 2>/dev/null` // '';
        if ($out =~ /Key ID\s+([0-9A-Fa-f]+)/i) { $keyid = lc($1); last; }
    }
    return $keyid;
}

# rpm_evr: the single distinct EPOCH:VERSION-RELEASE of package $name's binary rpm(s) in $dir (epoch
# defaults to 0 when the header carries none), or undef if none match. Mirrors rpm_version's dedup:
# more than one distinct EVR means a stale artifact was not cleaned before the build (a version pin
# could then pass against the wrong rpm). genesis's x86_64 + ppc64 rpms share one EVR, so a normal
# pair is a single entry.
sub rpm_evr {
    my ($dir, $name) = @_;
    my $glob = ($name eq 'xCAT-genesis-base')
        ? "$dir/xCAT-genesis-base-*.rpm"
        : "$dir/${name}-*.rpm";
    my %evrs;
    for my $f (sort glob($glob)) {
        next if $f =~ /\.src\.rpm$/ || $f =~ /-debug(?:info|source)-/;
        my $n = `rpm -qp --qf '%{name}' ${\ sh_quote($f)} 2>/dev/null`;
        my $match = ($name eq 'xCAT-genesis-base')
            ? ($n =~ /^xCAT-genesis-base-/) : ($n eq $name);
        next unless $match;
        my $evr = `rpm -qp --qf '%{epochnum}:%{version}-%{release}' ${\ sh_quote($f)} 2>/dev/null`;
        chomp $evr;
        $evrs{$evr} = 1 if $evr ne '';
    }
    my $evr;
    return $evr unless %evrs;
    die "Multiple EVRs of $name present in $dir: " . join(', ', sort keys %evrs)
      . " (stale artifact not cleaned before the build)\n" if keys(%evrs) > 1;
    ($evr) = keys %evrs;
    return $evr;
}

# rpm_vercmp_segment: ONE rpmvercmp segment comparison via rpm's own lua binding, returning -1/0/1.
# Used as the injected comparator for MockBuildUtils::evr_cmp so the EVR gate uses rpm's canonical
# version algorithm (epoch/release composition is done in evr_cmp). Long-bracket the args so any
# version char (. _ ~ ^ +) passes through literally; rpm versions never contain the ]==] sequence.
sub rpm_vercmp_segment {
    my ($a, $b) = @_;
    $a = '' unless defined $a;
    $b = '' unless defined $b;
    my $out = `rpm --eval '%{lua:print(rpm.vercmp([==[$a]==],[==[$b]==]))}' 2>/dev/null`;
    chomp $out;
    die "FATAL: rpm.vercmp gave no result for '$a' vs '$b'\n" unless $out =~ /^-?\d+$/;
    return $out <=> 0;
}

# verify_rpms_checksig: cryptographically verify EVERY binary rpm in $dir with `rpmkeys --checksig`
# against an ISOLATED keyring holding only the signing key. This is the RPM-native integrity + origin
# check: it verifies each rpm's header/payload digests AND that the signature is by this key (NOKEY /
# NOT OK => a real failure, since the key IS imported). Returns @problems.
sub verify_rpms_checksig {
    my ($dir, $keyname, $home) = @_;
    my @rpms = grep { !/\.src\.rpm$/ } glob("$dir/*.rpm");
    return () unless @rpms;
    require_command('rpmkeys');
    require_command('gpg');
    my $tmpdb = tempdir('rpmkeys-XXXXXXXX', TMPDIR => 1, CLEANUP => 1);
    my $h = ($home ne '') ? ' --homedir ' . sh_quote($home) : '';
    my $keyfile = "$tmpdb/pubkey.asc";
    system("gpg$h --batch --yes -a --export " . sh_quote($keyname) . ' > ' . sh_quote($keyfile) . ' 2>/dev/null');
    return ("SIGKEY: cannot export public key '$keyname' for rpmkeys --checksig") if !-s $keyfile;
    my $dbopt = '--dbpath ' . sh_quote($tmpdb);
    system("rpmkeys $dbopt --import " . sh_quote($keyfile) . ' >/dev/null 2>&1') == 0
        or return ("SIGKEY: rpmkeys --import of '$keyname' into the temp keyring failed");
    my @problems;
    for my $rpm (@rpms) {
        my $out = `rpmkeys $dbopt --checksig -v ${\ sh_quote($rpm)} 2>&1`;
        push @problems, rpmkeys_checksig_problem(basename($rpm), $? >> 8, $out);
    }
    return @problems;
}

# repomd_observed_signer: run gpg --verify on the detached repomd signature and extract the identity
# of the key that actually signed it, as a primary-key fingerprint (the last field of the VALIDSIG
# status line). Returns '' when the .asc is absent or verification fails (both read as "unsigned").
sub repomd_observed_signer {
    my ($asc, $file, $home) = @_;
    return '' unless -f $asc && -f $file;
    my $h = ($home ne '') ? ' --homedir ' . sh_quote($home) : '';
    my $out = `gpg$h --status-fd=1 --verify ${\ sh_quote($asc)} ${\ sh_quote($file)} 2>/dev/null` // '';
    # An EXPIRED or REVOKED key, or an expired signature, still emits VALIDSIG -- reject those
    # explicitly so a no-longer-trustworthy signature is a problem, not a pass. A fully-good signature
    # emits GOODSIG; the degraded cases emit EXPKEYSIG/REVKEYSIG/EXPSIG instead.
    return '' if $out =~ /^\[GNUPG:\]\s+(?:EXPKEYSIG|REVKEYSIG|EXPSIG)\b/m;
    for my $line (split /\n/, $out) {
        # VALIDSIG <signing-fpr> <dates...> <primary-key-fpr>; the trailing field is the primary fpr.
        if ($line =~ /^\[GNUPG:\]\s+VALIDSIG\s+(.*\S)\s*$/) {
            my @f = split ' ', $1;
            return $f[-1];
        }
    }
    return '';
}

# verify_target_repo: the completeness + signature gate for ONE built per-target repo -- the single
# source of truth for "is this repo shippable?", replacing the old assert_required_deps + in-line
# version-pin loop. It does the IO (manifest parse, rpm_version, gpg --verify) and delegates every
# DECISION to the two PURE helpers: verify_repo_packages (missing/version) and verify_repo_signature
# (unsigned/wrongkey). Both problem lists are merged. Prints a one-line OK, or dies listing every
# problem. Both the automatic post-build gate (deploy_target) and the standalone --verify-repo mode
# call this, so there is exactly one gate implementation.
sub verify_target_repo {
    my ($dir, $tgt, $manifest, $sig_required) = @_;
    $manifest //= "$repo_root/packages-manifest.conf";
    my %MAN = read_manifest($manifest);
    my %req = %{ $MAN{$tgt} // {} };
    die "FATAL: no manifest section for target '$tgt' in $manifest\n" if !%req;
    # The WHOLE manifest, deliberately -- the --skip-* flags are NOT applied here. They say what
    # this INVOCATION built; they never say what the verified repository may be missing. Honouring
    # them let a repo with no xCAT-genesis-base pass whenever the verifying run happened to carry
    # --skip-genesis (PR #62 review). A package an earlier run built is still expected to be here.
    my @names   = sort keys %req;
    my %present     = repo_present_versions($dir, \@names);
    # Full EPOCH:VERSION-RELEASE per package, so a manifest EVR constraint (e.g. genesis-base
    # '>= 2:2.18.0', which %{VERSION}-only matching cannot enforce -- 2.* would accept a pre-2.18
    # genesis) is checked with rpm's own version algorithm (PR #62 review). rpm_vercmp_segment is
    # rpm's rpmvercmp; evr_cmp composes epoch/version/release around it.
    my %present_evr = map { $_ => rpm_evr($dir, $_) } @names;
    my %expected = map { $_ => $req{$_} } @names;
    my @problems = verify_repo_packages(\%expected, \%present, \%present_evr, \&rpm_vercmp_segment);

    # Signature gate: the IO (gpg) lives here; the decision is the pure verify_repo_signature. The
    # pipeline always signs, so a signed repo's repomd MUST be signed by --gpg-key-name. We resolve
    # that key to a fingerprint and extract the fingerprint that actually signed repomd, then compare.
    # Skipped with a printed note only when no gpg key/home is configured (nothing to check against).
    if ($gpg_sign || $gpg_home ne '') {
        require_command('gpg');
        my $repomd  = "$dir/repodata/repomd.xml";
        my $asc     = "$repomd.asc";
        my $exp_fpr = gpg_key_fingerprint($gpg_key_name, $gpg_home);
        # STRICT: the CLI key MUST resolve to exactly one fingerprint so we can confirm it signed the
        # repo. Undef => absent or ambiguous in the keyring -> we cannot verify -> hard fail, never a
        # presence-only pass.
        if (!defined $exp_fpr) {
            push @problems, "SIGKEY: cannot resolve --gpg-key-name '$gpg_key_name' to a single fingerprint (in the $gpg_home keyring?)";
        } else {
            my %exp_sig = ('repomd' => $exp_fpr);
            my %obs_sig = ('repomd' => repomd_observed_signer($asc, $repomd, $gpg_home));
            push @problems, verify_repo_signature(\%exp_sig, \%obs_sig);

            # Per-rpm signature gate: a signed repomd over an unsigned or foreign-signed rpm still
            # makes DNF reject that package at install time, so verify EVERY binary rpm -- not just the
            # metadata -- is signed by this key (rpm reports the signing subkey id; accept any id of
            # the key). Closes the "approves a repo DNF later rejects" gap (PR #62 review #4).
            require_command('rpm');
            # (a) RPM-native crypto verification: rpmkeys --checksig against an isolated keyring
            # holding only this key verifies every rpm's digests AND that the signature is by the key.
            push @problems, verify_rpms_checksig($dir, $gpg_key_name, $gpg_home);
            # (b) Explicit signer-id origin check kept alongside: assert each rpm's header signature
            # key id is one of this key's ids (primary/subkey).
            my $accept = gpg_key_ids($gpg_key_name, $gpg_home);
            if (!%$accept) {
                push @problems, "SIGKEY: cannot list key ids for '$gpg_key_name' to verify per-rpm signatures";
            } else {
                my @rpm_sigs = map { [ basename($_), rpm_signer_keyid($_) ] }
                               grep { !/\.src\.rpm$/ } glob("$dir/*.rpm");
                push @problems, verify_rpm_signatures(\@rpm_sigs, $accept);
            }
        }
    } elsif ($sig_required) {
        # Standalone --verify-repo advertises a signature check; with no keyring we cannot resolve the
        # CLI key or read the signer, so refuse rather than silently pass (which would be a false PASS).
        push @problems, "SIGKEY: --verify-repo requires --gpg-key-name + --gpg-home to check the repomd signature (none configured)";
    } else {
        print "[verify-repo] $tgt: no gpg key/home configured -- skipping repomd signature check\n";
    }

    if (@problems) {
        print "  - $_\n" for @problems;
        die "FATAL: repo INCOMPLETE for $tgt at $dir (" . scalar(@problems) . " problem(s))\n";
    }
    print "[verify-repo] $tgt complete: " . scalar(@names)
        . " required packages present + EVR-satisfied, repomd + every rpm checksig-verified, in $dir\n";
    return 1;
}

# derive_target_from_repo_path: map a deployed per-target repo path .../rh<N>/<arch> to its manifest
# target section name alma+epel-<N>-<arch>. Returns undef when the path lacks that rh<N>/<arch> tail,
# so the standalone --verify-repo mode can require an explicit --target instead.
sub derive_target_from_repo_path {
    my ($dir) = @_;
    my $tgt;
    return $tgt unless defined $dir;
    $tgt = "alma+epel-$1-$2" if $dir =~ m{/rh(\d+)/([^/]+)/*$};
    return $tgt;
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
    # Resolve by CONFIG-FILE existence, not by running `mock --print-root-path`: the latter can fail
    # transiently (bootstrap chroot setup, a concurrent mock holding a lock) and made el10 flakily
    # "resolve" to the long form that has no .cfg. Checking /etc/mock/<cfg>.cfg is deterministic.
    for my $id ($os_id, (exists $short_forms{$os_id} ? ($short_forms{$os_id}) : ())) {
        my $candidate = "${id}+epel-${rel}-${arch}";
        if (-f "/etc/mock/${candidate}.cfg") {
            print "Mock config resolved: $candidate\n" if $id ne $os_id;
            return $candidate;
        }
    }
    my $short = $short_forms{$os_id} // $os_id;
    die "Could not find mock config for ${os_id}+epel-${rel}-${arch} "
      . "(tried /etc/mock/${os_id}+epel-${rel}-${arch}.cfg and /etc/mock/${short}+epel-${rel}-${arch}.cfg)\n";
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

sub slurp_chomp {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot read $path: $!\n";
    my $line = <$fh>;
    close $fh;
    chomp $line if defined $line;
    return $line // '';
}

