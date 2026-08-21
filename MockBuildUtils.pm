package MockBuildUtils;
# Reusable, unit-testable helpers factored out of mockbuild-all.pl. Kept free of that script's
# globals so t/mockbuild-all.t can exercise them directly. The two orchestration helpers that
# need signing / re-indexing (cross_copy_genesis, finalize_xcat_dep) take those as injected
# callbacks instead of reaching for gpg/createrepo state, so they stay pure and testable.
use strict;
use warnings;
use Exporter 'import';
use File::Basename qw(basename);
use File::Copy qw(copy);
use File::Find;
use Sys::Hostname;
use Digest::MD5 qw(md5_hex);

our @EXPORT_OK = qw(
    sh_quote print_step
    version_matches required_pkgs have_rpm read_manifest
    verify_repo_packages verify_repo_signature verify_rpm_signatures
    parse_evr evr_cmp evr_constraint_ok parse_pin rpmkeys_checksig_problem
    rpm_version rpm_release rpm_sigmd5 rpm_is_signed restamp_release_line
    cross_copy_genesis finalize_xcat_dep bump_dep_release_suffix
    build_mock_uniqueext
);

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
# exact version (2.19.0), a shell-style glob (2.*  or  2.19.*), or '*' (any). Globs support * and
# ? and are anchored. Used so xCAT-genesis-base can pin 2.* (its Version walks with xcat-core)
# while the real xcat-dep packages stay exactly pinned.
sub version_matches {
    my ($got, $want) = @_;
    return 1 if !defined($want) || $want eq '*';
    return ($got eq $want) unless $want =~ /[*?]/;
    my $re = quotemeta($want);
    $re =~ s/\\\*/.*/g;
    $re =~ s/\\\?/./g;
    return $got =~ /\A$re\z/ ? 1 : 0;
}

# required_pkgs: given a list of manifest package names and the skip flags, return the subset
# that must actually be built and validated. A package whose builder was skipped is NOT required:
# --skip-genesis drops xCAT-genesis-base, --skip-perl drops perl-*, --skip-xcat-dep drops the dep
# builders (everything that is neither genesis nor perl). Pure function (flags passed in) so both
# the version-pin check and assert_required_deps use it and it is unit-testable.
sub required_pkgs {
    my ($pkgs, $skip_genesis, $skip_perl, $skip_dep) = @_;
    return grep {
           !($skip_genesis && $_ eq 'xCAT-genesis-base')
        && !($skip_perl    && /^perl-/)
        && !($skip_dep     && $_ ne 'xCAT-genesis-base' && $_ !~ /^perl-/)
    } @$pkgs;
}

# verify_repo_packages: the PURE completeness-decision layer of the repo gate. Given the manifest's
# %expected { pkg => version-pin } and the %present { pkg => version-found-or-undef } actually in a
# built repo, return a list of human-readable problem strings (empty list = every package present at
# its pin):
#   "MISSING <pkg> (manifest requires <pin>)"              when %present has no (defined) version for <pkg>
#   "VERSION <pkg>: repo has <got>, manifest pins <pin>"   when present but !version_matches(got, pin)
# Uses version_matches (same semantics as the in-line manifest pin loop), so a '*' or glob pin is
# accepted exactly as there. No file/manifest I/O here -- the disk layer builds %present and passes
# both hashes in, keeping this unit-testable in isolation.
# parse_evr($s): split an EVR string "[epoch:]version[-release]" into ($epoch, $version, $release).
# epoch defaults to '0' when absent or '(none)'; release is undef when the string carries none (so a
# release-less constraint compares version-only). Neither version nor release may contain '-', so the
# single '-' cleanly separates them.
sub parse_evr {
    my ($s) = @_;
    $s = '' unless defined $s;
    my ($epoch, $rest);
    if ($s =~ /^\s*(\d+):(.*)$/) { ($epoch, $rest) = ($1, $2); }
    else                        { ($epoch, $rest) = ('0', $s); }
    $epoch = '0' if !defined $epoch || $epoch eq '' || lc($epoch) eq '(none)';
    my ($ver, $rel) = split /-/, $rest, 2;
    return ($epoch, $ver, $rel);   # $rel undef when no release given
}

# evr_cmp($got, $want, $vercmp): compare two EVRs with rpm's labelCompare semantics -- epoch first
# (numeric), then version, then release -- returning -1/0/1 (got vs want). $vercmp->($a,$b) is an
# injected rpm-native segment comparator (rpm's rpmvercmp) returning -1/0/1, so this stays pure and
# unit-testable. Release is compared only when the CONSTRAINT specifies one (rpm's EVR semantics: a
# version-only requirement ignores the built release).
sub evr_cmp {
    my ($got, $want, $vercmp) = @_;
    my ($ge, $gv, $gr) = parse_evr($got);
    my ($we, $wv, $wr) = parse_evr($want);
    return (($ge <=> $we) <=> 0) if ($ge <=> $we) != 0;   # epoch: numeric
    my $c = $vercmp->($gv, $wv);
    return $c if $c;
    return 0 unless defined $wr && $wr ne '';             # constraint release-agnostic
    $gr = '' unless defined $gr;
    return $vercmp->($gr, $wr);
}

# evr_constraint_ok($got, $op, $want, $vercmp): does the observed EVR satisfy "<op> <want>"?
sub evr_constraint_ok {
    my ($got, $op, $want, $vercmp) = @_;
    my $c = evr_cmp($got, $want, $vercmp);
    return $c >= 0 if $op eq '>=';
    return $c >  0 if $op eq '>';
    return $c <= 0 if $op eq '<=';
    return $c <  0 if $op eq '<';
    return $c == 0 if $op eq '=' || $op eq '==';
    return undef;   # unknown operator
}

# parse_pin($pin): classify a manifest version pin.
#   '*'                         -> ('any')
#   '<op> <evr>' (>=,>,<=,<,=)  -> ('evr', $op, $evr)  full EPOCH:VERSION-RELEASE constraint
#   glob or exact version       -> ('version')         %{VERSION}-only match (version_matches)
sub parse_pin {
    my ($pin) = @_;
    return ('any') if !defined($pin) || $pin eq '*';
    return ('evr', $1, $2) if $pin =~ /^\s*(>=|<=|==|=|>|<)\s*(\S+)\s*$/;
    return ('version');
}

sub verify_repo_packages {
    my ($expected, $present_ver, $present_evr, $vercmp) = @_;
    $present_evr //= $present_ver;
    my @problems;
    for my $pkg (sort keys %$expected) {
        my $pin = $expected->{$pkg};
        my $got_ver = $present_ver->{$pkg};
        if (!defined $got_ver) {
            push @problems, "MISSING $pkg (manifest requires " . (defined($pin) ? $pin : '*') . ")";
            next;
        }
        my ($kind, $op, $want) = parse_pin($pin);
        if ($kind eq 'evr') {
            my $got_evr = $present_evr->{$pkg} // $got_ver;
            if (!$vercmp) {
                push @problems, "EVR $pkg: no EVR comparator available to check '$op $want'";
            } elsif (!evr_constraint_ok($got_evr, $op, $want, $vercmp)) {
                push @problems, "EVR $pkg: repo has $got_evr, manifest requires $op $want";
            }
        } elsif ($kind eq 'version') {   # VERSION glob/exact (unchanged)
            push @problems, "VERSION $pkg: repo has $got_ver, manifest pins $pin"
                if !version_matches($got_ver, $pin);
        }
        # 'any' -> accept
    }
    return @problems;
}

# rpmkeys_checksig_problem($name, $rc, $out): pure verdict for one `rpmkeys --checksig -v` run against
# an isolated keyring holding only the signing key. A clean rpm exits 0 and every digest/signature
# line reads OK; a tampered digest reads NOT OK; an rpm signed by another key (or unsigned) reads
# NOKEY. Return a problem string (or empty list) so the gate is testable without rpm.
sub rpmkeys_checksig_problem {
    my ($name, $rc, $out) = @_;
    $out = '' unless defined $out;
    return () if ($rc // 0) == 0 && $out !~ /NOT OK|NOKEY|MISSING KEYS/i;
    my $why = $out =~ /NOT OK/i        ? 'digest/signature NOT OK'
            : $out =~ /NOKEY/i         ? 'NOKEY (unsigned or signed by an unaccepted key)'
            : $out =~ /MISSING KEYS/i  ? 'MISSING KEYS'
            :                            "rpmkeys --checksig failed (rc=" . ($rc // '?') . ")";
    return "BADSIG rpm $name: $why";
}

# verify_repo_signature: the PURE signature-decision layer of the repo gate. Given %expected
# { unit => expected signing-key identity } and %observed { unit => key that ACTUALLY signed (a
# string the script extracts from gpg), or undef/'' when unsigned / verification failed }, return a
# list of problem strings (empty = every unit signed by the expected key). For EL the single unit is
# 'repomd'. This does a plain string compare only -- it invokes NO gpg: the caller runs gpg --verify,
# extracts the observed key id, and resolves --gpg-key-name to the SAME identity form before calling.
#   "UNSIGNED <unit> (expected <key>)"                     when %observed is absent/empty for <unit>
#   "WRONGKEY <unit>: signed by <observed>, expected <key>" when both defined but differ
sub verify_repo_signature {
    my ($expected, $observed) = @_;
    my @problems;
    for my $unit (sort keys %$expected) {
        my $exp = $expected->{$unit};
        my $obs = $observed->{$unit};
        if (!defined($obs) || $obs eq '') {
            push @problems, "UNSIGNED $unit (expected " . (defined($exp) ? $exp : '') . ")";
        } elsif (defined($exp) && $obs ne $exp) {
            push @problems, "WRONGKEY $unit: signed by $obs, expected $exp";
        }
    }
    return @problems;
}

# verify_rpm_signatures: pure decision for the per-rpm signature gate. $rpm_sigs is an arrayref of
# [rpm_basename, observed_keyid|undef] (rpm reports the signing SUBKEY id); $accept is a hashref set
# of acceptable key ids (the signing key's primary + subkey ids, lowercased). Returns one problem per
# rpm that is unsigned or signed by a key not in the set. A signed repomd over unsigned/foreign-signed
# rpms still makes DNF reject the install, so the packages must be checked, not just the metadata.
sub verify_rpm_signatures {
    my ($rpm_sigs, $accept) = @_;
    my @problems;
    for my $rs (@$rpm_sigs) {
        my ($name, $kid) = @$rs;
        if (!defined($kid) || $kid eq '') {
            push @problems, "UNSIGNED rpm $name";
        } elsif (!$accept->{ lc $kid }) {
            push @problems, "WRONGKEY rpm $name: signed by $kid, expected one of "
                . join('/', sort keys %$accept);
        }
    }
    return @problems;
}

# have_rpm: is there a non-src rpm named <name>-... under $dir?
sub have_rpm {
    my ($dir, $name) = @_;
    my @m = grep { !/\.src\.rpm$/ } glob("$dir/${name}-*.rpm");
    return scalar(@m) > 0;
}

# rpm_sigmd5: the SIGMD5 of an rpm -- the digest of its header+payload, independent of the GPG
# signature. Used to compare RPM identity/content: two rpms that share a basename but differ in
# content have different SIGMD5 (a bare filename match is not enough to call them identical).
sub rpm_sigmd5 {
    my ($f) = @_;
    return '' unless defined $f && -f $f;
    my $v = `rpm -qp --qf '%{SIGMD5}' ${\ sh_quote($f)} 2>/dev/null`;
    chomp $v;
    return $v;
}

# rpm_is_signed: does the rpm carry a PGP/GPG header signature? SIGMD5 (above) is content-only and
# is identical whether or not the rpm is signed, so a cross-copied genesis that was copied but not
# yet signed (a crash between the copy and the rpmsign) still matches by SIGMD5. finalize uses this
# to treat such a rpm as NOT up to date so the copy+sign path re-runs and heals it.
sub rpm_is_signed {
    my ($f) = @_;
    return 0 unless defined $f && -f $f;
    my $v = `rpm -qp --qf '%{SIGPGP}%{SIGGPG}' ${\ sh_quote($f)} 2>/dev/null`;
    return 0 if !defined $v;
    $v =~ s/\(none\)//g;      # unsigned rpms report "(none)" for both tags
    $v =~ s/\s+//g;
    return $v ne '' ? 1 : 0;
}

# restamp_release_line: given a spec `Release: ...` line and a CD suffix (".snap<YYYYMMDDHHMM>.<n>"),
# return (new_line, changed). Idempotent: a line already ending in exactly $suffix is returned
# unchanged (changed=0). A line carrying a DIFFERENT prior .snap stamp (or several, from an earlier
# corrupted run) has it stripped before the new suffix is appended, so a re-run in a reused tree
# REPLACES the stamp instead of accumulating a second one (…snap...57 -> …snap...58, never
# …snap...57.snap...58). Only the Release token is touched; a non-Release line is returned as-is.
sub restamp_release_line {
    my ($line, $suffix) = @_;
    return ($line, 0) unless defined $line && $line =~ /^Release:\s*\S/i;
    my $qs = quotemeta($suffix);
    return ($line, 0) if $line =~ /$qs\s*$/;                 # already carries THIS suffix
    (my $new = $line) =~ s/(?:\.snap\d{12}\.\d+)+(\s*)$/$1/; # drop any prior CD stamp(s)
    $new =~ s/(^Release:\s*\S+)/$1$suffix/i;
    return ($new, 1);
}

# rpm_version: %{version} of the built binary rpm named <name> under $dir (undef if absent).
# Skips src/debug rpms and confirms the rpm's real %{name} matches (glob can over-match).
# 'xCAT-genesis-base' matches the arch-suffixed rpm name (xCAT-genesis-base-x86_64 / -ppc64).
sub rpm_version {
    my ($dir, $name) = @_;
    my $glob = ($name eq 'xCAT-genesis-base')
        ? "$dir/xCAT-genesis-base-*.rpm"
        : "$dir/${name}-*.rpm";
    my %vers;   # distinct %{version}s of the matching binary rpms
    for my $f (sort glob($glob)) {
        next if $f =~ /\.src\.rpm$/ || $f =~ /-debug(?:info|source)-/;
        my $n = `rpm -qp --qf '%{name}' ${\ sh_quote($f)} 2>/dev/null`;
        my $match = ($name eq 'xCAT-genesis-base')
            ? ($n =~ /^xCAT-genesis-base-/) : ($n eq $name);
        next unless $match;
        my $v = `rpm -qp --qf '%{version}' ${\ sh_quote($f)} 2>/dev/null`;
        chomp $v;
        $vers{$v} = 1 if $v ne '';
    }
    return undef unless %vers;
    # More than one distinct version present means a stale artifact was not cleaned before the
    # build -- a version pin could then pass against the wrong rpm and both could be shipped.
    # (For genesis both arches share the same Version, so a normal x86_64+ppc64 pair is one entry.)
    die "Multiple versions of $name present in $dir: " . join(', ', sort keys %vers)
      . " (stale artifact not cleaned before the build)\n" if keys(%vers) > 1;
    my ($v) = keys %vers;
    return $v;
}

# rpm_release: %{release} of the built binary rpm named <name> under $dir (undef if absent). Same
# name-matching as rpm_version. Used to confirm a CD --build-number/--release-suffix bump actually
# landed in the built rpm's Release (validating %{VERSION} alone can't catch a silently un-bumped NVR).
sub rpm_release {
    my ($dir, $name) = @_;
    my $glob = ($name eq 'xCAT-genesis-base')
        ? "$dir/xCAT-genesis-base-*.rpm"
        : "$dir/${name}-*.rpm";
    for my $f (sort glob($glob)) {
        next if $f =~ /\.src\.rpm$/ || $f =~ /-debug(?:info|source)-/;
        my $n = `rpm -qp --qf '%{name}' ${\ sh_quote($f)} 2>/dev/null`;
        my $match = ($name eq 'xCAT-genesis-base')
            ? ($n =~ /^xCAT-genesis-base-/) : ($n eq $name);
        next unless $match;
        my $r = `rpm -qp --qf '%{release}' ${\ sh_quote($f)} 2>/dev/null`;
        chomp $r;
        return $r if $r ne '';
    }
    return undef;
}

# read_manifest: parse packages-manifest.conf into %{ target => { package => version|'*' } }.
# INI format: [target] sections; "package=version|*" entries; blank / "#" / ";" lines ignored.
# Returns an empty hash if the file is absent (callers that build require a section per target).
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

# cross_copy_genesis: copy the noarch xCAT-genesis-base-<tarch>-*.rpm from $from into $to, dropping
# any stale foreign-arch genesis already in $to so the repo ends with exactly the fresh set.
# Returns the count of rpms newly copied (0 = already up to date, so the caller can skip
# re-indexing). Idempotent. $sign is an optional coderef ($rpm_path) invoked on each copied rpm
# (e.g. to re-sign it); pass undef to skip signing. Content is compared by SIGMD5, so a stale
# same-name rpm is refreshed rather than mistaken for up to date.
sub cross_copy_genesis {
    my ($from, $to, $tarch, $sign) = @_;
    my @src = grep { !/\.src\.rpm$/ } glob("$from/xCAT-genesis-base-$tarch-*.rpm");
    return 0 if !@src;
    my %want = map { basename($_) => $_ } @src;
    my @existing = grep { !/\.src\.rpm$/ } glob("$to/xCAT-genesis-base-$tarch-*.rpm");
    if (scalar(@existing) == scalar(keys %want)) {
        my $up_to_date = 1;
        for my $base (keys %want) {
            my $dst = "$to/$base";
            my $src_sig = rpm_sigmd5($want{$base});
            # An empty SIGMD5 (unreadable rpm) means "cannot confirm identical" -> refresh rather
            # than risk skipping on a false match (two '' would otherwise compare equal).
            if (!-f $dst || $src_sig eq '' || $src_sig ne rpm_sigmd5($dst)) { $up_to_date = 0; last; }
            # Content matches, but SIGMD5 cannot see the signature: a crash between the copy and the
            # per-rpm sign leaves a same-content-but-UNSIGNED rpm. When a signer is configured, treat
            # an unsigned dst as not-up-to-date so the copy+sign path re-runs and signs it.
            if ($sign && !rpm_is_signed($dst)) { $up_to_date = 0; last; }
        }
        return 0 if $up_to_date;
    }
    for my $old (@existing) {
        unlink $old or die "Failed to remove stale genesis $old: $!\n";
        print "[finalize]   - " . basename($old) . " (stale foreign-arch, removed from $to)\n";
    }
    my $copied = 0;
    for my $base (sort keys %want) {
        copy($want{$base}, "$to/$base")
            or die "Failed to cross-copy genesis $want{$base} -> $to: $!\n";
        print "[finalize]   + $base  ($from -> $to)\n";
        $sign->("$to/$base") if $sign;   # e.g. re-sign so the deploy gate never sees an unsigned rpm
        $copied++;
    }
    return $copied;
}

# finalize_xcat_dep: cross-populate the noarch xCAT-genesis-base between each matching
# <os>/x86_64 and <os>/ppc64le repo pair (issue #7610), then re-index the repos that changed.
# %opt: sign => coderef($rpm) applied to copied rpms (or undef); reindex => coderef($dir) run on
# a repo whose rpm set changed (or undef). Both injected so this stays free of gpg/createrepo
# state and is unit-testable. Requires each arch's own genesis rpm to be present (a pair with no
# genesis is a hard error, never a silent no-op) and fails if no repo pair is found at all.
# Architectures whose xCAT-genesis-base is cross-provisioned into every peer repo, so a management
# node can netboot nodes of any arch (issue #7610). Each entry maps the repo/subdir arch name to the
# genesis rpm's xCAT "tarch" (xCAT collapses ppc/ppc64le into tarch ppc64; x86_64 stays x86_64). This
# is the SINGLE SOURCE OF TRUTH for the cross-arch matrix -- to add an arch later (e.g. aarch64,
# riscv64) add an entry here AND wire its repo root into finalize_xcat_dep's %repo (the caller passes
# it). Discovery, the per-arch input gate, and the N-way cross-copy all iterate this list.
our @GENESIS_ARCHES = (
    { arch => 'x86_64',  tarch => 'x86_64' },
    { arch => 'ppc64le', tarch => 'ppc64'  },
);

sub finalize_xcat_dep {
    my ($x86_64_repo, $ppc64le_repo, %opt) = @_;
    my $sign    = $opt{sign};
    my $reindex = $opt{reindex};
    print_step('Finalize xcat-dep: cross-arch genesis-base provisioning (issue #7610)');
    print "x86_64-repo:  $x86_64_repo\n";
    print "ppc64le-repo: $ppc64le_repo\n";

    # Per-arch repo root, keyed by the @GENESIS_ARCHES arch name. A new arch added to that list must
    # also get its root wired here (today both roots are the same CD tree); a missing one fails loudly
    # below rather than silently skipping.
    my %repo = ( x86_64 => $x86_64_repo, ppc64le => $ppc64le_repo );

    # Discover the UNION of OS dirs across ALL arch repos. Anchoring discovery on one arch let an
    # <os> built for only the OTHER arch slip through unseen -- finalize then never cross-populated
    # that cell and still exited 0 (PR #62 review). Every discovered <os> must carry every arch below.
    my %os;
    for my $a (@GENESIS_ARCHES) {
        my $root = $repo{ $a->{arch} }
            // die "FATAL: [finalize] no repo root configured for arch '$a->{arch}' (wire it in %repo)\n";
        $os{ basename($_) } = 1 for grep { -d "$_/$a->{arch}" } glob("$root/*");
    }

    my $pairs = 0;
    for my $osdir (sort keys %os) {
        my %adir = map { $_->{arch} => "$repo{$_->{arch}}/$osdir/$_->{arch}" } @GENESIS_ARCHES;
        # Pass 1 -- every arch peer repo dir must exist: a one-arch <os> is an incomplete input, not
        # something to skip past (skipping would leave a cell without a foreign-arch genesis and still
        # exit 0). Checked before the rpm pass so a missing peer is reported as such. Symmetric across
        # all arches (catches an x86_64-only AND a ppc64le-only <os>).
        for my $a (@GENESIS_ARCHES) {
            die "FATAL: [finalize] $osdir: no $a->{arch} peer repo at $adir{$a->{arch}}\n"
              . "  (every arch must build every EL before finalize)\n" if !-d $adir{ $a->{arch} };
        }
        # Pass 2 -- every arch must have produced its OWN genesis rpm before finalize cross-populates
        # them; otherwise a pair with no genesis rpms would make finalize a silent no-op that still
        # exits 0. xCAT collapses ppc/ppc64le into tarch=ppc64, so match on each arch's tarch.
        for my $a (@GENESIS_ARCHES) {
            die "FATAL: [finalize] $osdir: no $a->{arch} xCAT-genesis-base rpm (tarch $a->{tarch}) in $adir{$a->{arch}}\n"
                if !grep { !/\.src\.rpm$/ } glob("$adir{$a->{arch}}/xCAT-genesis-base-$a->{tarch}-*.rpm");
        }
        # N-way cross-copy: put each arch's genesis into EVERY other arch's repo dir.
        my @summary;
        for my $src (@GENESIS_ARCHES) {
            for my $dst (@GENESIS_ARCHES) {
                next if $src->{arch} eq $dst->{arch};
                my $n = cross_copy_genesis($adir{$src->{arch}}, $adir{$dst->{arch}}, $src->{tarch}, $sign);
                push @summary, "$n $src->{tarch} -> $dst->{arch}";
            }
        }
        # Re-index+sign EVERY arch repo of this <os> each finalize, not only when an rpm was copied
        # this run: a crash after a prior run's copy+sign but before its createrepo leaves the genesis
        # rpm on disk (so cross_copy_genesis now returns 0) yet ABSENT from repomd.xml -- which no
        # signature gate catches. Re-indexing is cheap (tiny repos) and idempotent, and heals that
        # partial state; skipped only when no signer/indexer was injected.
        if ($reindex) { $reindex->($adir{$_->{arch}}) for @GENESIS_ARCHES; }
        print "[finalize] $osdir: " . join(', ', @summary) . "\n";
        $pairs++;
    }
    die "FATAL: --finalize-xcat-dep found no <os> repo dir under any arch root\n"
      . "  --x86_64-repo '$x86_64_repo'\n  --ppc64le-repo '$ppc64le_repo'\n" if $pairs == 0;
    print_step('Finalize complete');
}

# bump_dep_release_suffix: append $suffix (e.g. ".snap202607161200.57") to the Release: line of
# every xcat-dep package spec under $repo_root, so the CD build stamps a fresh, monotonic NVR.
# Idempotent: a spec already carrying this exact suffix is left alone (a re-run in the same tree
# does not double-stamp). Preserves any %{?dist}/%{?distver} macro already on the line. Returns the
# count of specs newly stamped. Dies only if NO spec under $repo_root carries a Release: line.
# Pure (takes everything as args) so t/mockbuild-all.t can exercise it directly.
sub bump_dep_release_suffix {
    my ($repo_root, $suffix) = @_;
    my @specs;
    # Only stamp xcat-dep's OWN specs. If someone checked xcat-core out NESTED under $repo_root (the
    # legacy `xcat-source-code`/`xcat-core` layout), do NOT descend into it -- rewriting a core spec
    # (e.g. xCAT-genesis-base.spec's dynamic Release) would break the lockstep with genesis-scripts.
    find(sub {
        if (-d $_ && ($_ eq 'xcat-core' || $_ eq 'xcat-source-code')) { $File::Find::prune = 1; return; }
        push @specs, $File::Find::name if /\.spec$/ && -f $_;
    }, $repo_root);
    my ($with_release, $bumped, $already) = (0, 0, 0);
    for my $spec (sort @specs) {
        open my $in, '<', $spec or die "open $spec: $!\n";
        my @lines = <$in>;
        close $in;
        my ($has_release, $changed) = (0, 0);
        for my $line (@lines) {
            # case-insensitive: some specs (e.g. Sys-Virt.spec) use a lowercase `release:`
            next unless $line =~ /^Release:\s*\S/i;
            $has_release = 1;
            # restamp_release_line is idempotent (no-op if already carrying $suffix) and strips any
            # prior .snap stamp before applying the new one, so a re-run with a different
            # --build-number replaces rather than accumulates (unit-tested in t/mockbuild-all.t).
            my ($new, $ch) = restamp_release_line($line, $suffix);
            if ($ch) { $line = $new; $changed = 1; }
            last;                                 # only the first Release: line
        }
        $with_release++ if $has_release;
        $already++      if $has_release && !$changed;
        next unless $changed;
        # atomic write (temp + rename) so a concurrent per-arch build on the shared NFS tree never
        # sees a torn spec; identical suffix -> identical content, so last-writer-wins is safe. The
        # temp name carries the hostname AND pid: the two arch build hosts share the NFS tree and can
        # reuse the same pid, so pid alone could collide across hosts.
        my $tmp = "$spec.bump." . hostname() . ".$$";
        open my $out, '>', $tmp or die "open> $tmp: $!\n";
        print {$out} @lines;
        close $out;
        rename $tmp, $spec or die "rename $tmp -> $spec: $!\n";
        $bumped++;
    }
    print "Release bump '$suffix': $bumped newly stamped, $already already stamped, of $with_release spec(s) with a Release line under $repo_root\n";
    # Only a genuine "no dep specs at all" is fatal. All-already-stamped is the expected idempotent
    # case (re-run in the same tree, or the other arch bumped first) -- NOT an error.
    die "FATAL: --build-number given but NO spec carried a Release: line under $repo_root (wrong tree?)\n"
        if $with_release == 0;
    return $bumped;
}

# build_mock_uniqueext: a mock --uniqueext UNIQUE per (run, build-step) so concurrent mock builds
# never share a chroot root (/var/lib/mock/<cfg>-<uniqueext>). $run is the per-target run id
# (e.g. "alma+epel-8-ppc64le-<n>"), $seq orders the step, $label names the package.
#
# The run id must NOT be blindly tail-truncated. The per-target id leads with the EL/arch token, and
# for the 7-char "ppc64le" arch the EL digit is exactly what falls off the front of a keep-the-last-24
# truncation -- so alma+epel-{8,9,10}-ppc64le all collapse to the same run part. That is catastrophic
# for goconserver, which compiles EVERY EL in the el10 chroot (build_cfg rewritten to -10-): the
# chroot NAME is then identical across the three ELs, and the uniqueext is the ONLY thing keeping
# their roots apart, so three concurrent el8/el9/el10 ppc64le goconserver builds race in one root.
# When the id is too long, keep a readable leading token AND append a short digest of the FULL id, so
# distinct ids always yield distinct uniqueext regardless of where in the string they differ.
sub build_mock_uniqueext {
    my ($run, $seq, $label) = @_;

    my $run_part = defined($run) ? $run : 'run';
    $run_part =~ s/[^A-Za-z0-9_.-]+/-/g;
    $run_part =~ s/^-+|-+$//g;
    $run_part = 'run' if $run_part eq '';
    if (length($run_part) > 24) {
        my $digest = substr(md5_hex($run_part), 0, 8);
        (my $head = substr($run_part, 0, 15)) =~ s/-+$//;
        $run_part = "$head-$digest";
    }

    my $label_part = defined($label) ? $label : 'step';
    $label_part =~ s/[^A-Za-z0-9_.-]+/-/g;
    $label_part =~ s/^-+|-+$//g;
    $label_part = 'step' if $label_part eq '';
    $label_part = substr($label_part, 0, 20) if length($label_part) > 20;

    my $idx = defined($seq) ? int($seq) : 0;
    $idx = 0 if $idx < 0;

    return sprintf("mba-%02d-%s-%s", $idx, $run_part, $label_part);
}

1;
