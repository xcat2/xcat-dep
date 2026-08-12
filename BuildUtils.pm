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
use File::Basename qw(basename);
use File::Copy qw(copy);
use File::Path qw(make_path);
use Digest::MD5;
use MIME::Base64 qw(encode_base64);

our @EXPORT_OK = qw(
    sh_quote print_step
    version_matches required_pkgs read_manifest standard_options
    codename_to_version version_to_codename known_codenames
    chroot_name chroot_sources_list
    control_field genesis_deb_control
    deb_field deb_version deb_upstream_version deb_hash cross_copy_genesis_deb
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
sub codename_to_version { my ($c) = @_; return $CODENAME_TO_VERSION{$c // ''}; }
sub version_to_codename { my ($v) = @_; return $VERSION_TO_CODENAME{$v // ''}; }

# ---------------------------------------------------------------------------------------------------
# Shared / format-agnostic helpers (identical semantics to MockBuildUtils.pm; see migration note).
# ---------------------------------------------------------------------------------------------------

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
        finalize-xcat-dep! force-unlock!
        dry-run!
    );
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

# deb_upstream_version: the UPSTREAM part of a Debian version — strip a leading "epoch:" and the
# trailing "-<debian_revision>" (dpkg splits the revision at the LAST dash). So '1.8.18-4' -> '1.8.18',
# '2:0.3.3-snap202608101400.57' -> '0.3.3'. This is what the manifest pins (the Release/revision
# carries the codename/snap stamp and is intentionally NOT pinned), mirroring EL rpm_version's %{version}.
sub deb_upstream_version {
    my ($v) = @_;
    return $v unless defined $v;
    $v =~ s/^\d+://;        # drop epoch
    $v =~ s/-[^-]*$//;      # drop the last -revision segment
    return $v;
}

# deb_version: the UPSTREAM Version of the built binary .deb named <pkg>_*.deb under $dir (undef if
# absent). $pkg is the binary package name (e.g. 'ipmitool-xcat', 'goconserver', or the logical
# 'xcat-genesis-base' which matches the arch-suffixed xcat-genesis-base-amd64/-ppc64el). Dies if the
# dir holds more than one DISTINCT upstream version of the package (a stale artifact not cleaned
# before the build — a version pin could otherwise pass against the wrong deb and both could ship).
# Mirrors MockBuildUtils::rpm_version.
sub deb_version {
    my ($dir, $pkg) = @_;
    my $glob = ($pkg eq 'xcat-genesis-base')
        ? "$dir/xcat-genesis-base-*_*.deb"
        : "$dir/${pkg}_*.deb";
    my %vers;
    for my $f (sort glob($glob)) {
        my $n = deb_field($f, 'Package');
        my $match = ($pkg eq 'xcat-genesis-base')
            ? ($n =~ /^xcat-genesis-base-/) : ($n eq $pkg);
        next unless $match;
        my $v = deb_upstream_version(deb_field($f, 'Version'));
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

# build_deb_in_chroot: build ONE package inside its <codename>-<arch>-sbuild chroot and collect the
# produced .deb(s) into $result_dir. The COMMON orchestration lives here -- an ephemeral schroot
# session, apt update, install of common tools + the package's debian/control Build-Depends, an
# OUT-OF-TREE copy of the package dir (the checkout is never mutated), SOURCE_DATE_EPOCH for
# reproducible builds, deb collection, and a host-side check that the debs actually landed (a
# chroot-local --result-dir would otherwise be a silent no-output). Each <dep>/sbuild.pl supplies
# only its package-specific $build snippet (the source prep + dpkg-buildpackage that used to live in
# make_deb.sh); $build runs with CWD = the copied package dir and must leave its .deb(s) somewhere
# under the build work tree. Dies on any failure.
#   %args: pkg, chroot, pkg_dir, result_dir, build_timestamp, build (required); extra_tools (arrayref, optional)
sub build_deb_in_chroot {
    my (%a) = @_;
    defined $a{$_} or die "build_deb_in_chroot: missing '$_'\n"
        for qw(pkg chroot pkg_dir result_dir build_timestamp build);
    my $pkg = $a{pkg};
    die "FATAL: chroot $a{chroot} missing (run sbuild-all.pl to auto-init it)\n"
        if system("schroot -l 2>/dev/null | grep -qx chroot:$a{chroot}") != 0;
    make_path($a{result_dir});
    my $extra = join(' ', @{ $a{extra_tools} || [] });
    my $b64   = encode_base64($a{build}, '');

    # The whole per-package build runs in ONE schroot session (ephemeral overlay). schroot SANITIZES
    # the environment, so values are passed as POSITIONAL ARGS to the inner bash; the package-specific
    # build is passed base64-encoded to avoid any quoting interplay through schroot.
    my $inner = <<'INNER';
set -uo pipefail
PKGSRC="$1"; OUT="$2"; SDE="$3"; EXTRA="$4"; B64="$5"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=nocheck SOURCE_DATE_EPOCH="$SDE"
for t in 1 2 3; do apt-get update -q && break; sleep 5; done
apt-get install -y --no-install-recommends \
    git wget curl ca-certificates devscripts quilt fakeroot build-essential $EXTRA >/dev/null 2>&1 || true
W=$(mktemp -d); cp -a "$PKGSRC" "$W/pkg"; cd "$W/pkg"
if [ -f debian/control ]; then
  BD=$(sed -n '/^Build-Depends:/,/^\S/p' debian/control | tr ',' '\n' \
       | sed -E 's/^Build-Depends://; s/\(.*\)//; s/\[.*\]//; s/[[:space:]]//g' \
       | grep -E '^[a-z0-9]' | grep -v '^debhelper-compat' | sort -u | tr '\n' ' ')
  [ -n "$BD" ] && { apt-get install -y $BD >/dev/null 2>&1 || echo "[warn] some build-deps failed to install"; }
fi
printf '%s' "$B64" | base64 -d > "$W/pkgbuild.sh"
( cd "$W/pkg" && bash "$W/pkgbuild.sh" ) || { echo "package build FAILED"; exit 1; }
found=$(find "$W" -maxdepth 3 -name '*.deb' ! -name '*-dbgsym_*' -print)
[ -n "$found" ] || { echo "build produced no .deb"; exit 1; }
mkdir -p "$OUT"; echo "$found" | while read -r d; do cp -v "$d" "$OUT/"; done
INNER

    my $cmd = 'schroot -c ' . sh_quote($a{chroot}) . ' -u root -d / -- bash -c '
            . sh_quote($inner) . ' bash '
            . sh_quote($a{pkg_dir}) . ' ' . sh_quote($a{result_dir}) . ' '
            . sh_quote($a{build_timestamp}) . ' ' . sh_quote($extra) . ' ' . sh_quote($b64);
    print "[$pkg] building in chroot $a{chroot} -> $a{result_dir} (SOURCE_DATE_EPOCH=$a{build_timestamp})\n";
    my $rc = system('bash', '-c', $cmd);
    my $ec = $rc == -1 ? -1 : ($rc >> 8);
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
