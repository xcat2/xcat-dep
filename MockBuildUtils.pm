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

our @EXPORT_OK = qw(
    sh_quote print_step
    version_matches required_pkgs have_rpm read_manifest
    rpm_version rpm_sigmd5
    cross_copy_genesis finalize_xcat_dep
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

# rpm_version: %{version} of the built binary rpm named <name> under $dir (undef if absent).
# Skips src/debug rpms and confirms the rpm's real %{name} matches (glob can over-match).
# 'xCAT-genesis-base' matches the arch-suffixed rpm name (xCAT-genesis-base-x86_64 / -ppc64).
sub rpm_version {
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
        my $v = `rpm -qp --qf '%{version}' ${\ sh_quote($f)} 2>/dev/null`;
        chomp $v;
        return $v;
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
            if (!-f $dst || rpm_sigmd5($want{$base}) ne rpm_sigmd5($dst)) { $up_to_date = 0; last; }
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
        if (!-d $ppcdir) {
            print "[finalize] $osdir: no ppc64le peer at $ppcdir -- skipping\n";
            next;
        }
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
        $reindex->($x86dir) if $to_x86 && $reindex;
        $reindex->($ppcdir) if $to_ppc && $reindex;
        printf "[finalize] %s: %d ppc64 genesis -> x86_64, %d x86_64 genesis -> ppc64le\n",
            $osdir, $to_x86, $to_ppc;
        $pairs++;
    }
    die "FATAL: --finalize-xcat-dep found no <os>/x86_64 + <os>/ppc64le repo pair under\n"
      . "  --x86_64-repo '$x86_64_repo'\n  --ppc64le-repo '$ppc64le_repo'\n" if $pairs == 0;
    print_step('Finalize complete');
}

1;
