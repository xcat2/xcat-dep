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

our @EXPORT_OK = qw(
    sh_quote print_step
    version_matches required_pkgs have_rpm read_manifest
    verify_repo_packages verify_repo_signature
    rpm_version rpm_release rpm_sigmd5 rpm_is_signed restamp_release_line
    cross_copy_genesis finalize_xcat_dep bump_dep_release_suffix
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
sub verify_repo_packages {
    my ($expected, $present) = @_;
    my @problems;
    for my $pkg (sort keys %$expected) {
        my $pin = $expected->{$pkg};
        my $got = $present->{$pkg};
        if (!defined $got) {
            push @problems, "MISSING $pkg (manifest requires " . (defined($pin) ? $pin : '*') . ")";
        } elsif (!version_matches($got, $pin)) {
            push @problems, "VERSION $pkg: repo has $got, manifest pins $pin";
        }
    }
    return @problems;
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
sub finalize_xcat_dep {
    my ($x86_64_repo, $ppc64le_repo, %opt) = @_;
    my $sign    = $opt{sign};
    my $reindex = $opt{reindex};
    print_step('Finalize xcat-dep: cross-arch genesis-base provisioning (issue #7610)');
    print "x86_64-repo:  $x86_64_repo\n";
    print "ppc64le-repo: $ppc64le_repo\n";
    my @osdirs = grep { -d "$_/x86_64" } glob("$x86_64_repo/*");
    my $pairs = 0;
    for my $p (sort @osdirs) {
        my $osdir  = basename($p);
        my $x86dir = "$x86_64_repo/$osdir/x86_64";
        my $ppcdir = "$ppc64le_repo/$osdir/ppc64le";
        # Require the peer repo itself: in the CD both arches build every EL, so a missing
        # ppc64le peer for an x86_64 OS means an incomplete input, not something to skip past
        # (skipping would leave that OS's x86_64 repo without the ppc64 genesis and still exit 0).
        die "FATAL: [finalize] $osdir: no ppc64le peer repo at $ppcdir\n"
          . "  (both arches must build every EL before finalize)\n" if !-d $ppcdir;
        # Require the expected inputs: each arch's build must have produced its OWN genesis rpm
        # before finalize cross-populates them. Without this, a pair whose builds produced no
        # genesis rpms would make finalize a silent no-op that still exits 0 (the bug this guards).
        die "FATAL: [finalize] $osdir: no x86_64 xCAT-genesis-base rpm in $x86dir\n"
            if !grep { !/\.src\.rpm$/ } glob("$x86dir/xCAT-genesis-base-x86_64-*.rpm");
        die "FATAL: [finalize] $osdir: no ppc64 xCAT-genesis-base rpm in $ppcdir\n"
            if !grep { !/\.src\.rpm$/ } glob("$ppcdir/xCAT-genesis-base-ppc64-*.rpm");
        # xCAT collapses ppc/ppc64/ppc64le into tarch=ppc64, so the ppc genesis rpm is
        # named xCAT-genesis-base-ppc64-*. Cross-copy both directions.
        my $to_x86 = cross_copy_genesis($ppcdir, $x86dir, 'ppc64',  $sign);
        my $to_ppc = cross_copy_genesis($x86dir, $ppcdir, 'x86_64', $sign);
        # Re-index+sign BOTH repos of the pair every finalize, not only when an rpm was copied this
        # run. A crash after a prior run's copy+sign but before its createrepo leaves the genesis rpm
        # on disk (so cross_copy_genesis now returns 0) yet ABSENT from repomd.xml -- which no
        # signature gate catches. Re-indexing is cheap (these are tiny repos) and idempotent, and it
        # heals that partial state; skipped only when no signer/indexer was injected.
        if ($reindex) { $reindex->($x86dir); $reindex->($ppcdir); }
        printf "[finalize] %s: %d ppc64 genesis -> x86_64, %d x86_64 genesis -> ppc64le\n",
            $osdir, $to_x86, $to_ppc;
        $pairs++;
    }
    die "FATAL: --finalize-xcat-dep found no <os>/x86_64 + <os>/ppc64le repo pair under\n"
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

1;
