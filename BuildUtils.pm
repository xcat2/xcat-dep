package BuildUtils;
# Reusable, unit-testable helpers for the xcat-dep build tooling. This module is the SHARED,
# format-agnostic home (sh_quote, print_step, version_matches, read_manifest, required_pkgs,
# standard_options) plus the Debian/apt-specific helpers used by sbuild-all.pl and the per-package
# <dep>/sbuild.pl builders. It mirrors the EL-side MockBuildUtils.pm and is kept free of any
# orchestrator globals so t/sbuild-all.t can exercise every function directly. The two helpers that
# need signing / re-indexing (cross_copy_genesis_deb) take those as injected callbacks instead of
# reaching for gpg/apt-ftparchive state, so they stay pure and testable.
#
# NOTE (deferred EL migration): the format-agnostic helpers below are duplicated in MockBuildUtils.pm
# today. PR #62 (the EL matrix build) is in review; once it lands, a follow-up migrates
# mockbuild-all.pl/MockBuildUtils.pm onto BuildUtils.pm so the two orchestrators share ONE copy of
# these helpers and ONE CLI spec (standard_options). Until then BuildUtils.pm is the authoritative,
# forward-looking home and MockBuildUtils.pm keeps its own copies untouched.
use strict;
use warnings;
use Exporter 'import';
use File::Basename qw(basename dirname);
use lib dirname(__FILE__) . '/lib';
use XCAT::BuildUtils qw(run_bounded emulated_build_timeout);
use File::Copy qw(copy);
use File::Path qw(make_path);
use Digest::MD5;
use MIME::Base64 qw(encode_base64);

our @EXPORT_OK = qw(
    install_deps_packages install_deps_command missing_perl_modules
    sh_quote print_step
    version_matches required_pkgs read_manifest standard_options
    verify_repo_packages verify_repo_signature verify_repo_arches
    parse_packages_index parse_release_architectures resolve_present_names
    index_has_native_arch control_binary_arch skip_arch_all_on
    codename_to_version version_to_codename known_codenames
    supported_arches is_supported_arch
    chroot_name chroot_sources_list chroot_is_disposable chroot_build_script
    chroot_build_timeout
    control_field genesis_deb_control
    deb_field deb_version deb_hash cross_copy_genesis_deb
    build_deb_in_chroot
);

# Canonical Ubuntu codename <-> ubuntuXX.YY map. This is the SINGLE source of truth for the
# supported codename set (concern #5: build, repo-assembly, chroot init and the manifest all derive
# from here, so they can never drift). focal IS supported (there are ubuntu-20-* pipeline confs and
# core build-ubunturepo ships focal) — the old build-apt-repo.sh bug was omitting it.
my %CODENAME_TO_VERSION = (
    focal    => 'ubuntu20.04',
    jammy    => 'ubuntu22.04',
    noble    => 'ubuntu24.04',
    resolute => 'ubuntu26.04',
);
my %VERSION_TO_CODENAME = reverse %CODENAME_TO_VERSION;

sub known_codenames    { return sort keys %CODENAME_TO_VERSION; }

# The dpkg architectures xcat-dep builds. amd64 is the native one and the single producer of the
# Architecture:all packages; every other one is a secondary architecture, is served by
# ubuntu-ports rather than archive.ubuntu.com, and is built through a qemu-user chroot when the
# build host is amd64. Keep this the single source of truth: --arch, --target, --expect-arch and
# the mirror choice all derive from it.
my @ARCHES = qw(amd64 ppc64el riscv64);
my %ARCH   = map { $_ => 1 } @ARCHES;

sub supported_arches   { return @ARCHES; }
sub is_supported_arch  { my ($a) = @_; return defined($a) && $ARCH{$a} ? 1 : 0; }
sub codename_to_version { my ($c) = @_; return $CODENAME_TO_VERSION{$c // ''}; }
sub version_to_codename { my ($v) = @_; return $VERSION_TO_CODENAME{$v // ''}; }

# ---------------------------------------------------------------------------------------------------
# Shared / format-agnostic helpers (identical semantics to MockBuildUtils.pm; see migration note).
# ---------------------------------------------------------------------------------------------------

# install_deps_packages(): the host packages sbuild-all.pl needs to run at all. Kept as data beside
# the code that needs them: the failure mode is a build host provisioned by hand, and a missing perl
# module surfaces as a compile-time abort in the middle of a CD run rather than as a clear message
# (xcat-master-ub had no File::Slurper, which is how this was found).
sub install_deps_packages {
    # NOTE: no libipc-cmd-perl -- IPC::Cmd is CORE on Debian/Ubuntu (it ships in perl-modules) and
    # no such package exists, so naming it fails the whole install. That it is present is asserted
    # by the module probe, not by installing a package.
    return qw(perl libfile-slurper-perl libparallel-forkmanager-perl
              sbuild schroot debootstrap apt-utils dpkg-dev devscripts equivs quilt fakeroot
              build-essential reprepro gnupg rsync wget git);
}

# install_deps_command(): the argv that installs them, non-interactively.
sub install_deps_command {
    return ('apt-get', 'install', '-y', '--no-install-recommends', install_deps_packages());
}

# missing_perl_modules(@modules): those that cannot be loaded, in order. --install-deps proves the
# modules by LOADING them, rather than trusting the package manager's exit code.
sub missing_perl_modules {
    my (@modules) = @_;
    my @missing;
    for my $m (@modules) {
        my $file = $m;
        $file =~ s{::}{/}g;
        $file .= '.pm';
        eval { require $file; 1 } or push @missing, $m;
    }
    return @missing;
}

# sh_quote: single-quote a string for safe use in a shell command.
sub sh_quote {
    my ($s) = @_;
    $s = '' if !defined $s;
    $s =~ s/'/'"'"'/g;
    return "'$s'";
}

# print_step: print a step banner.
sub print_step {
    my ($msg) = @_;
    print "\n== $msg ==\n";
}

# version_matches: does the built version $got satisfy the manifest pin $want? $want may be an
# exact version (0.3.3), a shell-style glob (2.*  or  2.19.*), or '*' (any). Globs support * and ?
# and are anchored. Used so xcat-genesis-base can pin 2.* (its Version walks with xcat-core) while
# the real xcat-dep packages stay exactly pinned.
sub version_matches {
    my ($got, $want) = @_;
    return 1 if !defined($want) || $want eq '*';
    return ($got eq $want) unless $want =~ /[*?]/;
    my $re = quotemeta($want);
    $re =~ s/\\\*/.*/g;
    $re =~ s/\\\?/./g;
    return $got =~ /\A$re\z/ ? 1 : 0;
}

# required_pkgs: given the manifest package names for a target and the skip flags, return the subset
# that must actually be built and validated. A package whose builder was skipped is NOT required:
# --skip-genesis drops xcat-genesis-base, --skip-xcat-dep drops the compiled dep builders
# (everything that is not genesis). Pure function (flags passed in) so both the version-pin check
# and the collection validation use it and it is unit-testable. The Debian side has no perl set
# (unlike EL), so there is no --skip-perl dimension.
sub required_pkgs {
    my ($pkgs, $skip_genesis, $skip_dep) = @_;
    return grep {
           !($skip_genesis && $_ eq 'xcat-genesis-base')
        && !($skip_dep     && $_ ne 'xcat-genesis-base')
    } @$pkgs;
}

# read_manifest: parse a per-target manifest into %{ target => { package => version|'*' } }.
# INI format: [target] sections; "package=version|*" entries; blank / "#" / ";" lines ignored.
# Returns an empty hash if the file is absent (callers that build require a section per target).
# Identical parser to MockBuildUtils::read_manifest so both manifests share one grammar.
sub read_manifest {
    my ($path) = @_;
    my %m;
    return %m unless -f $path;
    open my $fh, '<', $path or die "Cannot read manifest $path: $!\n";
    my $sec;
    while (my $line = <$fh>) {
        $line =~ s/\r?\n\z//;
        $line =~ s/^\s+|\s+$//g;
        next if $line eq '' || $line =~ /^[#;]/;
        if ($line =~ /^\[(.+?)\]$/) { $sec = $1; $m{$sec} ||= {}; next; }
        next unless defined $sec;
        my ($k, $v) = split /=/, $line, 2;
        $k =~ s/\s+\z//;
        $v = defined($v) ? ($v =~ s/^\s+//r) : '';
        $m{$sec}{$k} = ($v ne '') ? $v : '*';
    }
    close $fh;
    return %m;
}

# standard_options: the CANONICAL Getopt::Long option specs shared by sbuild-all.pl and (after the
# deferred migration) mockbuild-all.pl, so both orchestrators speak ONE flag vocabulary. Returns an
# ordered list of "name=type" / "name!" spec strings. A script builds its GetOptions() from this
# list mapped to its own destination variables, and MAY add a few tool-specific specs of its own
# (e.g. rpm's --gpg-key-name vs apt's --gpg-key-id, or sbuild's --require-ppc-genesis). Keeping the
# core set here is what makes "standardize the CLI" enforceable and unit-testable.
sub standard_options {
    return qw(
        repo-root=s xcat-source=s
        output=s output-root=s
        target=s manifest=s
        skip-build! skip-install! skip-genesis! skip-xcat-dep!
        skip-createrepo! skip-tarball!
        run-id=s build-timestamp=i build-number=i
        parallel-targets=i parallel-builds=i max-parallel=i
        gpg-sign! gpg-home=s
        genesis-release=s
        dry-run!
    );
}

# ---------------------------------------------------------------------------------------------------
# Published-repo completeness gate (PURE decision + PURE index parsing; no I/O, no manifest parsing).
# These are the unit-testable core of the manifest-driven completeness gate: the disk/name-resolution
# layer (sbuild-all.pl) feeds them plain hashes/strings so the DECISION stays testable without a repo.
# ---------------------------------------------------------------------------------------------------

# verify_repo_packages(\%expected, \%present) -> @problems
#   %expected : pkg name => manifest version pin ('*' = any)
#   %present  : pkg name => the actual (upstream) version found in the repo, or undef/absent if not found
# Returns human-readable problem strings (empty list = the repo is complete for this set):
#   "MISSING <pkg> (manifest requires <pin>)"              -- required package not present at all
#   "VERSION <pkg>: repo has <got>, manifest pins <pin>"   -- present but the pin is not satisfied
# The pin semantics are exactly BuildUtils::version_matches (the same check validate_manifest uses on
# freshly-built debs), so a repo that "validates on build" and a repo that "validates on publish" agree.
# Pure: no I/O, deterministic ordering (problems returned in sorted package-name order).
sub verify_repo_packages {
    my ($expected, $present) = @_;
    my @problems;
    for my $pkg (sort keys %$expected) {
        my $pin = $expected->{$pkg};
        my $got = $present->{$pkg};
        if (!defined $got) {
            push @problems, "MISSING $pkg (manifest requires " . (defined($pin) ? $pin : '*') . ")";
            next;
        }
        push @problems, "VERSION $pkg: repo has $got, manifest pins $pin"
            unless version_matches($got, $pin);
    }
    return @problems;
}

# verify_repo_signature(\%expected, \%observed) -> @problems
#   %expected : unit => the expected signing-key identity (for Ubuntu the unit is the codename:
#               { focal => <key>, jammy => <key>, ... })
#   %observed : unit => the key that ACTUALLY signed the unit's metadata (the string the IO layer
#               extracts from gpg), or undef/'' when the unit is unsigned / verification failed
# Returns human-readable problem strings (empty list = every unit is signed by the expected key):
#   "UNSIGNED <unit> (expected <key>)"                       -- no valid signature at all
#   "WRONGKEY <unit>: signed by <observed>, expected <key>"  -- signed, but by a different key
# Pure: a string comparison only -- NO gpg call, no I/O (the IO layer runs gpg and passes %observed in).
# Deterministic (problems returned in sorted unit order).
sub verify_repo_signature {
    my ($expected, $observed) = @_;
    my @problems;
    for my $unit (sort keys %$expected) {
        my $exp = $expected->{$unit};
        my $obs = $observed->{$unit};
        if (!defined $obs || $obs eq '') {
            push @problems, "UNSIGNED $unit (expected $exp)";
            next;
        }
        push @problems, "WRONGKEY $unit: signed by $obs, expected $exp"
            unless $obs eq $exp;
    }
    return @problems;
}

# verify_repo_arches(\@expected, \%native) -> @problems
#   @expected : the architecture set the published repo is REQUIRED to serve. It comes from an
#               EXPLICIT claim -- --expect-arch, the staged arch set that was just promoted, or the
#               repo's own Release "Architectures:" line -- NEVER from "whichever binary-<arch>
#               directories happen to exist". That is the whole point: if the expected set were
#               inferred from presence, an entirely missing secondary architecture would read as
#               "this run did not build it" instead of "the repository is incomplete" (the false-PASS
#               the PR #63 review caught).
#   %native   : arch => boolean, "the published binary-<arch>/Packages carries at least one stanza
#               built FOR that arch" (index_has_native_arch) -- collected by the IO layer for every
#               arch it looked at, expected or not.
# Returns human-readable problem strings (empty list = the arch set is exactly right):
#   "MISSING-ARCH <a> (expected, but the published index carries no native <a> package)"
#   "UNEXPECTED-ARCH <a> (native <a> packages published, but <a> is not in the expected set <set>)"
# The UNEXPECTED direction matters too: it catches a stale architecture left behind in a tree that is
# no longer built for it. Pure: no I/O, deterministic (problems in sorted arch order).
sub verify_repo_arches {
    my ($expected, $native) = @_;
    my %want = map { $_ => 1 } @{ $expected || [] };
    my @problems;
    for my $a (sort keys %want) {
        push @problems, "MISSING-ARCH $a (expected, but the published index carries no native $a package)"
            unless $native->{$a};
    }
    for my $a (sort keys %$native) {
        next unless $native->{$a};
        next if $want{$a};
        push @problems, "UNEXPECTED-ARCH $a (native $a packages published, but $a is not in the "
                      . "expected set [" . join(' ', sort keys %want) . "])";
    }
    return @problems;
}

# parse_release_architectures($release_text) -> @arches
# The architecture set an apt Release file CLAIMS to serve (its "Architectures:" line), in file order
# and de-duplicated; an empty list when the field is absent. This is the repository's own published
# claim, so it is the right FALLBACK expected-arch set for a standalone verification of a tree whose
# build-time --expect-arch is not known: verifying a repo against what it advertises to apt clients
# catches "Release says amd64 ppc64el but binary-ppc64el is empty/missing". Pure: text in, list out.
sub parse_release_architectures {
    my ($text) = @_;
    return () unless defined $text;
    my ($line) = $text =~ /^Architectures:[ \t]*(.*?)[ \t]*$/m;
    return () unless defined $line;
    my (@a, %seen);
    for my $x (split /\s+/, $line) {
        next unless length $x;
        push @a, $x unless $seen{$x}++;
    }
    return @a;
}

# parse_packages_index($text) -> \%{ package_name => version }
# Parse a Debian 'Packages' index: RFC822 stanzas separated by blank line(s); each carries a
# 'Package:' and a 'Version:'. Returns name => version (the FULL Debian version verbatim, epoch +
# revision included -- which is exactly what the manifest pin is compared against). A stanza
# lacking either field is skipped; malformed/empty input yields an empty hash.
# DUPLICATE = LOUD ERROR: apt-ftparchive emits one stanza per package, so a name appearing twice with
# DISTINCT versions means a stale .deb was not cleaned from the pool before assemble -- a version pin
# could then pass against the wrong .deb and both could ship. This dies (mirroring the EL rpm_version
# behaviour), so EL and Ubuntu AGREE: a duplicate is always a hard failure, never a silent keep-one.
# (An identical repeated version is harmless and kept.)
sub parse_packages_index {
    my ($text) = @_;
    my %map;
    return \%map unless defined $text && $text ne '';
    for my $stanza (split /\n\n+/, $text) {
        next unless $stanza =~ /\S/;
        my ($name) = $stanza =~ /^Package:[ \t]*(\S+)/m;
        my ($ver)  = $stanza =~ /^Version:[ \t]*(\S+)/m;
        next unless defined $name && defined $ver;
        die "FATAL: duplicate package '$name' in the Packages index with distinct versions "
          . "'$map{$name}' and '$ver' (stale artifact not cleaned before assemble)\n"
            if exists $map{$name} && $map{$name} ne $ver;
        $map{$name} = $ver;
    }
    return \%map;
}

# index_has_native_arch($packages_text, $arch): true iff the Packages index has at least one stanza
# built FOR that arch (Architecture: <arch>), as opposed to only Architecture:all debs (grub2-xcat,
# genesis) which EVERY binary-<arch> index carries. This lets the verify gate distinguish "this arch
# was actually built" from "this arch's index merely inherited the arch:all debs" -- so a genuine
# single-arch run (BUILD_PPC=false: amd64 natives + arch:all only) is not mistaken for a two-arch
# repo and made to demand native ppc deps it never built. Pure: text in, boolean out.
sub index_has_native_arch {
    my ($text, $arch) = @_;
    return 0 unless defined $text && defined $arch && $arch ne '';
    for my $stanza (split /\n\n+/, $text) {
        return 1 if $stanza =~ /^Architecture:[ \t]*\Q$arch\E[ \t]*$/m;
    }
    return 0;
}

# control_binary_arch($control_text, $binpkg): the Architecture field of the BINARY package $binpkg in
# a debian/control (a source may declare several binary packages). Returns the field value verbatim --
# 'all', 'any', or a space-separated arch list ('i386 amd64 ia64 ppc64el') -- or undef if that
# package/field is absent. Lets the builder tell an arch:all single-producer package (built once on
# amd64 -- e.g. syslinux-xcat/grub2-xcat, whose source is x86-only) from a genuinely per-arch one, so
# it is not rebuilt on ppc. Pure: text in, string out.
sub control_binary_arch {
    my ($text, $binpkg) = @_;
    return undef unless defined $text && defined $binpkg && $binpkg ne '';
    for my $para (split /\n\n+/, $text) {
        my ($p) = $para =~ /^Package:[ \t]*(\S+)/m;
        next unless defined $p && $p eq $binpkg;
        my ($a) = $para =~ /^Architecture:[ \t]*(.+?)[ \t]*$/m;   # full value (may be a space list)
        return $a;   # undef if this paragraph lacks an Architecture field
    }
    return undef;
}

# skip_arch_all_on($control_text, $binpkg, $arch): true iff $binpkg is an Architecture:all
# single-producer package (built ONCE on amd64) and $arch is NOT amd64 -- so it must be neither BUILT
# nor per-arch VALIDATED on $arch (it arrives from the amd64 producer; its presence on $arch is checked
# later against the PUBLISHED index by verify_assembled_repo). The single source of truth shared by
# build_one_codename and validate_manifest, so a package the build skips is never demanded by the
# per-arch validation. Pure: control text in, boolean out.
sub skip_arch_all_on {
    my ($control_text, $binpkg, $arch) = @_;
    return 0 if !defined $arch || $arch eq 'amd64';
    return ((control_binary_arch($control_text, $binpkg) // '') eq 'all') ? 1 : 0;
}

# resolve_present_names(\%parsed, $arch, \@names) -> \%present  (name => FULL version | undef)
# PURE. Resolves each manifest package NAME to the version actually in the parsed index (\%parsed from
# parse_packages_index), returning the FULL Debian version -- [epoch:]upstream[-revision], verbatim --
# because that is what the manifest pins. Comparing only the upstream part would accept a package with
# the right upstream version but the wrong epoch or a stale packaging revision, which is exactly what
# xCAT's own versioned Depends (goconserver >= 0.3.3-snap..., ipmitool-xcat >= 1.8.17-1) care about.
# Resolution order:
#   - exact index key (e.g. ipmitool-xcat), else
#   - the arch-suffixed key for THIS cell's arch (e.g. xcat-genesis-base -> xcat-genesis-base-<arch>).
# It deliberately does NOT fall back to a DIFFERENT-arch suffix: the xcat-genesis-base-<arch> debs are
# Architecture:all and appear in EVERY arch's binary index, so an alphabetical prefix match would
# resolve the ppc64el cell to xcat-genesis-base-amd64 and MASK a missing native ppc genesis (#7610).
sub resolve_present_names {
    my ($parsed, $arch, $names) = @_;
    my %present;
    for my $name (@$names) {
        my $full;
        if    (exists $parsed->{$name})            { $full = $parsed->{$name}; }
        elsif (exists $parsed->{"$name-$arch"})    { $full = $parsed->{"$name-$arch"}; }
        $present{$name} = $full;
    }
    return \%present;
}

# ---------------------------------------------------------------------------------------------------
# Chroot provisioning helpers (absorbed from mk-dep-chroots.sh; sbuild-all.pl auto-inits on first run).
# ---------------------------------------------------------------------------------------------------

# chroot_name: the schroot session name for a (codename, arch) — "<codename>-<arch>-sbuild".
sub chroot_name {
    my ($codename, $arch) = @_;
    return "$codename-$arch-sbuild";
}

# chroot_sources_list: the apt sources.list body for a freshly bootstrapped chroot. main + universe
# (+ updates/security) so build-deps that live in universe (quilt, ...) resolve — sbuild-createchroot's
# default is main-only, which makes every build fail on `quilt`. Pure/testable; $mirror defaults to a
# fast BR mirror because archive.ubuntu.com times out from the build hosts.
sub chroot_sources_list {
    my ($mirror, $codename) = @_;
    $mirror   ||= 'http://br.archive.ubuntu.com/ubuntu';
    die "chroot_sources_list: codename required\n" if !defined $codename || $codename eq '';
    return join('', map { "$_\n" }
        "deb $mirror $codename main universe",
        "deb $mirror $codename-updates main universe",
        "deb $mirror $codename-security main universe",
    );
}

# chroot_is_disposable($schroot_config_text): true iff a `schroot -c <name> -- ...` session against
# this chroot gets a THROWAWAY filesystem -- i.e. everything the build installs or writes is discarded
# when the session ends, so the NEXT package starts from the pristine base.
#
# This is the load-bearing precondition of the per-package build (PR #63 review concern #2): the
# per-codename chroots are long-lived and shared by all seven packages, so without a disposable
# session, package N's build-dependencies stay installed for package N+1 -- and a package whose
# debian/control forgets a Build-Depends builds anyway, silently, because a sibling happened to pull
# the dependency in. Making dependency installation fatal is only half the fix; it means nothing if a
# stale environment can satisfy an undeclared dependency in the first place.
#
# Disposable configurations, per schroot(1):
#   * union-type = overlay | overlayfs | aufs | unionfs   -- a per-session union mount over the base
#     directory; writes go to the (discarded) overlay. This is what sbuild-createchroot sets up.
#   * type = file                                          -- the session unpacks a fresh tarball.
#   * type = {btrfs,lvm,zfs}-snapshot                      -- the session gets its own snapshot.
# A plain `type=directory` with `union-type=none` is NOT disposable: the session bind-mounts the base
# directory read-write and every build mutates it permanently.
# Pure: `schroot --config -c <name>` text in, boolean out.
sub chroot_is_disposable {
    my ($config_text) = @_;
    return 0 unless defined $config_text && $config_text ne '';
    my ($union) = $config_text =~ /^union-type=[ \t]*(\S+)/m;
    return 1 if defined $union && $union =~ /^(?:overlay|overlayfs|aufs|unionfs)$/;
    my ($type) = $config_text =~ /^type=[ \t]*(\S+)/m;
    return 1 if defined $type && $type =~ /^(?:file|btrfs-snapshot|lvm-snapshot|zfs-snapshot)$/;
    return 0;
}

# ---------------------------------------------------------------------------------------------------
# Debian control-metadata helpers (concern #2: preserve the maintained packaging's semantics).
# ---------------------------------------------------------------------------------------------------

# control_field: extract a field's value from a Debian control paragraph text (the binary Package:
# paragraph, or a DEBIAN/control). Returns the value with continuation lines folded to single spaces,
# or undef if absent. Pure/testable. Used to lift Depends/Breaks/Replaces/Maintainer from the
# maintained xCAT-genesis-builder/debian/control so the rpm->deb genesis shim keeps them.
sub control_field {
    my ($text, $field) = @_;
    return undef unless defined $text && defined $field;
    for my $para (split /\n\n+/, $text) {
        if ($para =~ /^\Q$field\E:[ \t]*(.*(?:\n[ \t]+.*)*)/mi) {
            my $v = $1;
            $v =~ s/\n[ \t]+/ /g;   # fold continuation lines
            $v =~ s/\s+$//;
            return $v;
        }
    }
    return undef;
}

# genesis_deb_control: build the DEBIAN/control text for the cross-arch-converted xcat-genesis-base
# deb, PRESERVING the maintained packaging's semantics (Depends/Breaks/Replaces/Section/Priority)
# instead of hand-rolling a bare 5-field control (the bug in build-dep-debs.sh flagged by review
# concern #2). $maintained is the text of xCAT-genesis-builder/debian/control (or undef when it
# cannot be located — then a minimal-but-honest control is produced and the caller should warn).
# $pkgname is e.g. xcat-genesis-base-ppc64el, $version the deb version, $arch 'all'. Pure/testable.
sub genesis_deb_control {
    my ($maintained, $pkgname, $version, $arch) = @_;
    $arch ||= 'all';
    my %f = (
        Package      => $pkgname,
        Version      => $version,
        Architecture => $arch,
        Section      => 'admin',
        Priority     => 'optional',
        Maintainer   => 'xCAT <xcat-user@lists.sourceforge.net>',
    );
    if (defined $maintained && $maintained ne '') {
        for my $k (qw(Section Priority Maintainer Depends Pre-Depends Recommends
                      Suggests Breaks Replaces Conflicts Provides)) {
            my $v = control_field($maintained, $k);
            $f{$k} = $v if defined $v && $v ne '';
        }
        my $desc = control_field($maintained, 'Description');
        $f{Description} = $desc if defined $desc && $desc ne '';
    }
    $f{Description} ||= 'xCAT Genesis netboot image (converted from the rpm for cross-arch netboot)';
    # ${misc:Depends} is a debhelper substitution var that only resolves during a real dpkg build;
    # in a hand-assembled control it would ship literally, so drop it from a preserved Depends.
    for my $k (qw(Depends Pre-Depends Recommends Suggests)) {
        next unless defined $f{$k};
        $f{$k} =~ s/\$\{[^}]+\}//g;
        $f{$k} =~ s/^[,\s]+|[,\s]+$//g;
        $f{$k} =~ s/\s*,\s*,\s*/, /g;
        delete $f{$k} if $f{$k} eq '';
    }
    my @order = qw(Package Version Section Priority Architecture Maintainer
                   Pre-Depends Depends Recommends Suggests Breaks Replaces Conflicts
                   Provides Description);
    my $out = '';
    for my $k (@order) {
        next unless defined $f{$k} && $f{$k} ne '';
        $out .= "$k: $f{$k}\n";
    }
    return $out;
}

# ---------------------------------------------------------------------------------------------------
# Built-.deb inspection + cross-arch genesis provisioning (filesystem; tested with real dpkg-deb).
# ---------------------------------------------------------------------------------------------------

# deb_field: a control field of a built .deb via `dpkg-deb -f`. Returns '' on error/missing.
sub deb_field {
    my ($deb, $field) = @_;
    return '' unless defined $deb && -f $deb && defined $field;
    my $v = `dpkg-deb -f ${\ sh_quote($deb)} ${\ sh_quote($field)} 2>/dev/null`;
    chomp $v if defined $v;
    return defined $v ? $v : '';
}

# deb_version: the FULL Version ([epoch:]upstream[-revision]) of the built binary .deb named
# <pkg>_*.deb under $dir (undef if absent) -- the same string the published index carries, so
# build-time validation and publish-time verification compare like with like against the manifest pin.
# $pkg is the binary package name (e.g. 'ipmitool-xcat', 'goconserver') or the logical
# 'xcat-genesis-base'.
#
# $arch (optional) disambiguates that logical name: the genesis debs are arch-SUFFIXED
# (xcat-genesis-base-amd64 / -ppc64el) and are legitimately built from two DIFFERENT genesis rpms, so
# their revisions differ (2.19.0-snap202607261133 vs ...271832). On the amd64 host both are staged
# (the cross-arch ppc one for #7610), so without $arch the two would look like a version conflict.
# Pass the target arch and only that arch's genesis is considered -- matching resolve_present_names,
# which likewise never borrows another arch's genesis.
#
# Dies if the dir holds more than one DISTINCT version of the package (a stale artifact not cleaned
# before the build -- a version pin could otherwise pass against the wrong deb and both could ship).
# Mirrors MockBuildUtils::rpm_version.
sub deb_version {
    my ($dir, $pkg, $arch) = @_;
    my $is_genesis = ($pkg eq 'xcat-genesis-base');
    my $glob = $is_genesis
        ? ((defined $arch && $arch ne '') ? "$dir/xcat-genesis-base-$arch\_*.deb"
                                          : "$dir/xcat-genesis-base-*_*.deb")
        : "$dir/${pkg}_*.deb";
    my %vers;
    for my $f (sort glob($glob)) {
        my $n = deb_field($f, 'Package');
        my $match = $is_genesis
            ? ($n =~ /^xcat-genesis-base-/
               && (!defined $arch || $arch eq '' || $n eq "xcat-genesis-base-$arch"))
            : ($n eq $pkg);
        next unless $match;
        my $v = deb_field($f, 'Version');
        $vers{$v} = 1 if defined $v && $v ne '';
    }
    return undef unless %vers;
    die "Multiple versions of $pkg present in $dir: " . join(', ', sort keys %vers)
      . " (stale artifact not cleaned before the build)\n" if keys(%vers) > 1;
    my ($v) = keys %vers;
    return $v;
}

# deb_hash: content identity of a .deb (md5 of the file bytes). A .deb is an `ar` archive whose
# member order/timestamps are build-stable enough that a byte hash is a sound identity for the
# cross-copy idempotency check (two same-named debs with different content hash differently).
sub deb_hash {
    my ($f) = @_;
    return '' unless defined $f && -f $f;
    open my $fh, '<', $f or return '';
    binmode $fh;
    my $d = Digest::MD5->new->addfile($fh)->hexdigest;
    close $fh;
    return $d;
}

# cross_copy_genesis_deb: copy the Architecture:all xcat-genesis-base-<arch>_*.deb from $from into
# $to, dropping any stale same-arch genesis already in $to so the dir ends with exactly the fresh
# set. Returns the count newly copied (0 = already up to date, so the caller can skip re-indexing).
# Idempotent; content is compared by deb_hash so a stale same-name deb is refreshed rather than
# mistaken for up to date. $sign is an optional coderef($deb_path) invoked on each copied deb; pass
# undef to skip. Mirrors MockBuildUtils::cross_copy_genesis for the apt world.
sub cross_copy_genesis_deb {
    my ($from, $to, $arch, $sign) = @_;
    my @src = glob("$from/xcat-genesis-base-$arch\_*.deb");
    return 0 if !@src;
    my %want = map { basename($_) => $_ } @src;
    my @existing = glob("$to/xcat-genesis-base-$arch\_*.deb");
    if (scalar(@existing) == scalar(keys %want)) {
        my $up_to_date = 1;
        for my $base (keys %want) {
            my $dst = "$to/$base";
            my $src_hash = deb_hash($want{$base});
            if (!-f $dst || $src_hash eq '' || $src_hash ne deb_hash($dst)) { $up_to_date = 0; last; }
        }
        return 0 if $up_to_date;
    }
    for my $old (@existing) {
        unlink $old or die "Failed to remove stale genesis $old: $!\n";
    }
    my $copied = 0;
    for my $base (sort keys %want) {
        copy($want{$base}, "$to/$base")
            or die "Failed to cross-copy genesis $want{$base} -> $to: $!\n";
        $sign->("$to/$base") if $sign;
        $copied++;
    }
    return $copied;
}

# ---------------------------------------------------------------------------------------------------
# Per-package build orchestration (shared by every <dep>/sbuild.pl; the deb analogue of what
# MockBuildUtils' helpers do for the per-package mockbuild.pl builders).
# ---------------------------------------------------------------------------------------------------

# chroot_build_script: the bash program that runs INSIDE the per-package schroot session. Returned as
# text (pure) so t/sbuild-all.t can assert its fail-hard properties without a chroot.
#
# Fail-hard contract (PR #63 review concern #2) -- every step below is FATAL, none is best-effort:
#   * `set -euo pipefail`: any unchecked command failure aborts the build.
#   * apt-get update / the common build tooling install are retried (transient mirror hiccups) and
#     then FATAL. They used to end in `|| true`, which let a package build with, say, no `quilt` and
#     produce a silently-wrong .deb.
#   * Build-Depends are installed with `mk-build-deps` (devscripts + equivs) instead of a sed
#     extraction, and a failure is FATAL. mk-build-deps feeds the control file's relationships to apt
#     verbatim, so version constraints `(>= 12)`, alternatives `a | b` and arch qualifiers `[!ppc64el]`
#     are honoured -- the sed pipeline dropped all three, and, paired with the swallowed error, a
#     too-old or missing build dependency produced a green build.
# The build environment is disposable: the caller asserts the chroot gives each session a throwaway
# overlay/snapshot (chroot_is_disposable), so nothing this script installs can leak into the next
# package's build and satisfy an undeclared dependency.
sub chroot_build_script {
    return <<'INNER';
set -euo pipefail
PKGSRC="$1"; OUT="$2"; SDE="$3"; EXTRA="$4"; B64="$5"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=nocheck SOURCE_DATE_EPOCH="$SDE"

# apt_retry: run apt-get, retrying a few times for a transient mirror/network hiccup, then FATAL.
apt_retry() {
    local i
    for i in 1 2 3; do
        if apt-get "$@"; then return 0; fi
        echo "[warn] 'apt-get $*' failed (attempt $i/3); retrying in 5s" >&2
        sleep 5
    done
    echo "FATAL: 'apt-get $*' failed after 3 attempts" >&2
    return 1
}

apt_retry update -q
# Common build tooling. FATAL: a missing tool silently changes what gets built.
# shellcheck disable=SC2086  # $EXTRA is a deliberate word-split package list
apt_retry install -y --no-install-recommends \
    git wget curl ca-certificates devscripts equivs quilt fakeroot build-essential $EXTRA

W=$(mktemp -d)
cp -a "$PKGSRC" "$W/pkg"
cd "$W/pkg"

# Some package directories carry PREBUILT .deb files in the checkout (elilo/ ships
# elilo-xcat_3.14-5_all.deb and gnu-efi_3.0v-5_amd64.deb). Those arrive with the copied source tree
# and are NOT output of this build -- collecting them republishes a stale, unrelated artifact under
# this run's name. Record what is already present so the collector can subtract it. A file the build
# OVERWRITES (elilo-xcat_3.14-6_all.deb) changes size/mtime, so it still counts as build output.
find "$W" -maxdepth 3 -name '*.deb' -printf '%s %T@ %p\n' | sort > "$W/.debs-before"

# Declared Build-Depends, resolved by mk-build-deps: it hands debian/control's relationships to apt
# verbatim, so versions/alternatives/arch-qualifiers are honoured. FATAL on failure -- an unsatisfied
# build dependency must stop the build, never be papered over by whatever the chroot already carries.
if [ -f debian/control ]; then
    echo "== installing Build-Depends from debian/control (mk-build-deps) =="
    # Retried like every other apt operation here, and for the same reason: a suite that moves under
    # us (resolute rolling openssl, say) leaves the index naming a version the pool has already
    # dropped, and the fetch 404s. Refreshing the index between attempts is what fixes that, so the
    # retry does exactly that. Still FATAL once the attempts are spent -- a package must never build
    # against whatever the chroot happens to carry.
    attempt=1
    while :; do
        if mk-build-deps --install --remove \
            --tool 'apt-get -y --no-install-recommends' debian/control; then
            break
        fi
        if [ "$attempt" -ge 3 ]; then
            echo "FATAL: mk-build-deps failed after $attempt attempts" >&2
            exit 1
        fi
        echo "[retry] dependency installation failed (attempt $attempt/3); refreshing the index" >&2
        apt_retry update -q
        sleep 5
        attempt=$((attempt + 1))
    done
fi

printf '%s' "$B64" | base64 -d > "$W/pkgbuild.sh"
( cd "$W/pkg" && bash "$W/pkgbuild.sh" )

# Collect ONLY what this build produced: everything that is new or changed since the snapshot taken
# before the build. Prebuilt debs that came in with the checkout are subtracted, and the mk-build-deps
# dummy package (<src>-build-deps_*.deb) and debug symbols are excluded outright -- none of the three
# is build output, and none may reach the repo.
find "$W" -maxdepth 3 -name '*.deb' ! -name '*-dbgsym_*' ! -name '*-build-deps_*' \
    -printf '%s %T@ %p\n' | sort > "$W/.debs-after"
mapfile -t found < <(comm -13 "$W/.debs-before" "$W/.debs-after" | sed 's/^[^ ]* [^ ]* //')
if [ "${#found[@]}" -eq 0 ]; then
    echo "FATAL: the package build produced no .deb (only prebuilt artifacts from the checkout)" >&2
    exit 1
fi
comm -12 "$W/.debs-before" "$W/.debs-after" | sed 's/^[^ ]* [^ ]* //' \
    | while read -r f; do echo "prebuilt in the checkout, NOT collected: $f"; done
mkdir -p "$OUT"
for d in "${found[@]}"; do cp -v "$d" "$OUT/"; done
INNER
}

# build_deb_in_chroot: build ONE package inside its <codename>-<arch>-sbuild chroot and collect the
# produced .deb(s) into $result_dir. The COMMON orchestration lives here -- a disposable schroot
# session, apt update, install of common tools + the package's debian/control Build-Depends, an
# OUT-OF-TREE copy of the package dir (the checkout is never mutated), SOURCE_DATE_EPOCH for
# reproducible builds, deb collection, and a host-side check that the debs actually landed (a
# chroot-local --result-dir would otherwise be a silent no-output). Each <dep>/sbuild.pl supplies
# only its package-specific $build snippet (the source prep + dpkg-buildpackage that used to live in
# make_deb.sh); $build runs with CWD = the copied package dir and must leave its .deb(s) somewhere
# under the build work tree. Dies on any failure -- including a chroot that is not disposable.
#   %args: pkg, chroot, pkg_dir, result_dir, build_timestamp, build (required); extra_tools (arrayref, optional)
# chroot_build_timeout($chroot): the wall-clock budget for one build in $chroot. The chroot is named
# <codename>-<arch>-sbuild, so its arch says whether the build is native or runs through qemu-user.
# XCAT_DEP_BUILD_TIMEOUT overrides it; sbuild-all.pl --build-timeout sets that variable, because the
# per-package <dep>/sbuild.pl builders are separate processes with their own CLI. 0 disables the bound.
sub chroot_build_timeout {
    my ($chroot) = @_;
    return int($ENV{XCAT_DEP_BUILD_TIMEOUT}) if defined $ENV{XCAT_DEP_BUILD_TIMEOUT}
                                             && $ENV{XCAT_DEP_BUILD_TIMEOUT} =~ /^\d+$/;
    my ($target_arch) = (($chroot // '') =~ /^.+-([^-]+)-sbuild$/);
    my $host_arch = `dpkg --print-architecture 2>/dev/null`;
    chomp $host_arch;
    return emulated_build_timeout($target_arch, $host_arch);
}

sub build_deb_in_chroot {
    my (%a) = @_;
    defined $a{$_} or die "build_deb_in_chroot: missing '$_'\n"
        for qw(pkg chroot pkg_dir result_dir build_timestamp build);
    my $pkg = $a{pkg};
    die "FATAL: chroot $a{chroot} missing (run sbuild-all.pl to auto-init it)\n"
        if system("schroot -l 2>/dev/null | grep -qx chroot:$a{chroot}") != 0;
    # HARD precondition: each package must build in a CLEAN, throwaway environment. A shared
    # `type=directory` chroot with no union mount would carry the previous package's build-deps into
    # this one, so an undeclared Build-Depends would build green here and fail for everyone else.
    my $cfg = `schroot --config -c ${\ sh_quote($a{chroot}) } 2>/dev/null` // '';
    die "FATAL: chroot $a{chroot} is NOT disposable -- a schroot session against it would mutate the\n"
      . "  shared base filesystem, so one package's build-dependencies would leak into the next and\n"
      . "  hide a missing Build-Depends. Add 'union-type=overlay' to its /etc/schroot/chroot.d/ entry\n"
      . "  (or delete the chroot and let sbuild-all.pl re-create it).\n"
        unless chroot_is_disposable($cfg);
    make_path($a{result_dir});
    my $extra = join(' ', @{ $a{extra_tools} || [] });
    my $b64   = encode_base64($a{build}, '');

    # The whole per-package build runs in ONE disposable schroot session. schroot SANITIZES the
    # environment, so values are passed as POSITIONAL ARGS to the inner bash; the package-specific
    # build is passed base64-encoded to avoid any quoting interplay through schroot.
    my $inner = chroot_build_script();

    my $cmd = 'schroot -c ' . sh_quote($a{chroot}) . ' -u root -d / -- bash -c '
            . sh_quote($inner) . ' bash '
            . sh_quote($a{pkg_dir}) . ' ' . sh_quote($a{result_dir}) . ' '
            . sh_quote($a{build_timestamp}) . ' ' . sh_quote($extra) . ' ' . sh_quote($b64);
    print "[$pkg] building in chroot $a{chroot} -> $a{result_dir} (SOURCE_DATE_EPOCH=$a{build_timestamp})\n";
    # A build that deadlocks under qemu-user (a resolute goconserver `go build` did, with both Go
    # pids in futex_wait and no CPU ticks at all) used to hang here forever, and a hung cell reads as
    # "still running" rather than as a defect. Bound it, and print the process tree, each wchan and a
    # CPU sample before the kill, so the failure says WHY it stopped.
    my $timeout = defined $a{timeout} ? $a{timeout} : chroot_build_timeout($a{chroot});
    my $r = run_bounded(cmd => $cmd, timeout => $timeout, label => "[$pkg] build in $a{chroot}",
                        out => \*STDOUT);
    die "[$pkg] build TIMED OUT after $r->{elapsed}s (budget ${timeout}s) -- see the stall report above\n"
        if $r->{timed_out};
    my $ec = $r->{ec};
    die "[$pkg] build failed (rc=$ec)\n" if $ec != 0;
    # The debs were copied from INSIDE the chroot; that only reaches the host if --result-dir is on a
    # bind-mounted path. Verify host-side so a mis-configured (chroot-local) result-dir fails LOUD.
    my @debs = glob("$a{result_dir}/*.deb");
    die "[$pkg] build succeeded in the chroot but no .deb is visible at $a{result_dir} on the host\n"
      . "  (is --result-dir on a path bind-mounted into the chroot, e.g. under /opt/xcat-ci-shared?)\n"
      unless @debs;
    print "[$pkg] OK (" . scalar(@debs) . " deb(s) in $a{result_dir})\n";
    return scalar @debs;
}

1;
