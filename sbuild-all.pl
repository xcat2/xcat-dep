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
#   2. Everything is built + validated into a FRESH per-run STAGING tree first; the published apt repo
#      is (re)assembled from staging ONLY after the complete expected set validates -- so a partial or
#      failed build never reaches the published repo, and stale debs never accumulate (concern #1).
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
use lib $RealBin;
use BuildUtils qw(sh_quote print_step version_matches required_pkgs read_manifest standard_options
                  verify_repo_packages verify_repo_signature parse_packages_index resolve_present_names
                  index_has_native_arch
                  codename_to_version known_codenames chroot_name chroot_sources_list
                  control_field genesis_deb_control
                  deb_field deb_version deb_upstream_version deb_hash cross_copy_genesis_deb);

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
my ($skip_createrepo, $skip_tarball) = (0,0);
my $dry_run = 0;
# Completeness+signature gate on the PUBLISHED apt index (what apt clients see). $verify_repo_arg set
# (--verify-repo=<apt_dir>) runs the gate STANDALONE against that assembled apt dir and exits (no lock,
# no build). $no_verify_repo suppresses the AUTOMATIC post-assembly gate that otherwise runs at the end
# of assemble_apt. Default: automatic gate ON.
my $verify_repo_arg = '';
my $no_verify_repo  = 0;
my $gpg_sign = 0;
my $gpg_key_id = 'xcat@megware.com';
my $gpg_home = '';
my @genesis_debs;                    # native xcat-genesis-base-<arch> deb(s): path or URL (preferred)
my $genesis_rpm = '';                # fallback: native-arch genesis rpm to convert
my $genesis_rpm_ppc = '';            # fallback: cross-arch ppc genesis rpm to convert (amd64 host)
my $require_ppc_genesis = 0;
# File-scoped exclusive run-lock handle. MUST be file-scoped (not a lexical inside a block) so the
# flock lives for the WHOLE process -- a lexical would close the FH and release the lock early.
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
$spec{'verify-repo=s'}         = \$verify_repo_arg;   # standalone gate: --verify-repo=<apt_dir>
$spec{'no-verify-repo!'}       = \$no_verify_repo;    # suppress the automatic post-assembly gate
$spec{'output=s'}              = \$output_root;   # --output alias
$spec{'help|h'}                = sub { pod2usage(-verbose => 1, -exitval => 0); };
$spec{'man'}                   = sub { pod2usage(-verbose => 2, -exitval => 0); };

GetOptions(%spec) or pod2usage(-verbose => 1, -exitval => 2);

# ---------------------------------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------------------------------
$repo_root = abs_path($repo_root);
$xcat_src  = abs_path($xcat_src) if -d $xcat_src;
$manifest  ||= "$repo_root/debs-manifest.conf";
$arch      ||= `dpkg --print-architecture 2>/dev/null`; chomp $arch;
$arch      ||= 'amd64';
die "FATAL: unsupported --arch '$arch' (amd64|ppc64el)\n" unless $arch =~ /^(amd64|ppc64el)$/;
# Arch-aware chroot bootstrap mirror: ppc64el is NOT served by archive.ubuntu.com -- it lives on
# ubuntu-ports. Only defaulted when --mirror was not given explicitly.
$mirror    ||= ($arch eq 'ppc64el') ? 'http://ports.ubuntu.com/ubuntu-ports'
                                     : 'http://br.archive.ubuntu.com/ubuntu';

# --target "<codename>-<arch>" pins a single codename (and cross-checks the arch); otherwise --dists.
my @dist_list;
if ($dists =~ /-(amd64|ppc64el)$/) {
    my ($cn, $a) = $dists =~ /^(.+)-(amd64|ppc64el)$/;
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

$output_root ||= "$repo_root/build-output/sbuild-all";
$apt_dir     ||= "$repo_root/repos/apt";
$run_id      ||= strftime("%Y%m%d-%H%M%S", localtime());
$build_timestamp = time() unless defined $build_timestamp;
my $snap_ts = strftime("%Y%m%d%H%M", gmtime($build_timestamp));
$ENV{SOURCE_DATE_EPOCH} = $build_timestamp;   # deterministic mtimes across the whole run

my %MANIFEST = read_manifest($manifest);

# Standalone gate: --verify-repo=<apt_dir> checks an already-assembled apt tree (completeness +
# Release signatures) using THIS script's manifest resolution (--manifest or the default
# debs-manifest.conf), --dists, and --gpg-key-id/--gpg-home, then exits. It takes NO run lock and does
# NOT build. Dispatched here (after manifest + @dist_list are resolved) so it never trips the
# build-only per-target section check below and never reaches the lock/build phases.
if (length $verify_repo_arg) {
    die "FATAL: --verify-repo apt dir not found: $verify_repo_arg\n" unless -d $verify_repo_arg;
    print_step('Standalone repo verification (no build, no lock)');
    verify_assembled_repo(\%MANIFEST, abs_path($verify_repo_arg), \@dist_list, [$arch]);
    exit 0;
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
        if (have_chroot($name)) { print "  chroot $name: present\n"; next; }
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
        print "  chroot $name: created\n";
    }
}

# ---------------------------------------------------------------------------------------------------
# Phase: build the compiled deps (drives each <dep>/sbuild.pl in the matching chroot)
# ---------------------------------------------------------------------------------------------------
# build_one_codename: build every required (non-genesis) package for ONE codename, serially, each in
# that codename's <codename>-<arch>-sbuild chroot. Returns 0 on success, non-zero if any package
# failed. Called either directly (serial mode) or inside a forked child (parallel mode).
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
    if ($a eq 'ppc64el') { $t =~ s/amd64/ppc64el/g; }
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
            my $want = $MANIFEST{$tgt}{$pkg};
            my $got  = deb_version($dir, $pkg);
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
# resolve each required manifest @names against it, returning %present = (reqname => upstream-version |
# undef). Name-resolution mirrors deb_version/validate_manifest: try an EXACT index key first (most
# packages -- ipmitool-xcat, goconserver, grub2-xcat, the Architecture:all boot bits keep their plain
# names), else exactly <name>-<arch> for THIS cell's arch (the arch-suffixed xcat-genesis-base ->
# xcat-genesis-base-<arch>, never a different arch's). The published Version carries epoch+revision, so
# it is reduced to the UPSTREAM part (what the manifest pins) via deb_upstream_version before the pure
# comparator. (Resolution itself lives in the pure BuildUtils::resolve_present_names.)
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

# verify_assembled_repo($manifest_href, $apt_dir, $dists_aref): the ONE completeness+signature gate,
# shared by the automatic post-assembly run (end of assemble_apt) and the standalone --verify-repo mode.
# It is the IO layer: it PARSES the repository (parse_packages_index of each published
# binary-<arch>/Packages -> %present; gpg --verify of each dists/<cn>/InRelease -> %observed signer),
# PARSES the manifest (-> %expected pkg pins per cell) and resolves the GPG key (--gpg-key-id -> expected
# signer), then delegates the DECISION to the pure verify_repo_packages (per codename x arch) and
# verify_repo_signature (per codename). Package problems are [<cn>/<arch>]-prefixed; the pure signature
# problems already carry the codename unit. Any problem dies non-zero.
sub verify_assembled_repo {
    my ($man, $adir, $dists, $arches, $sig_enabled) = @_;
    my @all;
    # $sig_enabled: whether a valid signature is REQUIRED. The post-assembly auto-run passes $gpg_sign
    # -- a repo assembled WITHOUT --gpg-sign is intentionally unsigned, so don't demand a signature and
    # false-fail. Standalone --verify-repo passes undef -> fall back to "a gpg key/home is configured".
    $sig_enabled = ($gpg_home ne '' || $gpg_sign) unless defined $sig_enabled;
    my $expected_key = $sig_enabled ? resolve_expected_key() : undef;
    my $expected_is_fpr = defined($expected_key) ? 1 : 0;
    print "  apt-dir: $adir\n";
    print "  signature check: " . ($sig_enabled
        ? "on (expected key " . ($expected_key // $gpg_key_id) . ($expected_is_fpr ? '' : ' [UNRESOLVED -> hard fail]') . ")"
        : "SKIPPED (no --gpg-home/--gpg-sign)") . "\n";
    # STRICT: if signing is expected but --gpg-key-id does not resolve to a fingerprint (not in the
    # keyring), we CANNOT confirm the signer -- that is a hard failure, never a presence-only pass.
    push @all, "SIGKEY: cannot resolve --gpg-key-id '$gpg_key_id' to a fingerprint (in the $gpg_home keyring?)"
        if $sig_enabled && !$expected_is_fpr;

    my (%exp_sig, %obs_sig, %checked_arch);
    for my $cn (@$dists) {
        # Arches to verify for THIS codename: the caller's --arch set (the required FLOOR -- always
        # checked, so an explicitly-requested arch whose index is empty/missing is still caught)
        # UNIONed with any arch that actually published a non-empty binary-<arch>/Packages. This lets
        # the multi-arch assemble (invoked with a single --arch amd64) still verify the ppc64el debs it
        # carries, while a genuinely single-arch run (e.g. BUILD_PPC=false, amd64 only) never
        # false-fails demanding an arch it did not build.
        my %want = map { $_ => 1 } @{ $arches || [] };
        # Add an arch iff it published NATIVE debs (a Packages stanza with Architecture == that arch),
        # NOT merely a non-empty index: every binary-<arch>/Packages carries the Architecture:all debs
        # (grub2-xcat, genesis), so a non-empty ppc index does NOT imply ppc was built. Native-arch
        # detection keeps a genuine single-arch run (BUILD_PPC=false) from demanding the ppc section.
        for my $a (qw(amd64 ppc64el)) {
            my $idx = "$adir/dists/$cn/main/binary-$a/Packages";
            next unless -f $idx;
            open my $ifh, '<', $idx or next;
            local $/; my $body = <$ifh>; close $ifh;
            $want{$a} = 1 if index_has_native_arch($body, $a);
        }
        # completeness: manifest (source of truth) vs the PUBLISHED index, per codename x arch.
        for my $a (sort keys %want) {
            $checked_arch{$a} = 1;
            my $tgt = "$cn-$a";
            my $req = $man->{$tgt};
            unless ($req && %$req) {
                print "  [$cn/$a] no manifest section [$tgt] -- skipping (codename does not target this arch)\n";
                next;
            }
            my @names = required_pkgs([sort keys %$req], $skip_genesis, $skip_xcat_dep);
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
        if ($sig_enabled && $expected_is_fpr) {
            $exp_sig{$cn} = $expected_key;
            $obs_sig{$cn} = sig_observed_key($adir, $cn);
        }
    }
    push @all, verify_repo_signature(\%exp_sig, \%obs_sig) if $sig_enabled && $expected_is_fpr;

    if (@all) {
        print "$_\n" for @all;
        die "FATAL: apt repo INCOMPLETE (" . scalar(@all) . " problem(s))\n";
    }
    print "[verify-repo] complete: all required packages present + version-pinned"
        . ($sig_enabled ? " + Release signatures valid (key $expected_key)" : "")
        . " for [" . join(' ', @$dists) . "] x {" . join(',', sort keys %checked_arch) . "}\n";
    return;
}

# ---------------------------------------------------------------------------------------------------
# Phase: assemble + sign the apt repo (absorbed build-apt-repo.sh; promote-on-success)
# ---------------------------------------------------------------------------------------------------
sub assemble_apt {
    return if $skip_createrepo;
    print_step('Assemble apt repo (promote validated staging -> published repo)');
    run("command -v apt-ftparchive >/dev/null 2>&1 || { echo 'need apt-utils' >&2; exit 1; }", always => 1) unless $dry_run;
    for my $cn (@dist_list) {
        my $ver = codename_to_version($cn);
        my $pool = "$apt_dir/pool/main/$cn";
        # wipe ONLY this codename's published pool+dists, then repopulate from validated staging
        # (both arches: staging/<cn>/{amd64,ppc64el}/*.deb). Wiping first is what removes stale debs
        # from a prior run so the published repo never carries a mixture (concern #1).
        wipe_tree($pool, "$apt_dir/dists/$cn", "$apt_dir/$ver") unless $dry_run;
        make_path($pool, "$apt_dir/$ver") unless $dry_run;
        unless ($dry_run) {
            # Collect this codename's staged debs across both arches, deduping on binary package
            # NAME+ARCH: if two files resolve to the same package+arch (e.g. a native ppc genesis and
            # an amd64-host cross-converted one both claiming xcat-genesis-base-ppc64el/all) only ONE
            # may reach the pool. Keep the highest version and warn naming both -- a safety net that
            # holds regardless of the --skip-genesis single-producer contract (concern #4).
            my %best;   # "name|arch" => { file => path, ver => version }
            for my $deb (glob("$staging/$cn/*/*.deb")) {
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
                copy($deb, "$apt_dir/$ver/$b");
            }
        }
        # Packages index per binary-<arch>: an arch's index carries that arch's debs + all Architecture:all.
        for my $a (qw(amd64 ppc64el)) {
            my $bindir = "$apt_dir/dists/$cn/main/binary-$a";
            make_path($bindir) unless $dry_run;
            next if $dry_run;
            my $all = `cd ${\ sh_quote($apt_dir)} && apt-ftparchive packages pool/main/$cn`;
            open my $pf, '>', "$bindir/Packages" or die "write Packages: $!\n";
            for my $para (split /\n\n+/, $all) {
                next unless $para =~ /\S/;
                my ($pa) = $para =~ /^Architecture:\s*(\S+)/m;
                print $pf "$para\n\n" if defined $pa && ($pa eq $a || $pa eq 'all');
            }
            close $pf;
            run("gzip -9 -kf -n " . sh_quote("$bindir/Packages"));
        }
        next if $dry_run;
        # Advertise ONLY the arches actually staged for this codename: an arch counts iff its
        # binary-<arch>/Packages is non-empty. A single-arch run must not claim a missing arch in
        # Release (apt would then error on the absent index).
        my @staged_arches = grep { -s "$apt_dir/dists/$cn/main/binary-$_/Packages" } qw(amd64 ppc64el);
        @staged_arches = ('amd64') unless @staged_arches;   # never emit an empty Architectures line
        # Release + sign
        my @rel = ('apt-ftparchive',
            '-o', 'APT::FTPArchive::Release::Origin=xCAT',
            '-o', 'APT::FTPArchive::Release::Label=xcat-dep',
            '-o', "APT::FTPArchive::Release::Suite=$cn",
            '-o', "APT::FTPArchive::Release::Codename=$cn",
            '-o', 'APT::FTPArchive::Release::Architectures=' . join(' ', @staged_arches),
            '-o', 'APT::FTPArchive::Release::Components=main',
            '-o', "APT::FTPArchive::Release::Description=xCAT dependency packages for $ver",
            'release', "$apt_dir/dists/$cn/");
        run(join(' ', map { sh_quote($_) } @rel) . " > " . sh_quote("$apt_dir/dists/$cn/Release"));
        my $det = strftime("%a, %d %b %Y %H:%M:%S +0000", gmtime($build_timestamp));
        run("sed -i " . sh_quote("s/^Date: .*/Date: $det/") . " " . sh_quote("$apt_dir/dists/$cn/Release"), nofail => 1);
        if ($gpg_sign) {
            my $g = $gpg_home ? "GNUPGHOME=" . sh_quote($gpg_home) . " " : '';
            my $rel = "$apt_dir/dists/$cn/Release";
            run("${g}gpg --default-key " . sh_quote($gpg_key_id) . " --batch --yes --armor --detach-sign -o "
               . sh_quote("$rel.gpg") . " " . sh_quote($rel));
            run("${g}gpg --default-key " . sh_quote($gpg_key_id) . " --batch --yes --armor --clearsign -o "
               . sh_quote("$apt_dir/dists/$cn/InRelease") . " " . sh_quote($rel));
        }
        print "  assembled + " . ($gpg_sign ? 'signed' : 'UNSIGNED') . " apt tree for $cn\n";
    }
    # export the signing pubkey for clients
    if ($gpg_sign && !$dry_run) {
        my $g = $gpg_home ? "GNUPGHOME=" . sh_quote($gpg_home) . " " : '';
        my $keysrc = "$repo_root/repomd.xml.key";
        if (-f $keysrc) { copy($keysrc, "$apt_dir/xcat-dep.asc"); }
        else { run("${g}gpg --armor --export " . sh_quote($gpg_key_id) . " > " . sh_quote("$apt_dir/xcat-dep.asc"), nofail => 1); }
    }
    # Automatic post-assembly GATE on the just-published index (completeness + Release signatures).
    # Runs once every codename's dists/<cn>/.../Packages + signed Release are written. Suppressed with
    # --no-verify-repo (iteration/debug); skipped under --dry-run (nothing was published).
    unless ($no_verify_repo || $dry_run) {
        print_step('Verify published apt repo (post-assembly completeness + signature gate)');
        # Require a valid signature iff we actually signed (--gpg-sign); a repo assembled without it is
        # intentionally unsigned and must not false-fail. (Standalone --verify-repo omits this arg.)
        verify_assembled_repo(\%MANIFEST, $apt_dir, \@dist_list, [$arch], $gpg_sign);
    }
}

# ---------------------------------------------------------------------------------------------------
# Phase: tarball (optional)
# ---------------------------------------------------------------------------------------------------
sub make_tarball {
    return if $skip_tarball;
    print_step('Tarball');
    my $tb = "$output_root/$run_id/xcat-dep-$arch-$run_id.tar.gz";
    make_path(dirname($tb)) unless $dry_run;   # the run dir may not exist yet (e.g. an assemble-only run)
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
assemble_apt();
make_tarball();
print_step("Completed ($arch: @dist_list)");

__END__

=head1 NAME

sbuild-all.pl - build, validate, sign and assemble the xcat-dep Ubuntu/Debian apt repository

=head1 SYNOPSIS

  sbuild-all.pl [options]

  # build ALL supported Ubuntu versions for this host's arch, sign + assemble the apt tree:
  sbuild-all.pl --arch amd64 --dists "focal jammy noble resolute" \
      --xcat-source ../xcat-core --genesis-rpm <xCAT-genesis-base rpm> \
      --gpg-sign --gpg-key-id xcat@megware.com --gpg-home <gpg-home>

  # build ONE Ubuntu version only:
  sbuild-all.pl --arch amd64 --dists noble  ...
  sbuild-all.pl --target noble-amd64        ...   # equivalent single-target form

  # assemble-only (re-sign/re-index from already-built staging):
  sbuild-all.pl --skip-build --skip-genesis --gpg-sign --gpg-key-id <id> --gpg-home <dir>

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
first; the published apt repo is (re)assembled from validated staging only after the complete
expected set validates -- so a partial or failed build never reaches the repo and stale debs never
accumulate. Any missing chroot / package / artifact, or any version-pin mismatch, fails the whole
run non-zero.

=head1 PHASES

=over 4

=item Ensure chroots

Auto-initializes any missing C<< <codename>-<arch>-sbuild >> chroot on first run (main + universe,
fast mirror, shared-tree bind-mount); idempotent. Skipped with C<--skip-build>.

=item Build

Runs each manifest package's C<< <dep>/sbuild.pl >> in the matching chroot into
C<staging/E<lt>codenameE<gt>/E<lt>archE<gt>/>.

=item Genesis

Produces the C<xcat-genesis-base> deb: a native deb is ingested as-is when provided
(C<--genesis-deb>); otherwise the rpm is converted while B<preserving the maintained control>
(Depends/Breaks/Replaces) and maintainer scripts. The amd64 host also converts the cross-arch
ppc64el genesis (issue #7610) unless C<--require-ppc-genesis> gates it. Skipped with C<--skip-genesis>.

=item Validate

Asserts every manifest-required package is present at its pinned version (zero tolerance).

=item Assemble

Wipes+repopulates each codename's published C<pool>/C<dists> from validated staging, indexes per
C<binary-E<lt>archE<gt>> (Architecture:all packages land in every arch index) and gpg-signs
C<Release>/C<InRelease>. Skipped with C<--skip-createrepo>.

=item Verify (published-repo gate)

After assembly, a manifest-driven gate asserts -- per codename E<times> arch, against the B<published>
C<binary-E<lt>archE<gt>/Packages> index apt clients actually see (not the staging pool) -- that every
manifest-required package is present at its pinned upstream version, and that each codename's
C<Release> is validly gpg-signed by the expected key (C<InRelease>, or detached C<Release.gpg>). Any
missing package, version mismatch, missing index, or unsigned/wrong-key signature fails the run. The
pure decisions (C<BuildUtils::verify_repo_packages> for completeness, C<BuildUtils::verify_repo_signature>
for the signer) and the index parsing (C<BuildUtils::parse_packages_index>) are unit-tested; this
script's IO layer parses the repository + resolves the gpg key and feeds those pure deciders. This
automatic gate is suppressed with C<--no-verify-repo>; the same check runs standalone against an
already-assembled tree via C<--verify-repo=E<lt>apt_dirE<gt>>.

=item Tarball

A repo tarball build artifact (the deployable offline FRS dep bundle is produced by the pipeline's
C<deploy.sh --tarball-kind dep>). Skipped with C<--skip-tarball>.

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

=item B<--gpg-sign> B<--gpg-key-id> C<id> B<--gpg-home> C<dir>

Sign C<Release>/C<InRelease> with the given key from the given GNUPGHOME.

=item B<--build-number> C<n> B<--build-timestamp> C<epoch> B<--run-id> C<id>

CD identifiers; C<--build-timestamp> also sets C<SOURCE_DATE_EPOCH> for reproducible builds.

=item B<--parallel-targets> C<N>

Per-codename build concurrency on this host. Default 0 = auto = build every requested codename in
parallel (each in its own chroot); N caps it; 1 forces serial. With the two arches on their two hosts,
the default gives 8 concurrent build streams for a 4-codename matrix (4 per host).

=item B<--skip-build> B<--skip-install> B<--skip-genesis> B<--skip-xcat-dep> B<--skip-createrepo> B<--skip-tarball>

Skip the corresponding phase(s). C<--skip-build --skip-genesis> gives an assemble-only run.

=item B<--verify-repo> C<< =<apt_dir> >>

Standalone mode: verify an already-assembled apt tree at C<< <apt_dir> >> (completeness + Release
signatures) using this script's manifest resolution (C<--manifest> or the default
C<debs-manifest.conf>), C<--dists>, and C<--gpg-key-id>/C<--gpg-home>, then exit. Takes no run lock and
builds nothing.

=item B<--no-verify-repo>

Suppress the B<automatic> post-assembly completeness+signature gate (for iteration/debug). The gate is
ON by default.

=item B<--dry-run>

Print the planned actions without executing them.

=item B<--help> / B<--man>

Option summary / this manual.

=back

=head1 SEE ALSO

C<mockbuild-all.pl> (the EL analogue), C<BuildUtils.pm>, C<< <dep>/sbuild.pl >>,
C<debs-manifest.conf>, and F<BUILD.md>.

=cut
