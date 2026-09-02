#!/usr/bin/env perl
# sbuild-all.pl -- top-level Ubuntu/Debian dependency-build orchestrator for xcat-dep. The apt/sbuild
# analogue of mockbuild-all.pl, sharing its CLI vocabulary (BuildUtils::standard_options) and its
# manifest-driven, zero-tolerance, fail-hard design. It ABSORBS the three legacy shell scripts:
#   * mk-dep-chroots.sh  -> the "ensure chroots" phase (auto-initializes per-codename sbuild chroots
#                           on first run; idempotent).
#   * build-dep-debs.sh  -> the per-package build phase (drives each <dep>/sbuild.pl in the matching
#                           chroot) + the metadata-preserving genesis phase.
#   * build-apt-repo.sh  -> the apt-repo assembly + signing phase (in Perl, focal supported).
#
# Design (mirrors mockbuild-all.pl + fixes the PR #63 review):
#   1. One host = one arch (dpkg --print-architecture / --arch); a set of codenames (--dists).
#      Each (codename,arch) is a TARGET named "<codename>-<arch>" with a section in debs-manifest.conf.
#   2. Everything is built + validated into a FRESH per-run STAGING tree first. An architecture build
#      run STOPS THERE: publishing is a separate --publish step that takes ONE GLOBAL lock, assembles
#      into a side tree, gates it, and swaps it onto the published path with a single rename(2). The
#      two arches build concurrently on their two hosts, so a per-arch build that also published would
#      interleave wipes of the same pool/dists/Release; and a partial or failed build must never reach
#      the published repo, nor stale debs accumulate in it (concern #1).
#   3. Per-arch package sets come from the manifest: the x86 boot components (syslinux/elilo/xnba,
#      Architecture:all) are built once on amd64 (single producer); ppc64el builds only the genuinely
#      arch-specific compiled deps (concern #3).
#   4. Any required chroot / package / artifact failure, or any version-pin mismatch, fails the whole
#      run non-zero (concern #4).
#   5. The genesis-base deb keeps the maintained Debian packaging semantics -- a native deb is ingested
#      as-is when provided; a converted rpm keeps the maintained control (Depends/Breaks/Replaces) and
#      maintainer scripts (concern #2).
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname basename);
use File::Path qw(make_path remove_tree);
use File::Find;
use File::Copy qw(copy);
use File::Temp qw(tempdir);
use Getopt::Long qw(GetOptions);
use Pod::Usage qw(pod2usage);
use POSIX qw(strftime);
use Fcntl qw(:flock);
use FindBin qw($RealBin);
use lib $RealBin, "$RealBin/lib";
# NOTE: XCAT::GenesisRelease (the shared reader/validator of an OpenEmbedded Genesis package release,
# the same module mockbuild-all.pl uses for the rpm side) is loaded ON DEMAND in the --genesis-release
# block, NOT with `use` here. It pulls in XCAT::BuildUtils, which needs File::Slurper, and the Ubuntu
# build hosts do not all carry that module: a compile-time import would make every apt build depend on
# it, including the builds that never pass --genesis-release. Its subs are therefore called
# fully-qualified.
use BuildUtils qw(sh_quote print_step version_matches required_pkgs read_manifest standard_options
                  install_deps_packages install_deps_command missing_perl_modules
                  verify_repo_packages verify_repo_signature verify_repo_arches
                  parse_packages_index parse_release_architectures resolve_present_names
                  index_has_native_arch control_binary_arch skip_arch_all_on
                  codename_to_version known_codenames supported_arches is_supported_arch
                  chroot_name chroot_sources_list
                  chroot_is_disposable
                  control_field genesis_deb_control
                  deb_field deb_version deb_hash cross_copy_genesis_deb);

my $script_dir = abs_path(dirname(__FILE__));
my $repo_root  = $script_dir;
my $xcat_src   = "$repo_root/../xcat-core";
my $output_root = '';
my $apt_dir    = '';
my $manifest   = '';
my $dists      = '';                 # space/comma list of codenames; default = all known
my $arch       = '';                 # dpkg arch (amd64/ppc64el); default from host
my $mirror     = '';   # default is arch-aware (set after --arch is resolved): amd64 -> archive mirror,
                       # ppc64el -> ubuntu-ports (ppc64el is not on archive.ubuntu.com).
my $run_id     = '';
my $build_timestamp;
my $build_number;
# Per-codename build concurrency ON THIS host/arch. 0 = auto = build every requested codename in
# parallel (each in its own <codename>-<arch>-sbuild chroot). With the Jenkinsfile running the two
# arches on their two hosts in parallel, "all 4 codenames per host" gives 8 concurrent build streams
# (4 per host). N caps it to N; 1 forces serial.
my $parallel_targets = 0;
my ($skip_build, $skip_install, $skip_genesis, $skip_xcat_dep) = (0,0,0,0);
my $install_deps = 0;
my ($skip_createrepo, $skip_tarball) = (0,0);
my $dry_run = 0;
# --publish: run the FINALIZATION phase (assemble + sign + gate + tarball). See the "Publishing"
# comment block below: an architecture build run stages only; publishing is a separate, singly-locked,
# atomic step. undef = not specified -> defaulted from --skip-build.
my $publish;
# --expect-arch: the architecture set the PUBLISHED repo must serve, stated EXPLICITLY (repeatable,
# and each value may be a space/comma list). This is what stops "an entirely missing secondary
# architecture" from reading as "this run simply did not build it" -- see resolve_expect_arches().
my @expect_arch;
# Completeness+signature gate on the PUBLISHED apt index (what apt clients see). $verify_repo_arg set
# (--verify-repo=<apt_dir>) runs the gate STANDALONE against that assembled apt dir and exits (no lock,
# no build). $no_verify_repo suppresses the AUTOMATIC post-publish gate that otherwise runs before the
# assembled tree is swapped into place. Default: automatic gate ON.
my $verify_repo_arg = '';
my $no_verify_repo  = 0;
# Signature verification is ON by default for the standalone gate (--verify-repo): an unsigned or
# wrongly-signed repo is a real defect, and silently skipping the check because no --gpg-home happened
# to be passed is a false PASS. --no-verify-signature is the explicit, deliberate opt-out.
my $no_verify_signature = 0;
my $gpg_sign = 0;
my $gpg_key_id = 'xcat@megware.com';
my $gpg_home = '';
my $genesis_release = '';            # OpenEmbedded Genesis package release to publish alongside
my $genesis_release_checksums;       # its verified SHA256SUMS, read once at startup
# The OpenEmbedded Genesis debs are published ONCE, in a pool of their own that every suite indexes.
# They are Architecture:all and identical for all suites, so a per-suite copy would multiply hundreds
# of megabytes by the number of codenames for no gain.
my $GENESIS_POOL_RELATIVE = 'pool/main/xcat-genesis-openembedded';
my @genesis_debs;                    # native xcat-genesis-base-<arch> deb(s): path or URL (preferred)
my $genesis_rpm = '';                # fallback: native-arch genesis rpm to convert
my $genesis_rpm_ppc = '';            # fallback: cross-arch ppc genesis rpm to convert (amd64 host)
my $require_ppc_genesis = 0;
# File-scoped exclusive run-lock handle. MUST be file-scoped (not a lexical inside a block) so the
# flock lives for the WHOLE process -- a lexical would close the FH and release the lock early.
# Seconds to wait for a concurrent publisher before giving up (--publish-lock-wait). Long by default:
# the other holder is a real publish (assemble + gate + swap), and waiting it out is almost always
# better than failing the run.
my $PUBLISH_LOCK_WAIT = 1800;
my $RUN_LOCK_FH;

# Builder map: manifest binary-package name -> the in-tree package dir that carries <dir>/sbuild.pl
# and the maintained debian/. (goconserver's dir == its binary name.)
my %PKG_DIR = (
    'ipmitool-xcat'  => 'ipmitool',
    'conserver-xcat' => 'conserver',
    'goconserver'    => 'goconserver',
    'syslinux-xcat'  => 'syslinux',
    'grub2-xcat'     => 'grub2-xcat',
    'elilo-xcat'     => 'elilo',
    'xnba-undi'      => 'xnba',
);

# Build the GetOptions map from the shared standard_options() spec (so the flag vocabulary matches
# mockbuild-all.pl), plus the apt/sbuild-specific options this orchestrator adds.
my %DEST = (
    'repo-root'        => \$repo_root,
    'xcat-source'      => \$xcat_src,
    'output'           => \$output_root,   # alias of --output-root
    'output-root'      => \$output_root,
    'manifest'         => \$manifest,
    'target'           => \$dists,         # accept --target "<codename>-<arch>" (mapped below) too
    'skip-build'       => \$skip_build,
    'skip-install'     => \$skip_install,
    'skip-genesis'     => \$skip_genesis,
    'skip-xcat-dep'    => \$skip_xcat_dep,
    'skip-createrepo'  => \$skip_createrepo,
    'skip-tarball'     => \$skip_tarball,
    'run-id'           => \$run_id,
    'build-timestamp'  => \$build_timestamp,
    'build-number'     => \$build_number,
    'gpg-sign'         => \$gpg_sign,
    'gpg-home'         => \$gpg_home,
    'dry-run'          => \$dry_run,
    # apt/sbuild-specific:
    'dists'            => \$dists,
    'arch'             => \$arch,
    'apt-dir'          => \$apt_dir,
    'mirror'           => \$mirror,
    'gpg-key-id'       => \$gpg_key_id,
    'genesis-release'  => \$genesis_release,
    'genesis-deb'      => \@genesis_debs,
    'genesis-rpm'      => \$genesis_rpm,
    'genesis-rpm-ppc'  => \$genesis_rpm_ppc,
    'require-ppc-genesis' => \$require_ppc_genesis,
);
my %spec;   # option-spec-string => destination ref
for my $s (standard_options()) {
    (my $name = $s) =~ s/[=!].*$//;
    next unless exists $DEST{$name};             # only wire the ones this tool uses
    $spec{$s} = $DEST{$name};
}
# apt/sbuild-specific specs
$spec{'dists=s'}               = \$dists;
$spec{'arch=s'}                = \$arch;
$spec{'apt-dir=s'}             = \$apt_dir;
$spec{'mirror=s'}              = \$mirror;
$spec{'gpg-key-id=s'}          = \$gpg_key_id;
$spec{'parallel-targets=i'}    = \$parallel_targets;
$spec{'genesis-deb=s'}         = \@genesis_debs;
$spec{'genesis-rpm=s'}         = \$genesis_rpm;
$spec{'genesis-rpm-ppc=s'}     = \$genesis_rpm_ppc;
$spec{'require-ppc-genesis!'}  = \$require_ppc_genesis;
$spec{'install-deps!'}         = \$install_deps;   # make this host able to run at all, then exit
$spec{'publish!'}              = \$publish;        # run the finalization (assemble+sign+gate+tarball)
$spec{'publish-lock-wait=i'}   = \$PUBLISH_LOCK_WAIT;   # seconds to queue behind another publisher
$spec{'expect-arch=s'}         = \@expect_arch;   # repeatable; each value may be a space/comma list
$spec{'verify-repo=s'}         = \$verify_repo_arg;   # standalone gate: --verify-repo=<apt_dir>
$spec{'no-verify-repo!'}       = \$no_verify_repo;    # suppress the automatic pre-swap gate
$spec{'no-verify-signature!'}  = \$no_verify_signature;   # explicit opt-out of the signature check
$spec{'output=s'}              = \$output_root;   # --output alias
$spec{'help|h'}                = sub { pod2usage(-verbose => 1, -exitval => 0); };
$spec{'man'}                   = sub { pod2usage(-verbose => 2, -exitval => 0); };

GetOptions(%spec) or pod2usage(-verbose => 1, -exitval => 2);

# --install-deps: make THIS host able to run the script, then exit. It comes first because
# everything below assumes the toolchain is present, and a host that lacks it would fail with a
# compile-time error inside a module rather than a message it can act on -- which is how
# File::Slurper being absent on xcat-master-ub aborted a CD run mid-build. The modules are proven by
# LOADING them, not by trusting apt's exit code. Run once per build host, as root.
if ($install_deps) {
    die "FATAL: --install-deps must run as root (uid=$>)\n" if $> != 0;
    my @cmd = install_deps_command();
    print_step('Install build prerequisites');
    print "  " . join(' ', @cmd) . "\n";
    local $ENV{DEBIAN_FRONTEND} = 'noninteractive';
    system('apt-get', 'update', '-q') == 0 or die "FATAL: apt-get update failed\n";
    system(@cmd) == 0 or die "FATAL: " . join(' ', @cmd) . " failed\n";
    my @modules = qw(File::Slurper IPC::Cmd Parallel::ForkManager Digest::MD5);
    my @missing = missing_perl_modules(@modules);
    die "FATAL: still missing after install: " . join(', ', @missing) . "\n" if @missing;
    print "  perl modules present: " . join(', ', @modules) . "\n";
    print "  host is ready\n";
    exit 0;
}

# ---------------------------------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------------------------------
$repo_root = abs_path($repo_root);
$xcat_src  = abs_path($xcat_src) if -d $xcat_src;
$manifest  ||= "$repo_root/debs-manifest.conf";
$arch      ||= `dpkg --print-architecture 2>/dev/null`; chomp $arch;
$arch      ||= 'amd64';
die "FATAL: unsupported --arch '$arch' (@{[join '|', supported_arches()]})\n" unless is_supported_arch($arch);
# Arch-aware chroot bootstrap mirror: only amd64 is on archive.ubuntu.com. Every secondary
# architecture -- ppc64el and riscv64 -- lives on ubuntu-ports. Only defaulted when --mirror was not
# given explicitly.
$mirror    ||= ($arch ne 'amd64') ? 'http://ports.ubuntu.com/ubuntu-ports'
                                  : 'http://br.archive.ubuntu.com/ubuntu';

# --target "<codename>-<arch>" pins a single codename (and cross-checks the arch); otherwise --dists.
my @dist_list;
if ($dists =~ /-(@{[join '|', supported_arches()]})$/) {
    my ($cn, $a) = $dists =~ /^(.+)-(@{[join '|', supported_arches()]})$/;
    die "FATAL: --target arch '$a' != host --arch '$arch'\n" if $a ne $arch;
    @dist_list = ($cn);
} else {
    $dists =~ s/,/ /g;
    @dist_list = grep { length } split /\s+/, $dists;
    @dist_list = known_codenames() unless @dist_list;
}
for my $cn (@dist_list) {
    die "FATAL: unknown codename '$cn' (known: @{[known_codenames()]})\n" unless codename_to_version($cn);
}

@expect_arch = grep { length } map { split /[\s,]+/ } @expect_arch;
for my $a (@expect_arch) {
    die "FATAL: unsupported --expect-arch '$a' (@{[join '|', supported_arches()]})\n" unless is_supported_arch($a);
}

# ---------------------------------------------------------------------------------------------------
# Publishing: an ARCH BUILD RUN STAGES ONLY; publishing is a SEPARATE, SINGLY-LOCKED, ATOMIC step.
#
# The two arches build CONCURRENTLY on their two hosts against the same --apt-dir on the shared tree.
# If both were allowed to assemble, they would wipe and repopulate the same pool/, dists/, Release,
# InRelease and tarball at the same time and interleave into a corrupt (but green) repository. The
# per-arch run lock does NOT prevent that -- it is per-arch by design, so the two arches can build in
# parallel (PR #63 review concern #1).
#
# So the phases are split by ROLE:
#   * a run that BUILDS (no --skip-build) produces staging artifacts and stops there;
#   * publishing happens only when asked for with --publish -- or implicitly on a run that builds
#     nothing (--skip-build), which IS the finalization step -- and it takes ONE GLOBAL publish lock
#     and swaps a fully-assembled, fully-verified tree into place with a single rename().
# --skip-createrepo (the shared CLI's "do not build a repo") always wins and suppresses publishing.
$publish = ($skip_build ? 1 : 0) unless defined $publish;
$publish = 0 if $skip_createrepo;

$output_root ||= "$repo_root/build-output/sbuild-all";
$apt_dir     ||= "$repo_root/repos/apt";
$run_id      ||= strftime("%Y%m%d-%H%M%S", localtime());
$build_timestamp = time() unless defined $build_timestamp;
my $snap_ts = strftime("%Y%m%d%H%M", gmtime($build_timestamp));
$ENV{SOURCE_DATE_EPOCH} = $build_timestamp;   # deterministic mtimes across the whole run

my %MANIFEST = read_manifest($manifest);

# Standalone gate: --verify-repo=<apt_dir> checks an already-assembled apt tree (completeness +
# Release signatures) using THIS script's manifest resolution (--manifest or the default
# debs-manifest.conf), --dists, --expect-arch, and --gpg-key-id/--gpg-home, then exits. It takes NO run
# lock and does NOT build. Dispatched here (after manifest + @dist_list are resolved) so it never trips
# the build-only per-target section check below and never reaches the lock/build phases.
#
# Two deliberate STRICTNESS choices here (PR #63 review concern #3), both of which used to be
# false-PASSes:
#   * The signature IS verified by default. It used to be skipped unless --gpg-home happened to be
#     given, so the common `--verify-repo <dir>` invocation silently checked completeness only.
#     --no-verify-signature is the explicit opt-out.
#   * The expected architecture set is a CLAIM, never "whatever is present": --expect-arch if given,
#     else the arch set each codename's own Release advertises to apt clients. An entirely missing
#     binary-<arch> therefore reads as MISSING-ARCH, not as "that arch was not built this run".
if (length $verify_repo_arg) {
    die "FATAL: --verify-repo apt dir not found: $verify_repo_arg\n" unless -d $verify_repo_arg;
    print_step('Standalone repo verification (no build, no lock)');
    my $adir = abs_path($verify_repo_arg);
    verify_assembled_repo(\%MANIFEST, $adir, \@dist_list,
        resolve_expect_arches('standalone', $adir), !$no_verify_signature);
    exit 0;
}

# --genesis-release <DIR>: publish an OpenEmbedded Genesis package RELEASE alongside the packages this
# run builds. The release is built and signed elsewhere (genesis-openembedded/build + package); this
# script only VERIFIES it and copies the verified bytes into every selected suite. Resolved here --
# after the standalone --verify-repo exit, so a verify-only run is not asked for a release, and before
# any build or publish, so an invalid release fails the run before it touches the tree.
if ($genesis_release ne '') {
    $genesis_release = abs_path($genesis_release)
        or die "FATAL: cannot resolve --genesis-release directory\n";
    die "FATAL: Genesis release directory not found: $genesis_release\n" unless -d $genesis_release;
    my $verifier = "$script_dir/genesis-openembedded/verify-release";
    die "FATAL: Genesis release verifier not found: $verifier\n" unless -x $verifier;
    # Checksum, verify, checksum again -- the same window mockbuild-all.pl closes on the rpm side: the
    # verifier reads the tree it validates, so a release rewritten together with its SHA256SUMS while
    # the verifier runs would satisfy both the verifier and any single pass taken afterwards.
    require XCAT::BuildUtils;
    require XCAT::GenesisRelease;
    my $before = XCAT::GenesisRelease::validated_release_checksums($genesis_release);
    XCAT::BuildUtils::run_command($^X, $verifier, '--complete', '--format', 'deb', $genesis_release);
    my $after = XCAT::GenesisRelease::validated_release_checksums($genesis_release);
    die "FATAL: Genesis release changed during verification\n"
        unless XCAT::BuildUtils::hashes_equal($before, $after);
    $genesis_release_checksums = $before;
    # Every suite's Packages index points into the shared Genesis pool, and publishing a release
    # replaces that pool -- so a run that rebuilt only some suites would leave the others indexing
    # files that no longer exist. Publish a release for all of them or for none.
    my @missing = grep { my $c = $_; !grep { $_ eq $c } @dist_list } known_codenames();
    die "FATAL: --genesis-release updates the shared Genesis pool every suite indexes, so it must\n"
      . "       cover all of them; --dists omits: @missing\n" if @missing;
    print_step('Genesis release');
    print "  $genesis_release (" . scalar(genesis_release_debs()) . " deb packages)\n";
}

for my $cn (@dist_list) {
    my $tgt = "$cn-$arch";
    die "FATAL: no manifest section [$tgt] in $manifest\n" unless $MANIFEST{$tgt};
}

# Staging is arch-scoped: staging/<codename>/<arch>/. Each arch's build wipes ONLY its own
# <codename>/<arch> subdir (fresh per run -> no stale debs, concern #1) while the two arches (built on
# separate hosts into the shared NFS tree) coexist. The assemble phase reads staging/<codename>/*/
# across both arches. A stable path (not per-run-timestamp) lets the amd64 build, the ppc64el build,
# and a later assemble-only run (--skip-build --skip-genesis) all see the same tree.
my $staging = "$output_root/staging";
unless ($dry_run) { make_path($staging); }

# Fail-fast PER-ARCH run lock. Within ONE pipeline run the amd64 and ppc64el stages run CONCURRENTLY
# on their own hosts against the SAME --output-root (different arch subdirs), so a single shared lock
# would wrongly serialize them (or deadlock). Lock per-arch instead: <output_root>/.sbuild-all.<arch>.lock
# is only ever contended by same-arch stages, which all run on the SAME host -- so a plain local flock
# is authoritative (no cross-host NFS lockd needed). This still blocks a SECOND run's same-arch stage
# (cron vs manual) from racing on this arch's staging + the shared apt tree. Not taken under --dry-run.
unless ($dry_run) {
    make_path($output_root);
    my $lockfile = "$output_root/.sbuild-all.$arch.lock";
    open($RUN_LOCK_FH, '>', $lockfile) or die "FATAL: cannot open run lock $lockfile: $!\n";
    unless (flock($RUN_LOCK_FH, LOCK_EX | LOCK_NB)) {
        die "FATAL: another sbuild-all ($arch) is already running (lock held): $lockfile\n";
    }
}

print_step('Configuration');
print "  repo-root:   $repo_root\n";
print "  xcat-source: $xcat_src\n";
print "  arch:        $arch\n";
print "  dists:       @dist_list\n";
print "  manifest:    $manifest\n";
print "  apt-dir:     $apt_dir\n";
print "  staging:     $staging\n";
print "  run-id:      $run_id   snap-ts: $snap_ts   build-number: " . (defined $build_number ? $build_number : '(none)') . "\n";
print "  gpg-sign:    " . ($gpg_sign ? "yes (key $gpg_key_id)" : "no") . "\n";
print "  publish:     " . ($publish
    ? "yes (assemble + sign + gate + swap into $apt_dir, under the global publish lock)"
    : "no (STAGING ONLY -- re-run with --publish, or run the separate finalization step)") . "\n";
print "  expect-arch: " . (@expect_arch ? "@expect_arch" : '(derive from the staged arch set)') . "\n"
    if $publish;
print "  dry-run:     " . ($dry_run ? "yes" : "no") . "\n";

# ---------------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------------
sub run {
    my ($cmd, %o) = @_;
    print "+ $cmd\n";
    return 0 if $dry_run && !$o{always};
    my $rc = system('bash', '-c', $cmd);
    my $ec = $rc == -1 ? -1 : ($rc >> 8);
    die "FATAL: command failed (rc=$ec): $cmd\n" if $ec != 0 && !$o{nofail};
    return $ec;
}

# wipe_tree: remove_tree that FAILS LOUD on real leftovers but TOLERATES NFS silly-rename artifacts.
# A bare remove_tree() carps-and-ignores errors, so stale debs could silently persist -- we must not
# do that. But an ENOTEMPTY here is usually a .nfsXXXX silly-rename: an already-unlinked file that a
# still-open handle (often a peer or aborted build) keeps alive; it is NOT stale build output and
# self-heals when the holder closes. So retry once after a short pause, then die ONLY if a real
# (non-.nfs*) file survives. If the sole survivors are .nfs* artifacts, warn and continue -- assemble
# globs *.deb (never .nfs*), so they cannot leak into the published repo.
sub wipe_tree {
    my (@dirs) = @_;
    remove_tree(@dirs, { safe => 1, error => \my $err });
    return unless $err && @$err;
    sleep 2;   # give a transient silly-rename holder a chance to close
    remove_tree(@dirs, { safe => 1, error => \my $err2 });
    return unless $err2 && @$err2;
    my @real;
    for my $d (@dirs) {
        next unless -d $d;
        find(sub { push @real, $File::Find::name if -f $_ && $_ !~ /^\.nfs[0-9a-f]+$/i }, $d);
    }
    die "FATAL: failed to wipe @dirs -- real files survive: @real\n" if @real;
    warn "WARN: @dirs still holds only NFS silly-rename (.nfs*) leftovers after retry; "
       . "tolerating (they self-heal and are never *.deb)\n";
}

# deb_ver_gt: is Debian version $a strictly greater than $b? Uses dpkg's version comparison (the only
# correct arbiter of Debian version ordering). A missing/empty $b makes any $a "greater".
sub deb_ver_gt {
    my ($a, $b) = @_;
    return 1 if !defined $b || $b eq '';
    return 0 if !defined $a || $a eq '';
    return system('dpkg', '--compare-versions', $a, 'gt', $b) == 0 ? 1 : 0;
}

# ---------------------------------------------------------------------------------------------------
# Phase: ensure chroots (absorbed mk-dep-chroots.sh; first-run auto-init, idempotent)
# ---------------------------------------------------------------------------------------------------
sub have_chroot {
    my ($name) = @_;
    my $out = `schroot -l 2>/dev/null`;
    return $out =~ /^chroot:\Q$name\E$/m ? 1 : 0;
}

# ensure_disposable_chroot($name): make sure a `schroot -c <name> -- ...` session gets a THROWAWAY
# filesystem, so each package builds in a clean environment and one package's build-dependencies can
# never leak into the next (PR #63 review concern #2 -- see BuildUtils::chroot_is_disposable).
# sbuild-createchroot normally writes union-type=overlay; a chroot created before that (or by hand)
# may not have it. Repair the chroot.d entry in place, then re-check and hard-fail if it still is not
# disposable -- silently building in a shared, mutable chroot is exactly what must not happen.
sub ensure_disposable_chroot {
    my ($name) = @_;
    return 1 if $dry_run;
    my $cfg = `schroot --config -c ${\ sh_quote($name) } 2>/dev/null` // '';
    return 1 if chroot_is_disposable($cfg);
    my ($file) = grep { -f $_ && do { local $/; open my $fh, '<', $_ or 0;
                                      my $t = <$fh>; close $fh; $t =~ /^\[\Q$name\E\]/m } }
                 glob('/etc/schroot/chroot.d/*');
    if ($file) {
        print "  chroot $name: NOT disposable -> adding union-type=overlay to $file\n";
        run("sed -i " . sh_quote("/^union-type=/d") . " " . sh_quote($file));
        run("printf '%s\\n' 'union-type=overlay' >> " . sh_quote($file));
        $cfg = `schroot --config -c ${\ sh_quote($name) } 2>/dev/null` // '';
    }
    die "FATAL: chroot $name is not disposable (no union/snapshot session): a build would mutate the\n"
      . "  shared base filesystem and leak build-dependencies into the next package. Add\n"
      . "  'union-type=overlay' to its /etc/schroot/chroot.d/ entry, or delete the chroot so this\n"
      . "  script re-creates it.\n"
        unless chroot_is_disposable($cfg);
    return 1;
}

sub ensure_chroots {
    print_step('Ensure sbuild chroots (auto-init on first run)');
    die "FATAL: chroot init requires root (uid=$>)\n" if $> != 0 && !$dry_run;
    # one-time tooling + sbuild bind-mount of the shared tree
    run("command -v sbuild-createchroot >/dev/null 2>&1 || "
       ."{ DEBIAN_FRONTEND=noninteractive apt-get install -y -q schroot sbuild debootstrap; }");
    my $fstab = '/etc/schroot/sbuild/fstab';
    run("grep -q '/opt/xcat-ci-shared' $fstab 2>/dev/null || "
       ."echo '/opt/xcat-ci-shared  /opt/xcat-ci-shared  none  rw,bind  0  0' >> $fstab", nofail => 1);
    for my $cn (@dist_list) {
        my $name = chroot_name($cn, $arch);
        if (have_chroot($name)) {
            print "  chroot $name: present\n";
            ensure_disposable_chroot($name);
            next;
        }
        print "  chroot $name: MISSING -> creating\n";
        # debootstrap may lack a script for a new codename -> fall back to the generic one.
        run("[ -e /usr/share/debootstrap/scripts/$cn ] || ln -sf gutsy /usr/share/debootstrap/scripts/$cn", nofail => 1);
        my $root = "/srv/chroot/$cn-$arch";
        run("rm -rf $root; rm -f /etc/schroot/chroot.d/$cn-$arch* 2>/dev/null", nofail => 1);
        run("sbuild-createchroot --arch=" . sh_quote($arch) . " " . sh_quote($cn) . " "
           . sh_quote($root) . " " . sh_quote($mirror));
        # main + universe (+ updates/security) so build-deps in universe (quilt, ...) resolve.
        my $sl = chroot_sources_list($mirror, $cn);
        if (!$dry_run) {
            open my $fh, '>', "$root/etc/apt/sources.list" or die "write sources.list: $!\n";
            print $fh $sl; close $fh;
        } else { print "+ write $root/etc/apt/sources.list (main+universe)\n"; }
        run("mkdir -p $root/opt/xcat-ci-shared", nofail => 1);   # bind-mount target for the shared tree
        die "FATAL: chroot $name still absent after create\n" if !$dry_run && !have_chroot($name);
        # Each package MUST build in a throwaway session (see ensure_disposable_chroot).
        ensure_disposable_chroot($name);
        print "  chroot $name: created\n";
    }
}

# ---------------------------------------------------------------------------------------------------
# Phase: build the compiled deps (drives each <dep>/sbuild.pl in the matching chroot)
# ---------------------------------------------------------------------------------------------------
# build_one_codename: build every required (non-genesis) package for ONE codename, serially, each in
# that codename's <codename>-<arch>-sbuild chroot. Returns 0 on success, non-zero if any package
# failed. Called either directly (serial mode) or inside a forked child (parallel mode).
# pkg_skip_on_arch($pkg, $arch): the SINGLE source of truth for "is $pkg an arch:all single-producer
# that must be neither built nor per-arch-validated on $arch?". Reads the package's debian/control and
# delegates the decision to the pure BuildUtils::skip_arch_all_on. Used by BOTH build_one_codename and
# validate_manifest so they can never drift (a package the build skips must not be demanded by the
# validation). Fail-safe: an unreadable/missing control yields no skip (the package is built/validated).
sub pkg_skip_on_arch {
    my ($pkg, $a) = @_;
    my $dir = $PKG_DIR{$pkg} or return 0;
    my $ctl = '';
    if (open my $cf, '<', "$repo_root/$dir/debian/control") { local $/; $ctl = <$cf>; close $cf; }
    return skip_arch_all_on($ctl, $pkg, $a);
}

sub build_one_codename {
    my ($cn) = @_;
    my $tgt = "$cn-$arch";
    my $out = "$staging/$cn/$arch"; wipe_tree($out) if -d $out; make_path($out);
    my @pkgs = grep { $_ ne 'xcat-genesis-base' }
               required_pkgs([sort keys %{$MANIFEST{$tgt}}], $skip_genesis, $skip_xcat_dep);
    print "== [$cn] building: @pkgs -> $out ==\n";
    for my $pkg (@pkgs) {
        my $dir = $PKG_DIR{$pkg}
            or die "FATAL: no builder dir mapped for manifest package '$pkg'\n";
        # arch:all single-producer packages (grub2-xcat/syslinux-xcat/elilo-xcat/xnba-undi) are built
        # ONCE on amd64 -- their source is x86-only (syslinux compiles with nasm/gcc-multilib) -- and,
        # being Architecture:all, are assembled into every arch's Packages index. They stay REQUIRED in
        # the ppc64el manifest so the gate verifies the ppc repo actually carries them, but are NOT
        # rebuilt here. pkg_skip_on_arch() is the SHARED rule -- validate_manifest applies the SAME one
        # so the per-arch validation never demands a package the build deliberately skipped.
        if (pkg_skip_on_arch($pkg, $arch)) {
            print "  [$cn] -> $pkg: arch:all single-producer (built on amd64) -- not rebuilt on $arch\n";
            next;
        }
        my $builder = "$repo_root/$dir/sbuild.pl";
        die "FATAL: missing builder $builder (required for $pkg on $tgt)\n" unless -f $builder;
        my $log = "$out/$pkg.buildlog";
        my $cmd = join(' ',
            'perl', sh_quote($builder),
            '--codename', sh_quote($cn),
            '--arch', sh_quote($arch),
            '--chroot', sh_quote(chroot_name($cn, $arch)),
            '--result-dir', sh_quote($out),
            '--log-dir', sh_quote($out),
            '--build-timestamp', sh_quote($build_timestamp),
            (defined $build_number ? ('--build-number', sh_quote($build_number)) : ()),
            ($skip_install ? ('--skip-install') : ()),
            '>', sh_quote($log), '2>&1',
        );
        print "  [$cn] -> $pkg ($dir/sbuild.pl)\n";
        my $ec = run($cmd, nofail => 1);
        if ($ec != 0) { warn "FATAL: [$cn] $pkg build failed (rc=$ec) -- see $log\n"; return 1; }
    }
    print "== [$cn] done ==\n";
    return 0;
}

# build_deps: build every requested codename ON THIS host. By default all codenames build IN PARALLEL
# (one forked child per codename, each in its own chroot -- so with the two arches running on their two
# hosts, the matrix builds as 8 concurrent streams, 4 per host). --parallel-targets N caps concurrency;
# 1 (or --dry-run) is serial. Fails the run non-zero if ANY codename's build failed.
sub build_deps {
    my $max = $parallel_targets > 0 ? $parallel_targets : scalar(@dist_list);
    $max = 1 if $dry_run;   # keep dry-run output ordered + side-effect-free
    print_step("Build compiled deps ($arch) -- "
        . scalar(@dist_list) . " codename(s), up to $max in parallel");

    if ($max <= 1) {
        my @fail = grep { build_one_codename($_) != 0 } @dist_list;
        die "FATAL: build failed for codename(s): @fail\n" if @fail;
        return;
    }

    my @queue = @dist_list;
    my (%pid2cn, %fail);
    my $running = 0;
    while (@queue || $running) {
        while (@queue && $running < $max) {
            my $cn = shift @queue;
            my $pid = fork();
            die "FATAL: fork failed: $!\n" unless defined $pid;
            if ($pid == 0) { exit(build_one_codename($cn)); }   # child
            $pid2cn{$pid} = $cn; $running++;
        }
        my $pid = wait();
        if ($pid > 0) {
            my $ec = $? >> 8;
            my $cn = delete $pid2cn{$pid} // '?';
            $fail{$cn} = $ec if $ec != 0;
            $running--;
        }
    }
    die "FATAL: build failed for codename(s): "
        . join(', ', map { "$_ (rc=$fail{$_})" } sort keys %fail) . "\n" if %fail;
}

# ---------------------------------------------------------------------------------------------------
# Phase: genesis-base deb (concern #2: preserve maintained packaging; native ingest preferred)
# ---------------------------------------------------------------------------------------------------
# maintained_genesis_control($arch): the maintained xCAT-genesis-builder/debian/control text, with the
# arch-specific package/relationship names remapped to $arch (the tree carries the amd64 control).
sub maintained_genesis_control {
    my ($a) = @_;
    my $f = "$xcat_src/xCAT-genesis-builder/debian/control";
    return undef unless -f $f;
    local $/; open my $fh, '<', $f or return undef; my $t = <$fh>; close $fh;
    # The tree carries the amd64 control; any other arch is the same text with the arch renamed.
    $t =~ s/amd64/$a/g if $a ne 'amd64';
    return $t;
}
# convert_genesis_rpm($rpm, $pkgname, $arch, $outdir): rpm2cpio-extract the noarch genesis rpm and
# repackage as a .deb whose DEBIAN/control PRESERVES the maintained Depends/Breaks/Replaces and whose
# maintainer scripts (postinst/prerm/preinst/postrm) are copied from the maintained debian/ -- so the
# converted deb keeps the install/upgrade semantics the bare 5-field shim dropped (concern #2).
sub convert_genesis_rpm {
    my ($rpm, $pkgname, $a, $outdir) = @_;
    my $work = tempdir(CLEANUP => 1);
    my $get = ($rpm =~ m{^https?://})
        ? "curl -fsSL " . sh_quote($rpm) . " | rpm2cpio"
        : "rpm2cpio " . sh_quote($rpm);
    run("cd $work && $get | cpio -idm --quiet");
    my $ver = `rpm -qp --qf '%{VERSION}-%{RELEASE}' ${\ sh_quote($rpm)} 2>/dev/null`; chomp $ver;
    $ver ||= "2.18.0-snap$snap_ts";
    $ver =~ s/\.(el|fc)\d+.*$//;                       # drop the EL dist tag from the rpm Release
    my $pkgd = "$work/pkg"; make_path("$pkgd/DEBIAN", "$pkgd/opt/xcat");
    run("cp -a $work/opt/xcat/. $pkgd/opt/xcat/ 2>/dev/null || true", nofail => 1);
    my $control = genesis_deb_control(maintained_genesis_control($a), $pkgname, $ver, 'all');
    if (!$dry_run) {
        open my $fh, '>', "$pkgd/DEBIAN/control" or die "write control: $!\n"; print $fh $control; close $fh;
        # preserve maintainer scripts from the maintained packaging (install/upgrade behavior)
        my $mdeb = "$xcat_src/xCAT-genesis-builder/debian";
        for my $s (qw(postinst preinst postrm prerm)) {
            next unless -f "$mdeb/$s";
            copy("$mdeb/$s", "$pkgd/DEBIAN/$s"); chmod 0755, "$pkgd/DEBIAN/$s";
        }
    }
    make_path($outdir);
    run("dpkg-deb --build " . sh_quote($pkgd) . " " . sh_quote("$outdir/${pkgname}_${ver}_all.deb"));
    return "$outdir/${pkgname}_${ver}_all.deb";
}
sub build_genesis {
    print_step('Genesis-base deb (maintained packaging preserved)');
    my $gen = "$output_root/$run_id/genesis"; wipe_tree($gen) if -d $gen; make_path($gen);
    my $native_arch_pkg = "xcat-genesis-base-$arch";
    my $produced_native = 0;
    # 1) prefer an ingested native deb (full metadata + maintainer scripts, no conversion loss)
    for my $g (@genesis_debs) {
        my $base = basename($g);
        my $dst = "$gen/$base";
        if ($g =~ m{^https?://}) { run("curl -fsSL " . sh_quote($g) . " -o " . sh_quote($dst)); }
        else { die "FATAL: --genesis-deb not found: $g\n" unless -f $g || $dry_run; copy($g, $dst) unless $dry_run; }
        print "  ingested native genesis deb: $base\n";
        $produced_native = 1 if $base =~ /^\Q$native_arch_pkg\E_/;
    }
    # 2) else convert the native-arch rpm (metadata-preserving)
    if (!$produced_native) {
        if ($genesis_rpm) {
            print "  converting native-arch genesis rpm -> deb (preserving control + scripts)\n";
            convert_genesis_rpm($genesis_rpm, $native_arch_pkg, $arch, $gen);
        } elsif (!@genesis_debs) {
            die "FATAL: no native genesis for $arch: pass --genesis-deb (preferred) or --genesis-rpm\n";
        }
    }
    # 3) cross-arch ppc genesis on the amd64 host (#7610): convert the ppc rpm if given
    if ($arch eq 'amd64') {
        my $have_ppc = grep { basename($_) =~ /^xcat-genesis-base-ppc64el_/ } glob("$gen/*.deb");
        if (!$have_ppc && $genesis_rpm_ppc) {
            print "  converting cross-arch ppc64el genesis rpm -> deb (#7610)\n";
            convert_genesis_rpm($genesis_rpm_ppc, 'xcat-genesis-base-ppc64el', 'ppc64el', $gen);
            $have_ppc = 1;
        }
        if (!$have_ppc) {
            my $msg = "no ppc64el genesis (pass --genesis-deb/--genesis-rpm-ppc): an amd64 MN cannot "
                    . "netboot ppc nodes (#7610)";
            die "FATAL: $msg\n" if $require_ppc_genesis;
            warn "WARN: $msg\n";
        }
    }
    # stage the arch:all genesis deb(s) into every codename (this host's arch subdir; the cross-arch
    # ppc genesis produced on the amd64 host rides in the amd64 subdir and is picked up by assemble).
    # Use BuildUtils::cross_copy_genesis_deb -- the tested, hash-based, stale-dropping copier -- once
    # per genesis package-arch present in $gen (the native-arch one, plus the cross-converted ppc64el
    # one on the amd64 host). It refreshes a stale same-name deb by content and is idempotent.
    my %gen_arches;
    for my $d (glob("$gen/*.deb")) {
        $gen_arches{$1}++ if basename($d) =~ /^xcat-genesis-base-([a-z0-9]+)_/;
    }
    for my $cn (@dist_list) {
        my $dst = "$staging/$cn/$arch";
        if ($dry_run) {
            print "  [dry-run] would stage genesis (" . join(',', sort keys %gen_arches) . ") -> $cn/$arch\n";
            next;
        }
        make_path($dst);
        for my $ga (sort keys %gen_arches) {
            my $n = cross_copy_genesis_deb($gen, $dst, $ga, undef);
            print "  staged xcat-genesis-base-$ga -> $cn/$arch ($n newly copied)\n";
        }
    }
}

# ---------------------------------------------------------------------------------------------------
# Phase: validate the complete expected set per target (concern #4, zero tolerance)
# ---------------------------------------------------------------------------------------------------
sub validate_manifest {
    print_step('Validate complete expected set + version pins');
    return if $dry_run;
    my @fail;
    for my $cn (@dist_list) {
        my $tgt = "$cn-$arch";
        my $dir = "$staging/$cn/$arch";
        for my $pkg (required_pkgs([sort keys %{$MANIFEST{$tgt}}], $skip_genesis, $skip_xcat_dep)) {
            # arch:all single-producer packages are built on amd64 and are NOT staged for this arch, so
            # do not validate them per-arch here (build_one_codename skips them via the SAME rule). Their
            # presence on this arch is verified later against the PUBLISHED index (verify_assembled_repo).
            next if pkg_skip_on_arch($pkg, $arch);
            my $want = $MANIFEST{$tgt}{$pkg};
            # $arch disambiguates the logical 'xcat-genesis-base': both arch-suffixed genesis debs are
            # staged on the amd64 host (the cross-arch ppc one for #7610) and they carry DIFFERENT
            # revisions, so only this target's arch may be considered.
            my $got  = deb_version($dir, $pkg, $arch);
            if (!defined $got) { push @fail, "[$tgt] MISSING $pkg"; next; }
            push @fail, "[$tgt] $pkg: built $got, manifest pins $want"
                unless version_matches($got, $want);
        }
    }
    die "FATAL: manifest validation failed:\n  " . join("\n  ", @fail) . "\n" if @fail;
    print "  all targets satisfy the manifest (packages present, version pins matched)\n";
}

# ---------------------------------------------------------------------------------------------------
# Phase: manifest-driven completeness + signature GATE on the PUBLISHED apt index (what apt clients
# actually see). This replaces the coarse, pool-global, hard-coded Jenkinsfile check: the manifest is
# the single source of truth and the assertion is made per codename x arch against the PUBLISHED
# binary-<arch>/Packages index (not the staging pool). The pure DECISIONS (verify_repo_packages for
# completeness, verify_repo_signature for the signer) and the index PARSING (parse_packages_index) live
# in BuildUtils.pm and are unit-tested; this disk/IO layer only reads the index, resolves manifest names
# to index keys, and drives gpg for the signature check.
# ---------------------------------------------------------------------------------------------------

# repo_present_from_index($idx, @names): parse the PUBLISHED $idx (a binary-<arch>/Packages file) and
# resolve each required manifest @names against it, returning %present = (reqname => FULL version |
# undef). Name-resolution mirrors deb_version/validate_manifest: try an EXACT index key first (most
# packages -- ipmitool-xcat, goconserver, grub2-xcat, the Architecture:all boot bits keep their plain
# names), else exactly <name>-<arch> for THIS cell's arch (the arch-suffixed xcat-genesis-base ->
# xcat-genesis-base-<arch>, never a different arch's). The version is passed to the comparator WHOLE --
# [epoch:]upstream[-revision] -- because the manifest pins the whole thing, so a stale packaging
# revision or a wrong epoch is caught. (Resolution itself lives in the pure
# BuildUtils::resolve_present_names.)
sub repo_present_from_index {
    my ($idx, $arch, @names) = @_;
    my $text = do { local $/; open my $fh, '<', $idx or die "FATAL: cannot read $idx: $!\n"; <$fh> };
    my $parsed = parse_packages_index($text);
    # Name-resolution (incl. the arch-suffixed genesis, matched to THIS cell's arch -- never a
    # different arch's genesis, which would mask a missing native one) is the pure resolve_present_names.
    return %{ resolve_present_names($parsed, $arch, \@names) };
}

# resolve_expected_key(): the expected signing-key IDENTITY that --gpg-key-id names, resolved (via the
# pipeline's GNUPGHOME) to the primary-key fingerprint so it can be compared against what gpg reports as
# the actual signer. Falls back to the raw --gpg-key-id string when it cannot be resolved to a
# fingerprint (then the gate degrades to presence-only -- see sig_observed_key).
sub resolve_expected_key {
    my $g = $gpg_home ? "GNUPGHOME=" . sh_quote($gpg_home) . " " : '';
    my $out = `${g}gpg --list-keys --with-colons ${\ sh_quote($gpg_key_id)} 2>/dev/null` // '';
    # Collect the PRIMARY-key fingerprint of every matching key (the fpr line right after a 'pub'
    # record; subkey fprs follow 'sub' and are ignored). Return undef -- never the raw id -- when the
    # key is absent (unresolved) or MORE THAN ONE key matches (ambiguous); the caller then hard-fails
    # SIGKEY instead of comparing against a possibly-wrong key.
    my (@fprs, $want);
    for my $line (split /\n/, $out) {
        if    ($line =~ /^pub:/) { $want = 1; }
        elsif ($line =~ /^sub:/) { $want = 0; }
        elsif ($want && $line =~ /^fpr:::::::::([0-9A-Fa-f]+):/) { push @fprs, $1; $want = 0; }
    }
    return @fprs == 1 ? $fprs[0] : undef;
}

# sig_observed_key($adir, $cn): run gpg --verify on the codename's Release signature (clearsigned
# InRelease preferred, detached Release.gpg + Release fallback) and return the PRIMARY-key fingerprint
# that ACTUALLY signed it (the trailing field of the VALIDSIG status line), or undef when unsigned,
# verification FAILS, or the key is expired/revoked. STRICT: no presence-only fallback and no short
# GOODSIG keyid -- the caller compares this fingerprint against the resolved --gpg-key-id fingerprint,
# so undef surfaces as UNSIGNED and a different fingerprint as WRONGKEY.
sub sig_observed_key {
    my ($adir, $cn) = @_;
    my $g = $gpg_home ? "GNUPGHOME=" . sh_quote($gpg_home) . " " : '';
    my $inrel  = "$adir/dists/$cn/InRelease";
    my $rel    = "$adir/dists/$cn/Release";
    my $relgpg = "$adir/dists/$cn/Release.gpg";
    my $cmd;
    if (-f $inrel) {
        $cmd = "${g}gpg --status-fd=1 --verify " . sh_quote($inrel) . " 2>/dev/null";
    } elsif (-f $relgpg && -f $rel) {
        $cmd = "${g}gpg --status-fd=1 --verify " . sh_quote($relgpg) . " " . sh_quote($rel) . " 2>/dev/null";
    } else {
        return undef;   # no signature file at all -> UNSIGNED
    }
    my $out = `$cmd` // '';
    return undef if ($? >> 8) != 0;   # gpg --verify FAILED (BADSIG/NO_PUBKEY) -> unsigned/bad
    # An EXPIRED or REVOKED key, or an expired signature, still emits VALIDSIG (and gpg may exit 0),
    # so reject those explicitly -- a no-longer-trustworthy signature must be a problem, not a pass.
    return undef if $out =~ /^\[GNUPG:\]\s+(?:EXPKEYSIG|REVKEYSIG|EXPSIG)\b/m;
    my $obs_fpr = '';
    for my $line (split /\n/, $out) {
        if ($line =~ /^\[GNUPG:\]\s+VALIDSIG\s+(.*)$/) {
            my @f = split /\s+/, $1;
            $obs_fpr = $f[-1];        # last field = primary key fingerprint (full 40-hex)
            last;
        }
    }
    # STRICT: return the signer's primary-key fingerprint, or undef if we could not extract one. No
    # presence-only fallback -- the caller compares this against the resolved --gpg-key-id fingerprint,
    # so the gate always confirms the repo was signed by EXACTLY the CLI key (undef -> UNSIGNED, a
    # different fingerprint -> WRONGKEY). We never return a short GOODSIG keyid (it could not equal the
    # 40-hex expected fpr) nor the expected value itself (which would rubber-stamp a pass).
    return $obs_fpr ne '' ? $obs_fpr : undef;
}

# release_claimed_arches($adir, $cn): the architecture set dists/<cn>/Release ADVERTISES to apt
# clients ("Architectures:"), or the empty list when there is no Release. The repo's own claim, which
# is what the standalone gate holds it to when no --expect-arch is given.
sub release_claimed_arches {
    my ($adir, $cn) = @_;
    my $rel = "$adir/dists/$cn/Release";
    $rel = "$adir/dists/$cn/InRelease" unless -f $rel;
    return () unless -f $rel;
    open my $fh, '<', $rel or return ();
    local $/; my $t = <$fh>; close $fh;
    return parse_release_architectures($t);
}

# resolve_expect_arches($mode, $adir): the architecture set the published repo is REQUIRED to serve.
#
# This is the crux of PR #63 review concern #3. It must be a CLAIM someone made, never an inference
# from "which binary-<arch> directories happen to be populated" -- because inferring it from presence
# is precisely what turns an entirely missing secondary architecture into a silent PASS ("ppc64el is
# absent, so this run must not have built ppc64el"). Sources, in order:
#   1. --expect-arch          -- explicit; always wins. This is what the CD pipeline passes.
#   2. mode 'publish'         -- the arch set actually STAGED under staging/<cn>/<arch> (every one of
#                                which passed validate_manifest), unioned with this host's --arch.
#                                That is the set this publish intends to ship.
#   3. mode 'standalone'      -- the union of what each codename's own Release advertises, unioned
#                                with --arch. Verifying a repo against its published claim is what
#                                catches "Release says amd64 ppc64el, but binary-ppc64el is missing".
sub resolve_expect_arches {
    my ($mode, $adir) = @_;
    if (@expect_arch) {
        my %u = map { $_ => 1 } @expect_arch;
        return [sort keys %u];
    }
    my %u = ($arch => 1);
    if ($mode eq 'publish') {
        for my $cn (@dist_list) {
            for my $d (glob("$staging/$cn/*")) {
                next unless -d $d;
                my $a = basename($d);
                $u{$a} = 1 if $a =~ /^(amd64|ppc64el)$/;
            }
        }
        print "  expected arches (from the staged set): " . join(' ', sort keys %u) . "\n";
    } else {
        for my $cn (@dist_list) { $u{$_} = 1 for release_claimed_arches($adir, $cn); }
        print "  expected arches (from each codename's Release 'Architectures:'): "
            . join(' ', sort keys %u) . "\n";
    }
    return [sort keys %u];
}

# verify_assembled_repo($manifest_href, $apt_dir, $dists_aref, $expect_arches_aref, $sig_required):
# the ONE completeness+signature gate, shared by the automatic pre-swap run (inside publish_repo) and
# the standalone --verify-repo mode. It is the IO layer: it PARSES the repository (parse_packages_index
# of each published binary-<arch>/Packages -> %present; gpg --verify of each dists/<cn>/InRelease ->
# %observed signer), PARSES the manifest (-> %expected pkg pins per cell) and resolves the GPG key
# (--gpg-key-id -> expected signer), then delegates the DECISION to the pure verify_repo_arches (the
# arch set), verify_repo_packages (per codename x arch) and verify_repo_signature (per codename).
# Package problems are [<cn>/<arch>]-prefixed; the pure arch/signature problems already carry their
# unit. Any problem dies non-zero.
#
# $expect_arches_aref is the EXPECTED arch set from resolve_expect_arches -- required and non-empty.
# Every expected arch is checked (a missing index is MISSING-INDEX, an index with no native package is
# MISSING-ARCH), and any arch that published natives WITHOUT being expected is UNEXPECTED-ARCH. The
# gate never derives what it should demand from what it happens to find.
sub verify_assembled_repo {
    my ($man, $adir, $dists, $arches, $sig_required) = @_;
    my @all;
    my @expected = sort @{ $arches || [] };
    die "FATAL: verify_assembled_repo: no expected architecture set (pass --expect-arch)\n"
        unless @expected;
    # $sig_required: whether a valid signature is DEMANDED. The pre-swap auto-run passes $gpg_sign --
    # a repo assembled WITHOUT --gpg-sign is intentionally unsigned, so don't demand a signature and
    # false-fail. Standalone --verify-repo passes !--no-verify-signature, i.e. ON unless opted out.
    my $expected_key = $sig_required ? resolve_expected_key() : undef;
    my $expected_is_fpr = defined($expected_key) ? 1 : 0;
    print "  apt-dir: $adir\n";
    print "  expected arches: " . join(' ', @expected) . "\n";
    print "  signature check: " . ($sig_required
        ? "on (expected key " . ($expected_key // $gpg_key_id) . ($expected_is_fpr ? '' : ' [UNRESOLVED -> hard fail]') . ")"
        : "OFF (" . ($no_verify_signature ? '--no-verify-signature'
                                          : 'repo assembled without --gpg-sign') . ")") . "\n";
    # STRICT: if signing is expected but --gpg-key-id does not resolve to a fingerprint (not in the
    # keyring), we CANNOT confirm the signer -- that is a hard failure, never a presence-only pass.
    push @all, "SIGKEY: cannot resolve --gpg-key-id '$gpg_key_id' to a fingerprint (in the "
             . ($gpg_home ne '' ? $gpg_home : 'ambient GNUPGHOME') . " keyring?)"
        if $sig_required && !$expected_is_fpr;

    my (%exp_sig, %obs_sig);
    for my $cn (@$dists) {
        # Which arches carry NATIVE debs here (a Packages stanza with Architecture == that arch), as
        # opposed to only the Architecture:all debs (grub2-xcat, genesis) that ride into EVERY
        # binary-<arch> index. Collected for the EXPECTED set plus the other supported arches, so the
        # pure verify_repo_arches can report both directions: expected-but-absent and present-but-
        # unexpected (a stale arch left behind in the tree).
        my %native;
        for my $a (do { my %s = map { $_ => 1 } (@expected, qw(amd64 ppc64el)); sort keys %s }) {
            my $idx = "$adir/dists/$cn/main/binary-$a/Packages";
            $native{$a} = 0;
            next unless -f $idx;
            open my $ifh, '<', $idx or next;
            local $/; my $body = <$ifh>; close $ifh;
            $native{$a} = index_has_native_arch($body, $a) ? 1 : 0;
        }
        push @all, map { "[$cn] $_" } verify_repo_arches(\@expected, \%native);

        # completeness: manifest (source of truth) vs the PUBLISHED index, per codename x arch.
        for my $a (@expected) {
            my $tgt = "$cn-$a";
            my $req = $man->{$tgt};
            # A cell we are REQUIRED to serve but have no manifest section for cannot be verified at
            # all -- that is a configuration error, not a reason to pass it. (It used to be silently
            # skipped, which made an unlisted target a free PASS.)
            unless ($req && %$req) {
                push @all, "[$cn/$a] NO-MANIFEST section [$tgt] in $manifest, but $a is expected";
                next;
            }
            # The WHOLE manifest, deliberately -- no required_pkgs() skip filtering here. The
            # --skip-* flags say what this INVOCATION built, and the documented publish-only run
            # passes --skip-genesis; honouring them here would let the run that publishes decide
            # what the published repository is allowed to be missing, and a repo with no Genesis
            # package would pass its own publication gate. Packages this invocation did not build
            # are still expected in the tree (seeded from the previously published repo).
            my @names = sort keys %$req;
            my $idx = "$adir/dists/$cn/main/binary-$a/Packages";
            unless (-f $idx) {
                push @all, "[$cn/$a] MISSING-INDEX (no $idx)";
                next;
            }
            my %present = repo_present_from_index($idx, $a, @names);
            my %pins = map { $_ => $req->{$_} } @names;
            push @all, map { "[$cn/$a] $_" } verify_repo_packages(\%pins, \%present);
        }
        # signature IO: record the expected + observed signer for this codename (compared in bulk below).
        # Only when the expected key resolved to a fingerprint (else the SIGKEY hard-fail above stands).
        if ($sig_required && $expected_is_fpr) {
            $exp_sig{$cn} = $expected_key;
            $obs_sig{$cn} = sig_observed_key($adir, $cn);
        }
    }
    push @all, verify_repo_signature(\%exp_sig, \%obs_sig) if $sig_required && $expected_is_fpr;

    if (@all) {
        print "$_\n" for @all;
        die "FATAL: apt repo INCOMPLETE (" . scalar(@all) . " problem(s))\n";
    }
    print "[verify-repo] complete: all required packages present + version-pinned"
        . ($sig_required ? " + Release signatures valid (key $expected_key)" : "")
        . " for [" . join(' ', @$dists) . "] x {" . join(',', @expected) . "}\n";
    return;
}

# ---------------------------------------------------------------------------------------------------
# Phase: PUBLISH -- the single, locked, atomic finalization (absorbed build-apt-repo.sh).
#
# Concern #1 of the PR #63 review: the amd64 and ppc64el build runs execute CONCURRENTLY on their two
# hosts against the same --apt-dir. Two publishers there would interleave their wipes and rewrites of
# pool/, dists/, Release, InRelease and the tarball. The fix has three parts:
#
#   1. Build runs do not publish at all (see the $publish decision above): they only fill staging.
#      Publishing is a separate step, run once, after every arch has staged and validated.
#   2. That step takes ONE GLOBAL publish lock -- not the per-arch build lock -- so even a mistaken
#      second publisher (cron racing a manual run on the same host) serializes instead of interleaving.
#   3. It assembles into a SIDE TREE and swaps it in with rename(2) once the gate has passed. A reader
#      (deploy.sh's rsync, an apt client on a served tree) therefore only ever sees the previous
#      complete repo or the new complete repo -- never a half-wiped pool or an index that does not
#      match its Release. A failed gate leaves the published tree untouched.
#
# The lock file lives on the shared tree; within a host flock() is authoritative, which is what
# matters, since the pipeline's finalization step always runs on one host (the amd64 Ubuntu builder).
# ---------------------------------------------------------------------------------------------------
my $PUBLISH_LOCK_FH;

sub acquire_publish_lock {
    make_path($output_root);
    my $lockfile = "$output_root/.sbuild-all.publish.lock";
    open($PUBLISH_LOCK_FH, '>', $lockfile) or die "FATAL: cannot open publish lock $lockfile: $!\n";
    unless (flock($PUBLISH_LOCK_FH, LOCK_EX | LOCK_NB)) {
        print "  publish lock is held by another run -- waiting up to ${PUBLISH_LOCK_WAIT}s: $lockfile\n";
        local $SIG{ALRM} = sub {
            die "FATAL: timed out after ${PUBLISH_LOCK_WAIT}s waiting for the publish lock $lockfile\n";
        };
        alarm($PUBLISH_LOCK_WAIT);
        my $ok = flock($PUBLISH_LOCK_FH, LOCK_EX);
        alarm(0);
        die "FATAL: cannot take the publish lock $lockfile: $!\n" unless $ok;
    }
    print "  publish lock acquired: $lockfile\n";
    return $lockfile;
}

# assemble_into($dir, $expect_arches): (re)assemble every --dists codename inside $dir from the
# validated staging tree, index it per expected binary-<arch>, write + sign Release. $dir is the SIDE
# tree, never the published one.
# ---------------------------------------------------------------------------------------------------
# OpenEmbedded Genesis release (--genesis-release)
# ---------------------------------------------------------------------------------------------------
# genesis_release_debs: the release-relative paths of the release's deb packages, taken from the
# VERIFIED checksum manifest rather than from a directory listing -- a file that is not in SHA256SUMS
# is not part of the release and must never reach the pool.
sub genesis_release_debs {
    return sort grep { m{^deb/xcat-genesis-openembedded-[^/]+\.deb\z} }
        keys %{ $genesis_release_checksums // {} };
}

# install_genesis_release_debs($dir): (re)build the SHARED Genesis pool inside the side tree from
# the verified release, verifying each copy against the release checksums. Called once per publish,
# with the publish lock held and before any apt-ftparchive run, so the bytes indexed and signed are
# exactly the bytes verified here. Wiping first is what retires packages an earlier release left.
#
# A plain copy, never link(): the pool file must be its own inode. A hard link would leave the
# published package and the verified release sharing one, where a write through either path silently
# changes what the other holds.
sub install_genesis_release_debs {
    my ($dir) = @_;
    my @files = genesis_release_debs();
    die "FATAL: Genesis release has no deb packages\n" unless @files;
    my $pool = "$dir/$GENESIS_POOL_RELATIVE";
    wipe_tree($pool);
    make_path($pool);
    for my $relative (@files) {
        my $base = basename($relative);
        copy("$genesis_release/$relative", "$pool/$base")
            or die "FATAL: cannot install Genesis release package $relative -> $pool: $!\n";
        chmod(0644, "$pool/$base")
            or die "FATAL: cannot set mode on $pool/$base: $!\n";
        XCAT::GenesisRelease::verify_release_file($genesis_release_checksums, $relative, "$pool/$base");
    }
    verify_shared_pool($pool);
    return scalar(@files);
}

# verify_shared_pool($pool): assert the shared Genesis pool carries every package the manifest's
# [shared] section requires, at a version satisfying its pin. [shared] is not a build target: it
# describes the one pool every suite indexes, which no [<codename>-<arch>] section covers. Run on
# the SIDE TREE, before it is swapped into place, so an incomplete pool is never published.
# Completeness only -- the release checksums cover the bytes.
sub verify_shared_pool {
    my ($pool) = @_;
    my %req = %{ $MANIFEST{shared} // {} };
    die "FATAL: no [shared] section in $manifest -- cannot verify the shared Genesis pool\n"
        if !%req;
    my @names = sort keys %req;
    my %present = map { $_ => deb_version($pool, $_) } @names;
    my @problems = verify_repo_packages(\%req, \%present);
    if (@problems) {
        print "  - $_\n" for @problems;
        die "FATAL: shared Genesis pool INCOMPLETE at $pool (" . scalar(@problems) . " problem(s))\n";
    }
    print "  [verify-repo] shared pool complete: " . scalar(@names) . " packages present\n";
    return 1;
}

sub assemble_into {
    my ($dir, $expect) = @_;
    if ($genesis_release ne '') {
        my $n = install_genesis_release_debs($dir);
        print "  published + verified $n Genesis release package(s) into $GENESIS_POOL_RELATIVE\n";
    }
    for my $cn (@dist_list) {
        my $ver = codename_to_version($cn);
        my $pool = "$dir/pool/main/$cn";
        # wipe ONLY this codename's pool+dists in the side tree, then repopulate from validated
        # staging (all arches: staging/<cn>/{amd64,ppc64el}/*.deb). Wiping first is what removes stale
        # debs from a prior run so the published repo never carries a mixture.
        wipe_tree($pool, "$dir/dists/$cn", "$dir/$ver");
        make_path($pool, "$dir/$ver");
        # Collect this codename's staged debs across both arches, deduping on binary package
        # NAME+ARCH: if two files resolve to the same package+arch (e.g. a native ppc genesis and
        # an amd64-host cross-converted one both claiming xcat-genesis-base-ppc64el/all) only ONE
        # may reach the pool. Keep the highest version and warn naming both -- a safety net that
        # holds regardless of the --skip-genesis single-producer contract.
        my %best;   # "name|arch" => { file => path, ver => version }
        for my $deb (glob("$staging/$cn/*/*.deb")) {
            # OpenEmbedded Genesis debs never belong to a suite pool -- they are published once
            # into the shared pool. Drop anything staged under that name, so a leftover from an
            # earlier run cannot be published as if it had come from a verified release.
            next if basename($deb) =~ /^xcat-genesis-openembedded-/;
            my $name  = deb_field($deb, 'Package');
            my $darch = deb_field($deb, 'Architecture');
            my $dver  = deb_field($deb, 'Version');
            my $key   = "$name|$darch";
            if (my $cur = $best{$key}) {
                my $new_wins = deb_ver_gt($dver, $cur->{ver});
                my ($win, $lose) = $new_wins ? ($deb, $cur->{file}) : ($cur->{file}, $deb);
                warn "WARN: duplicate binary $name/$darch in staging for $cn -- keeping "
                   . basename($win) . ", dropping " . basename($lose) . "\n";
                $best{$key} = { file => $deb, ver => $dver } if $new_wins;
                next;
            }
            $best{$key} = { file => $deb, ver => $dver };
        }
        for my $key (sort keys %best) {
            my $deb = $best{$key}{file};
            my $b = basename($deb);
            link($deb, "$pool/$b") or copy($deb, "$pool/$b");
            copy($deb, "$dir/$ver/$b");
            # Served by a web server running as somebody else -- do not inherit the builder umask.
            chmod(0644, "$pool/$b", "$dir/$ver/$b");
        }
        # Packages index per EXPECTED binary-<arch>: an arch's index carries that arch's debs + all
        # Architecture:all. Only the expected arches get an index -- writing a binary-ppc64el index
        # containing nothing but the Architecture:all debs would advertise a ppc64el repo that cannot
        # actually satisfy a ppc64el client (and would then be mistaken for "ppc was published").
        # This suite's own pool PLUS the shared Genesis pool: one Packages index, two sources, each
        # deb's Filename staying relative to the repository root so clients fetch it where it is.
        my $all = `cd ${\ sh_quote($dir)} && apt-ftparchive packages pool/main/$cn`;
        $all .= `cd ${\ sh_quote($dir)} && apt-ftparchive packages $GENESIS_POOL_RELATIVE`
            if -d "$dir/$GENESIS_POOL_RELATIVE";
        for my $a (@$expect) {
            my $bindir = "$dir/dists/$cn/main/binary-$a";
            make_path($bindir);
            open my $pf, '>', "$bindir/Packages" or die "write Packages: $!\n";
            for my $para (split /\n\n+/, $all) {
                next unless $para =~ /\S/;
                my ($pa) = $para =~ /^Architecture:\s*(\S+)/m;
                print $pf "$para\n\n" if defined $pa && ($pa eq $a || $pa eq 'all');
            }
            close $pf;
            run("gzip -9 -kf -n " . sh_quote("$bindir/Packages"));
        }
        # Release advertises EXACTLY the expected arch set -- the same claim the gate then holds the
        # tree to, and the claim a later standalone --verify-repo falls back on.
        my @rel = ('apt-ftparchive',
            '-o', 'APT::FTPArchive::Release::Origin=xCAT',
            '-o', 'APT::FTPArchive::Release::Label=xcat-dep',
            '-o', "APT::FTPArchive::Release::Suite=$cn",
            '-o', "APT::FTPArchive::Release::Codename=$cn",
            '-o', 'APT::FTPArchive::Release::Architectures=' . join(' ', @$expect),
            '-o', 'APT::FTPArchive::Release::Components=main',
            '-o', "APT::FTPArchive::Release::Description=xCAT dependency packages for $ver",
            'release', "$dir/dists/$cn/");
        run(join(' ', map { sh_quote($_) } @rel) . " > " . sh_quote("$dir/dists/$cn/Release"));
        my $det = strftime("%a, %d %b %Y %H:%M:%S +0000", gmtime($build_timestamp));
        run("sed -i " . sh_quote("s/^Date: .*/Date: $det/") . " " . sh_quote("$dir/dists/$cn/Release"), nofail => 1);
        if ($gpg_sign) {
            my $g = $gpg_home ? "GNUPGHOME=" . sh_quote($gpg_home) . " " : '';
            my $rel = "$dir/dists/$cn/Release";
            run("${g}gpg --default-key " . sh_quote($gpg_key_id) . " --batch --yes --armor --detach-sign -o "
               . sh_quote("$rel.gpg") . " " . sh_quote($rel));
            run("${g}gpg --default-key " . sh_quote($gpg_key_id) . " --batch --yes --armor --clearsign -o "
               . sh_quote("$dir/dists/$cn/InRelease") . " " . sh_quote($rel));
        }
        print "  assembled + " . ($gpg_sign ? 'signed' : 'UNSIGNED') . " apt tree for $cn ("
            . join(' ', @$expect) . ")\n";
    }
    # export the signing pubkey for clients
    if ($gpg_sign) {
        my $g = $gpg_home ? "GNUPGHOME=" . sh_quote($gpg_home) . " " : '';
        my $keysrc = "$repo_root/repomd.xml.key";
        if (-f $keysrc) { copy($keysrc, "$dir/xcat-dep.asc"); }
        else { run("${g}gpg --armor --export " . sh_quote($gpg_key_id) . " > " . sh_quote("$dir/xcat-dep.asc"), nofail => 1); }
        chmod(0644, "$dir/xcat-dep.asc") if -f "$dir/xcat-dep.asc";
    }
}

# swap_into_place($tmp, $target): publish $tmp AS $target with rename(2) -- the only moment the
# published repo changes, and it changes all at once. Both paths are siblings, so both renames are
# same-filesystem and atomic. If the second rename fails the previous tree is put straight back.
sub swap_into_place {
    my ($tmp, $target) = @_;
    my $old = "$target.old-$run_id.$$";
    wipe_tree($old) if -d $old;
    my $had_old = 0;
    if (-d $target) {
        rename($target, $old) or die "FATAL: cannot move the published repo aside ($target -> $old): $!\n";
        $had_old = 1;
    }
    unless (rename($tmp, $target)) {
        my $err = $!;
        rename($old, $target) if $had_old;   # put the previous repo back; nothing was lost
        die "FATAL: cannot swap the assembled repo into place ($tmp -> $target): $err\n";
    }
    print "  published atomically: $target\n";
    wipe_tree($old) if $had_old;
}

sub publish_repo {
    unless ($publish) {
        print_step('Publish SKIPPED -- this run produced STAGING ONLY');
        print "  staged under $staging (arch $arch)\n";
        print "  the apt repo at $apt_dir is untouched: publishing is a separate, singly-locked,\n"
            . "  atomic step so two concurrent arch builds can never rewrite it at the same time.\n"
            . "  Finalize with:  sbuild-all.pl --skip-build --skip-genesis --publish "
            . "--expect-arch \"<arches>\" --gpg-sign ...\n";
        return;
    }
    print_step('Publish apt repo (locked, assembled aside, swapped in atomically)');
    my $expect = resolve_expect_arches('publish', $apt_dir);
    if ($dry_run) {
        print "  [dry-run] would lock $output_root/.sbuild-all.publish.lock, assemble @dist_list for "
            . join(' ', @$expect) . " into $apt_dir.publish-<run-id>.<pid>, gate it, then rename it "
            . "onto $apt_dir\n";
        return;
    }
    run("command -v apt-ftparchive >/dev/null 2>&1 || { echo 'need apt-utils' >&2; exit 1; }", always => 1);
    warn "WARN: publishing an UNSIGNED apt repo (no --gpg-sign) -- apt clients will reject it\n"
        unless $gpg_sign;
    acquire_publish_lock();

    # Side-tree name carries the pid too: --run-id has second granularity, and two runs that start in
    # the same second must not pick the same scratch path.
    my $tmp = "$apt_dir.publish-$run_id.$$";
    wipe_tree($tmp) if -e $tmp;
    make_path(dirname($apt_dir), $tmp);
    # Seed the side tree from the currently published one so codenames OUTSIDE --dists survive the
    # swap (a --dists noble run must not drop focal/jammy/resolute). A hardlink copy is cheap and
    # safe here: assemble_into only unlinks and re-creates files, it never writes through a link.
    if (-d $apt_dir) {
        run("cp -al " . sh_quote("$apt_dir/.") . " " . sh_quote("$tmp/") . " 2>/dev/null || "
          . "cp -a " . sh_quote("$apt_dir/.") . " " . sh_quote("$tmp/"));
    }

    # Assemble, then GATE BEFORE PUBLISH: the completeness + signature check runs against the side
    # tree, so an incomplete or mis-signed repo is never swapped in -- the previously published tree
    # stays exactly as it was. The gate is suppressed with --no-verify-repo (iteration/debug).
    # Anything that fails here takes the side tree with it and leaves $apt_dir untouched.
    eval {
        assemble_into($tmp, $expect);
        unless ($no_verify_repo) {
            print_step('Verify assembled apt repo (completeness + signature gate, before publishing)');
            # Require a valid signature iff we actually signed (--gpg-sign); a repo assembled without
            # it is intentionally unsigned and must not false-fail.
            verify_assembled_repo(\%MANIFEST, $tmp, \@dist_list, $expect, $gpg_sign);
        }
        1;
    } or do {
        my $err = $@ || "unknown error\n";
        print "  NOT publishing: $apt_dir keeps its previous contents\n";
        wipe_tree($tmp) if -d $tmp;
        die $err;
    };

    swap_into_place($tmp, $apt_dir);
    make_tarball();
}

# ---------------------------------------------------------------------------------------------------
# Phase: tarball (optional) -- part of PUBLISH, under the same lock. A per-arch build run must not tar
# the shared apt tree: with both arches running it would archive a tree the other arch is rewriting.
# ---------------------------------------------------------------------------------------------------
sub make_tarball {
    return if $skip_tarball;
    print_step('Tarball');
    my $tb = "$output_root/$run_id/xcat-dep-$arch-$run_id.tar.gz";
    make_path(dirname($tb));   # the run dir may not exist yet (e.g. a publish-only run)
    run("tar -C " . sh_quote(dirname($apt_dir)) . " -czf " . sh_quote($tb) . " " . sh_quote(basename($apt_dir)), nofail => 1);
    print "  $tb\n";
}

# ---------------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------------
unless ($skip_build) {
    ensure_chroots();
    build_deps();
}
build_genesis()    unless $skip_genesis;
validate_manifest();
publish_repo();      # no-op unless --publish (or a --skip-build finalization run); tarball is inside
print_step("Completed ($arch: @dist_list)" . ($publish ? '' : ' -- staging only, not published'));

__END__

=head1 NAME

sbuild-all.pl - build, validate, sign and assemble the xcat-dep Ubuntu/Debian apt repository

=head1 SYNOPSIS

  sbuild-all.pl [options]

  # STEP 1 -- per arch, on that arch's build host: build + validate into staging (does NOT publish):
  sbuild-all.pl --arch amd64   --dists "focal jammy noble resolute" \
      --xcat-source ../xcat-core --genesis-rpm <xCAT-genesis-base rpm>
  sbuild-all.pl --arch ppc64el --dists "focal jammy noble resolute" --skip-genesis

  # STEP 2 -- ONCE, after every arch has staged: assemble, sign, gate and publish atomically:
  sbuild-all.pl --skip-build --skip-genesis --publish --expect-arch "amd64 ppc64el" \
      --gpg-sign --gpg-key-id xcat@megware.com --gpg-home <gpg-home>

  # build ONE Ubuntu version only:
  sbuild-all.pl --arch amd64 --dists noble  ...
  sbuild-all.pl --target noble-amd64        ...   # equivalent single-target form

  # single host, build AND publish in one go (add --publish explicitly):
  sbuild-all.pl --arch amd64 --dists noble --genesis-rpm <rpm> --publish --expect-arch amd64 \
      --gpg-sign --gpg-key-id <id> --gpg-home <dir>

  # verify an already-published tree out of band (signatures checked by DEFAULT):
  sbuild-all.pl --verify-repo <apt_dir> --dists "focal jammy noble resolute" \
      --expect-arch "amd64 ppc64el" --gpg-key-id <id> --gpg-home <dir>

  sbuild-all.pl --help        # option summary
  sbuild-all.pl --man         # this manual
  perldoc sbuild-all.pl

=head1 DESCRIPTION

sbuild-all.pl is the top-level Ubuntu/Debian dependency-build orchestrator for xcat-dep -- the
apt/sbuild analogue of the EL C<mockbuild-all.pl>, sharing its CLI vocabulary
(C<BuildUtils::standard_options>) and its manifest-driven, zero-tolerance, fail-hard design. It
absorbs the three former shell scripts (C<mk-dep-chroots.sh>, C<build-dep-debs.sh>,
C<build-apt-repo.sh>) into one Perl entrypoint and drives each package's B<maintained> C<debian/>
packaging (never re-implemented) via its per-package C<< <dep>/sbuild.pl >> builder.

One host builds one architecture (C<--arch>, default C<dpkg --print-architecture>) for a set of
Ubuntu codenames (C<--dists>). Each C<< <codename>-<arch> >> is a B<target> with a section in
C<debs-manifest.conf>. Everything is built and validated into a fresh, per-arch B<staging> tree
first -- so a partial or failed build never reaches the repo and stale debs never accumulate. Any
missing chroot / package / artifact, or any version-pin mismatch, fails the whole run non-zero.

=head2 Build runs stage; publishing is a separate, locked, atomic step

An architecture build run B<does not publish>. The two arches build concurrently on their two hosts
against the same C<--apt-dir>, so a build run that also assembled would interleave its wipe and
rewrite of C<pool/>, C<dists/>, C<Release>, C<InRelease> and the tarball with the other arch's.

Publishing happens only with C<--publish> -- or implicitly on a run that builds nothing
(C<--skip-build>), which B<is> the finalization step. It takes B<one global publish lock> (not the
per-arch build lock), assembles the whole tree into a side directory, runs the completeness +
signature gate against B<that> tree, and only then swaps it onto C<--apt-dir> with a single
C<rename(2)>. Readers therefore see either the previous complete repo or the new complete repo, never
a half-written one, and a failed gate leaves the published tree untouched. Codenames outside
C<--dists> survive the swap (the side tree is seeded from the current published one).

=head2 Each package builds in a clean, disposable chroot

Every package is built in its own C<schroot> session, and the session must be B<throwaway> (an
overlay/union mount or a snapshot). C<sbuild-all.pl> repairs a chroot that lacks one
(C<union-type=overlay>) and hard-fails if it still is not disposable. That is what makes the fail-hard
dependency handling meaningful: inside the session, C<apt-get update>, the common build tooling and
the package's C<Build-Depends> (resolved with C<mk-build-deps>, so versions/alternatives/arch
qualifiers are honoured) are all B<fatal> on failure -- and because nothing survives the session, a
package whose C<debian/control> forgets a C<Build-Depends> cannot build green on a sibling's leftovers.

=head1 PHASES

=over 4

=item Ensure chroots

Auto-initializes any missing C<< <codename>-<arch>-sbuild >> chroot on first run (main + universe,
fast mirror, shared-tree bind-mount) and ensures each one hands out B<disposable> sessions
(C<union-type=overlay>); idempotent. Skipped with C<--skip-build>.

=item Build

Runs each manifest package's C<< <dep>/sbuild.pl >> in the matching chroot into
C<staging/E<lt>codenameE<gt>/E<lt>archE<gt>/>. Dependency installation inside the chroot is fatal on
failure (see L</"Each package builds in a clean, disposable chroot">).

=item Genesis

Produces the C<xcat-genesis-base> deb: a native deb is ingested as-is when provided
(C<--genesis-deb>); otherwise the rpm is converted while B<preserving the maintained control>
(Depends/Breaks/Replaces) and maintainer scripts. The amd64 host also converts the cross-arch
ppc64el genesis (issue #7610) unless C<--require-ppc-genesis> gates it. Skipped with C<--skip-genesis>.
An B<OpenEmbedded Genesis package release> is a separate, verified input published by
C<--genesis-release>; it is not built here.

=item Validate

Asserts every manifest-required package is present at its pinned version (zero tolerance).

=item Publish (C<--publish>; locked + atomic)

Takes the global publish lock, seeds a side tree from the currently published repo, wipes+repopulates
each C<--dists> codename's C<pool>/C<dists> there from validated staging, indexes per B<expected>
C<binary-E<lt>archE<gt>> (Architecture:all packages land in every expected arch index), advertises
exactly the expected arch set in C<Release>, gpg-signs C<Release>/C<InRelease>, runs the gate below
and -- only if it passes -- swaps the side tree onto C<--apt-dir> with C<rename(2)>. Suppressed with
C<--skip-createrepo>; not run at all on a build run without C<--publish>.

=item Verify (repo gate)

A manifest-driven gate asserts -- per codename E<times> expected arch, against the
C<binary-E<lt>archE<gt>/Packages> index apt clients will actually see (not the staging pool) -- that
every manifest-required package is present at its pinned upstream version, that the repo serves
exactly the B<expected architecture set>, and that each codename's C<Release> is validly gpg-signed by
the expected key (C<InRelease>, or detached C<Release.gpg>). Any missing package, version mismatch,
missing index, missing/unexpected architecture, missing manifest section, or unsigned/wrong-key
signature fails the run. The pure decisions (C<BuildUtils::verify_repo_arches> for the arch set,
C<verify_repo_packages> for completeness, C<verify_repo_signature> for the signer) and the parsing
(C<parse_packages_index>, C<parse_release_architectures>) are unit-tested; this script's IO layer
parses the repository + resolves the gpg key and feeds those pure deciders.

The expected architecture set is always a B<claim>, never an inference from what happens to be
present: C<--expect-arch> if given, else the staged arch set when publishing, else each codename's own
C<Release> C<Architectures:> line when verifying standalone. An entirely missing secondary
architecture is therefore reported (C<MISSING-ARCH>), not read as "this run did not build it".

The gate runs automatically before the swap (suppress with C<--no-verify-repo>) and standalone against
an already-published tree via C<--verify-repo=E<lt>apt_dirE<gt>>, where signatures are checked B<by
default> (opt out with C<--no-verify-signature>).

=item Tarball

A repo tarball build artifact of the published tree, taken under the publish lock (the deployable
offline FRS dep bundle is produced by the pipeline's C<deploy.sh --tarball-kind dep>). Skipped with
C<--skip-tarball>.

=back

=head1 OPTIONS

=over 4

=item B<--arch> C<amd64|ppc64el>

Host architecture. Default: C<dpkg --print-architecture>.

=item B<--dists> C<"E<lt>codenamesE<gt>">

Space/comma list of Ubuntu codenames to build. Default: all supported (C<focal jammy noble resolute>).

=item B<--target> C<< <codename>-<arch> >>

Build a single target; the arch must match C<--arch>.

=item B<--manifest> C<path>

Per-target manifest. Default: C<< <repo-root>/debs-manifest.conf >>.

=item B<--repo-root> / B<--xcat-source> C<path>

xcat-dep root (default: the script's dir) / xcat-core root (for the maintained genesis packaging).

=item B<--output-root> / B<--apt-dir> C<path>

Staging + build-output base / published apt tree (default C<< <repo-root>/repos/apt >>).

=item B<--mirror> C<url>

Chroot bootstrap mirror. Default is arch-aware: amd64 uses a fast BR archive mirror, ppc64el uses
C<ports.ubuntu.com/ubuntu-ports> (ppc64el is not served by archive.ubuntu.com). C<archive.ubuntu.com> times out from the
build hosts).

=item B<--genesis-deb> C<path|url>

Native C<xcat-genesis-base> deb to ingest (repeatable; preferred over conversion).

=item B<--genesis-rpm> / B<--genesis-rpm-ppc> C<path|url>

Native-arch genesis rpm to convert / cross-arch ppc genesis rpm to convert on amd64 (issue #7610).

=item B<--require-ppc-genesis>

Make a missing ppc64el genesis fatal (default: warn).

=item B<--genesis-release> C<dir>

Publish an B<OpenEmbedded Genesis package release> alongside the packages this run builds. The
release is produced separately (see F<genesis-openembedded/README.md>); this option only verifies it
and copies the verified bytes into every selected suite.

The release must be B<complete> (every supported Genesis architecture) and must carry C<deb>
packages. It is validated before any build or publish: its C<SHA256SUMS> is read, the shared
verifier runs, and the checksums are read again -- a release rewritten together with its checksums
while the verifier runs is rejected.

The packages are published B<once>, into F<pool/main/xcat-genesis-openembedded>, and every suite's
C<Packages> index points at that one copy: they are C<Architecture: all> and identical everywhere,
so a per-suite copy would multiply hundreds of megabytes by the number of codenames. Because every
suite indexes it, a release must be published for B<all> of them -- a run whose C<--dists> omits a
suite is refused rather than leaving that suite indexing files the new release retired. Each package
is copied and re-checked against the release checksums with the publish lock held, so what is
indexed and signed is exactly what was verified, and anything staged under the OpenEmbedded Genesis
package name is dropped: the release is the only source of those packages.

The OpenEmbedded packages carry their own names and install under
F</opt/xcat/share/xcat/netboot/genesis-openembedded/>, so publishing them does not replace the
C<xcat-genesis-base> package current xcat-core releases use. Omit the option to publish only the
existing Genesis deb.

=item B<--gpg-sign> B<--gpg-key-id> C<id> B<--gpg-home> C<dir>

Sign C<Release>/C<InRelease> with the given key from the given GNUPGHOME.

=item B<--build-number> C<n> B<--build-timestamp> C<epoch> B<--run-id> C<id>

CD identifiers; C<--build-timestamp> also sets C<SOURCE_DATE_EPOCH> for reproducible builds.

=item B<--parallel-targets> C<N>

Per-codename build concurrency on this host. Default 0 = auto = build every requested codename in
parallel (each in its own chroot); N caps it; 1 forces serial. With the two arches on their two hosts,
the default gives 8 concurrent build streams for a 4-codename matrix (4 per host).

=item B<--skip-build> B<--skip-install> B<--skip-genesis> B<--skip-xcat-dep> B<--skip-createrepo> B<--skip-tarball>

Skip the corresponding phase(s). C<--skip-build --skip-genesis> is the finalization run (it publishes
by default; see C<--publish>). C<--skip-createrepo> forces "do not publish" and always wins.

=item B<--install-deps>

Install this host's build prerequisites (the sbuild/schroot toolchain and the Perl modules the
script loads), verify each module now loads, then exit. Run once per build host, as root. Use
alone.

=item B<--publish-lock-wait> C<seconds>

How long to queue behind another publisher before failing (default 1800). Publishing takes one
global lock, so a concurrent publish is waited out rather than interleaved with.

=item B<--publish>

Run the finalization phase: take the global publish lock, assemble + sign into a side tree, gate it and
swap it onto C<--apt-dir> atomically. B<A build run does not publish unless this is given>, so the two
arches can build concurrently without racing each other on the shared repo. Defaults to on for a run
that builds nothing (C<--skip-build>), which is the finalization step. C<--no-publish> forces it off.

=item B<--expect-arch> C<< amd64|ppc64el >>

The architecture set the published repo must serve, stated explicitly. Repeatable, and each value may
be a space/comma list (C<--expect-arch "amd64 ppc64el">). Used by the gate: an expected arch with no
native package is C<MISSING-ARCH>, an unexpected arch that published natives is C<UNEXPECTED-ARCH>,
and C<Release> advertises exactly this set. Without it the gate falls back to the staged arch set when
publishing, or to each codename's C<Release> C<Architectures:> when verifying standalone.

=item B<--verify-repo> C<< =<apt_dir> >>

Standalone mode: verify an already-published apt tree at C<< <apt_dir> >> (architecture set +
completeness + Release signatures) using this script's manifest resolution (C<--manifest> or the
default C<debs-manifest.conf>), C<--dists>, C<--expect-arch>, and C<--gpg-key-id>/C<--gpg-home>, then
exit. Signatures are verified B<by default>. Takes no run lock and builds nothing.

=item B<--no-verify-repo>

Suppress the B<automatic> pre-swap completeness+signature gate (for iteration/debug). The gate is
ON by default.

=item B<--no-verify-signature>

Explicitly skip the Release signature check in the standalone C<--verify-repo> mode (for an
intentionally unsigned local tree). Without it, an unsigned or wrongly-signed repo fails the gate.

=item B<--dry-run>

Print the planned actions without executing them.

=item B<--help> / B<--man>

Option summary / this manual.

=back

=head1 SEE ALSO

C<mockbuild-all.pl> (the EL analogue), C<BuildUtils.pm>, C<< <dep>/sbuild.pl >>,
C<debs-manifest.conf>, and F<BUILD.md>.

=cut
