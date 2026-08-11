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
use File::Copy qw(copy);
use File::Temp qw(tempdir);
use Getopt::Long qw(GetOptions);
use Pod::Usage qw(pod2usage);
use POSIX qw(strftime);
use FindBin qw($RealBin);
use lib $RealBin;
use BuildUtils qw(sh_quote print_step version_matches required_pkgs read_manifest standard_options
                  codename_to_version known_codenames chroot_name chroot_sources_list
                  deb_snap_version rewrite_changelog_top control_field genesis_deb_control
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
my ($skip_build, $skip_install, $skip_genesis, $skip_xcat_dep) = (0,0,0,0);
my ($skip_createrepo, $skip_tarball) = (0,0);
my $dry_run = 0;
my $gpg_sign = 0;
my $gpg_key_id = 'xcat@megware.com';
my $gpg_home = '';
my @genesis_debs;                    # native xcat-genesis-base-<arch> deb(s): path or URL (preferred)
my $genesis_rpm = '';                # fallback: native-arch genesis rpm to convert
my $genesis_rpm_ppc = '';            # fallback: cross-arch ppc genesis rpm to convert (amd64 host)
my $require_ppc_genesis = 0;

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
$spec{'genesis-deb=s'}         = \@genesis_debs;
$spec{'genesis-rpm=s'}         = \$genesis_rpm;
$spec{'genesis-rpm-ppc=s'}     = \$genesis_rpm_ppc;
$spec{'require-ppc-genesis!'}  = \$require_ppc_genesis;
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
sub build_deps {
    print_step("Build compiled deps ($arch)");
    for my $cn (@dist_list) {
        my $tgt = "$cn-$arch";
        my $out = "$staging/$cn/$arch"; remove_tree($out) if -d $out; make_path($out);
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
            print "  -> $pkg ($dir/sbuild.pl)\n";
            my $ec = run($cmd, nofail => 1);
            die "FATAL: [$cn] $pkg build failed (rc=$ec) -- see $log\n" if $ec != 0;
        }
    }
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
    my $gen = "$output_root/$run_id/genesis"; remove_tree($gen) if -d $gen; make_path($gen);
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
    for my $cn (@dist_list) {
        make_path("$staging/$cn/$arch") unless $dry_run;
        for my $d (glob("$gen/*.deb")) {
            copy($d, "$staging/$cn/$arch/" . basename($d)) unless $dry_run;
            print "  staged " . basename($d) . " -> $cn/$arch\n";
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
        remove_tree($pool, "$apt_dir/dists/$cn", "$apt_dir/$ver") unless $dry_run;
        make_path($pool, "$apt_dir/$ver") unless $dry_run;
        for my $deb (glob("$staging/$cn/*/*.deb")) {
            my $b = basename($deb);
            unless ($dry_run) { link($deb, "$pool/$b") or copy($deb, "$pool/$b"); copy($deb, "$apt_dir/$ver/$b"); }
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
        # Release + sign
        my @rel = ('apt-ftparchive',
            '-o', 'APT::FTPArchive::Release::Origin=xCAT',
            '-o', 'APT::FTPArchive::Release::Label=xcat-dep',
            '-o', "APT::FTPArchive::Release::Suite=$cn",
            '-o', "APT::FTPArchive::Release::Codename=$cn",
            '-o', 'APT::FTPArchive::Release::Architectures=amd64 ppc64el',
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

=item B<--skip-build> B<--skip-install> B<--skip-genesis> B<--skip-xcat-dep> B<--skip-createrepo> B<--skip-tarball>

Skip the corresponding phase(s). C<--skip-build --skip-genesis> gives an assemble-only run.

=item B<--dry-run>

Print the planned actions without executing them.

=item B<--help> / B<--man>

Option summary / this manual.

=back

=head1 SEE ALSO

C<mockbuild-all.pl> (the EL analogue), C<BuildUtils.pm>, C<< <dep>/sbuild.pl >>,
C<debs-manifest.conf>, and F<BUILD.md>.

=cut
