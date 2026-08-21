#!/usr/bin/perl
# Focused fixture tests for the xcat-dep build helpers (MockBuildUtils.pm), covering the review
# feedback on PR #62: skip-mode package selection, version pins, RPM-identity comparison in the
# cross-arch genesis finalize, and the "require the genesis input" guard.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/..";
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(basename);
use MockBuildUtils qw(required_pkgs version_matches rpm_sigmd5 rpm_version rpm_release rpm_is_signed
                      restamp_release_line cross_copy_genesis finalize_xcat_dep read_manifest
                      verify_repo_packages verify_repo_signature verify_rpm_signatures
                      bump_dep_release_suffix build_mock_uniqueext);

# Run a printing sub with STDOUT muted so its progress lines do not pollute TAP.
sub quiet(&) {
    my ($code) = @_;
    open(my $save, '>&', \*STDOUT) or die "dup STDOUT: $!";
    open(STDOUT, '>', '/dev/null') or die "mute STDOUT: $!";
    my @r = eval { $code->() };
    my $err = $@;
    open(STDOUT, '>&', $save) or die "restore STDOUT: $!";
    die $err if $err;
    return wantarray ? @r : $r[0];
}

# ---- required_pkgs: a skipped builder's packages are not required (clean --skip-* runs) -------
my @all = qw(elilo-xcat ipmitool-xcat perl-IO-Stty perl-Sys-Virt xCAT-genesis-base);
is_deeply([required_pkgs(\@all, 0, 0, 0)], \@all,
    'no skips -> every package required');
is_deeply([required_pkgs(\@all, 1, 0, 0)], [qw(elilo-xcat ipmitool-xcat perl-IO-Stty perl-Sys-Virt)],
    '--skip-genesis drops xCAT-genesis-base');
is_deeply([required_pkgs(\@all, 0, 1, 0)], [qw(elilo-xcat ipmitool-xcat xCAT-genesis-base)],
    '--skip-perl drops perl-*');
is_deeply([required_pkgs(\@all, 0, 0, 1)], [qw(perl-IO-Stty perl-Sys-Virt xCAT-genesis-base)],
    '--skip-xcat-dep drops the dep builders');
is_deeply([required_pkgs(\@all, 1, 1, 1)], [],
    'all skips -> nothing required (a clean skip run validates nothing)');

# ---- gate composition: a clean --skip-* run does not flag the skipped package as MISSING ------
# (PR #62 R3.3) verify_target_repo derives its expected set with required_pkgs(...skip flags), so a
# package a skip mode intentionally did not build must NOT be reported missing by the completeness
# gate. This tests the composition (required_pkgs -> verify_repo_packages), not either half alone.
{
    my %pins    = ('elilo-xcat' => '3.14', 'perl-IO-Stty' => '0.04', 'xCAT-genesis-base' => '2.*');
    my $present = { 'elilo-xcat' => '3.14', 'perl-IO-Stty' => '0.04' };   # --skip-genesis: no genesis rpm built
    my @keep    = required_pkgs([sort keys %pins], 1, 0, 0);              # skip_genesis
    my %expected = map { $_ => $pins{$_} } @keep;
    is_deeply([verify_repo_packages(\%expected, $present)], [],
        'gate: --skip-genesis run with genesis absent reports no MISSING (skipped pkg not required)');

    # Sanity: WITHOUT the skip filter that same absent genesis IS flagged -- proving the filter is load-bearing.
    my @unfiltered = verify_repo_packages(\%pins, $present);
    is(scalar(@unfiltered), 1, 'gate: unfiltered, the absent genesis is flagged MISSING');
    like($unfiltered[0], qr/^MISSING xCAT-genesis-base\b/, 'gate: the flag names the absent genesis');
}

# ---- version_matches: exact + shell-glob pins ------------------------------------------------
ok( version_matches('2.19.0', '2.*'),    '2.* matches 2.19.0');
ok( version_matches('2.18.2', '2.*'),    '2.* matches 2.18.2 (walks with xcat-core)');
ok(!version_matches('3.0.0',  '2.*'),    '2.* rejects 3.0.0');
ok(!version_matches('20.0',   '2.*'),    '2.* rejects 20.0 (anchored, literal dot)');
ok( version_matches('2.19.0', '2.19.*'), '2.19.* matches 2.19.0');
ok(!version_matches('2.20.0', '2.19.*'), '2.19.* rejects 2.20.0');
ok( version_matches('1.8.18', '1.8.18'), 'exact pin matches');
ok(!version_matches('1.8.19', '1.8.18'), 'exact pin rejects a different version');
ok( version_matches('anything', '*'),    "'*' matches any version");

# ---- read_manifest: sections + entries -------------------------------------------------------
{
    my $dir = tempdir(CLEANUP => 1);
    my $f = "$dir/m.conf";
    open my $fh, '>', $f or die;
    print $fh "# comment\n[alma+epel-8-x86_64]\nelilo-xcat=3.14\nxCAT-genesis-base=2.*\n\n"
            . "[alma+epel-9-x86_64]\nperl-Sys-Virt=11.10.0\n";
    close $fh;
    my %m = read_manifest($f);
    is($m{'alma+epel-8-x86_64'}{'elilo-xcat'},       '3.14',    'read_manifest: exact pin');
    is($m{'alma+epel-8-x86_64'}{'xCAT-genesis-base'},'2.*',     'read_manifest: glob pin');
    is($m{'alma+epel-9-x86_64'}{'perl-Sys-Virt'},    '11.10.0', 'read_manifest: second section');
    is_deeply({read_manifest("$dir/nope.conf")}, {}, 'read_manifest: missing file -> empty');
}

# rpm_sigmd5 on a missing/unreadable rpm returns '' (so cross_copy treats it as "not identical").
is(rpm_sigmd5('/nonexistent/xCAT-genesis-base-ppc64-9.9.9.noarch.rpm'), '',
    'rpm_sigmd5 returns empty for a missing rpm');

# ---- RPM-identity comparison + cross_copy_genesis (needs rpmbuild for real rpms) --------------
SKIP: {
    skip 'rpmbuild not available', 6 if system('command -v rpmbuild >/dev/null 2>&1') != 0;
    my $tmp = tempdir(CLEANUP => 1);
    my $seq = 0;
    my $mk = sub {                       # build a genesis-named rpm with a given marker payload
        my ($tarch, $content, $version) = @_;
        $version ||= '2.19.0';
        my $out = "$tmp/out" . (++$seq);   # unique dir: same NVR would overwrite in a shared one
        my $spec = "$tmp/$tarch-$seq.spec";
        open my $fh, '>', $spec or die;
        print $fh <<"SPEC";
Name: xCAT-genesis-base-$tarch
Version: $version
Release: snapTEST
Summary: test fixture
License: EPL
BuildArch: noarch
%description
test fixture
%install
mkdir -p %{buildroot}/opt/xcat/t
echo '$content' > %{buildroot}/opt/xcat/t/marker
%files
/opt/xcat/t/marker
SPEC
        close $fh;
        system("rpmbuild -bb --quiet --define '_topdir $tmp/rpmb$seq' --define '_rpmdir $out' "
             . "'$spec' >/dev/null 2>&1") == 0 or die "rpmbuild failed for $tarch/$content";
        my ($rpm) = glob("$out/noarch/xCAT-genesis-base-$tarch-*.rpm");
        return $rpm;
    };
    my $rpmA = $mk->('ppc64', 'CONTENT_A');
    my $rpmB = $mk->('ppc64', 'CONTENT_B_is_different');   # same NVR/basename, different payload

    isnt(rpm_sigmd5($rpmA), rpm_sigmd5($rpmB),
        'rpm_sigmd5 differs for same-name rpms with different content');

    my $base = basename($rpmA);
    my ($from, $to) = ("$tmp/from", "$tmp/to");
    make_path($from, $to);
    system("cp '$rpmA' '$from/$base'");   # the fresh source
    system("cp '$rpmB' '$to/$base'");     # a STALE dest rpm sharing the filename

    my $n = quiet { cross_copy_genesis($from, $to, 'ppc64', undef) };
    ok($n >= 1, "cross_copy refreshes a stale same-name rpm by content (copied=$n)");
    is(rpm_sigmd5("$to/$base"), rpm_sigmd5($rpmA),
        'after cross_copy the dest matches the source content');

    my $n2 = quiet { cross_copy_genesis($from, $to, 'ppc64', undef) };
    is($n2, 0, 'cross_copy is a no-op when content is already identical (idempotent)');

    # A signer callback is invoked for each copied rpm.
    my ($from2, $to2) = ("$tmp/from2", "$tmp/to2");
    make_path($from2, $to2);
    system("cp '$rpmA' '$from2/$base'");
    my @signed;
    quiet { cross_copy_genesis($from2, $to2, 'ppc64', sub { push @signed, $_[0] }) };
    is_deeply(\@signed, ["$to2/$base"], 'the sign callback runs on each copied rpm');

    # rpm_version dies when a dir holds two DIFFERENT versions of the same package (stale artifact).
    my $vdir = "$tmp/vers"; make_path($vdir);
    system("cp '" . $mk->('ppc64', 'x', '2.19.0') . "' '$vdir/'");
    system("cp '" . $mk->('ppc64', 'x', '2.18.0') . "' '$vdir/'");
    my $vdied = !eval { rpm_version($vdir, 'xCAT-genesis-base'); 1 };
    ok($vdied, 'rpm_version dies when a dir holds multiple distinct versions of a package');
}

# ---- finalize_xcat_dep: require the genesis inputs (no silent no-op) --------------------------
{
    my $tmp = tempdir(CLEANUP => 1);
    make_path("$tmp/x/rh9/x86_64", "$tmp/p/rh9/ppc64le");   # a pair exists, but NO genesis rpms
    my $ok = eval { quiet { finalize_xcat_dep("$tmp/x", "$tmp/p") }; 1 };
    ok(!$ok, 'finalize dies when a repo pair has no genesis rpms (was a silent success)');
    like($@, qr/no (x86_64|ppc64) xCAT-genesis-base/,
        'finalize error names the missing genesis input');

    my $tmp2 = tempdir(CLEANUP => 1);   # no <os>/x86_64 pair at all
    make_path("$tmp2/x", "$tmp2/p");
    my $ok2 = eval { quiet { finalize_xcat_dep("$tmp2/x", "$tmp2/p") }; 1 };
    ok(!$ok2, 'finalize dies when no <os>/x86_64 + <os>/ppc64le pair is found');

    # A missing ppc64le PEER repo (not just missing rpms) is fatal, not a silent skip.
    my $tmp3 = tempdir(CLEANUP => 1);
    make_path("$tmp3/x/rh9/x86_64");    # x86_64 OS present, but NO ppc64le peer dir at all
    my $ok3 = eval { quiet { finalize_xcat_dep("$tmp3/x", "$tmp3/p") }; 1 };
    ok(!$ok3, 'finalize dies when an x86_64 OS has no ppc64le peer repo (no silent skip)');
    like($@, qr/no ppc64le peer repo/, 'finalize error names the missing peer');

    # Symmetric (PR #62 review #2): a ppc64le-ONLY <os> (no x86_64 sibling) must ALSO be caught --
    # the old x86_64-anchored discovery skipped it entirely and exited 0.
    my $tmp4 = tempdir(CLEANUP => 1);
    make_path("$tmp4/p/rh9/ppc64le");   # ppc64le OS present, but NO x86_64 peer dir at all
    my $ok4 = eval { quiet { finalize_xcat_dep("$tmp4/x", "$tmp4/p") }; 1 };
    ok(!$ok4, 'finalize dies when a ppc64le OS has no x86_64 peer repo (was silently skipped)');
    like($@, qr/no x86_64 peer repo/, 'finalize error names the missing x86_64 peer');

    # @GENESIS_ARCHES is the single source of truth for the cross-arch matrix (add arches there).
    my %tarch = map { $_->{arch} => $_->{tarch} } @MockBuildUtils::GENESIS_ARCHES;
    is($tarch{x86_64},  'x86_64', 'GENESIS_ARCHES: x86_64 maps to tarch x86_64');
    is($tarch{ppc64le}, 'ppc64',  'GENESIS_ARCHES: ppc64le maps to xCAT tarch ppc64');
}

# ---- restamp_release_line: CD --build-number Release stamping (PR #62 review point 1) ----------
# A fresh stamp is appended after the Release token, preserving any %{?dist} macro.
{
    my ($l, $ch) = restamp_release_line("Release:        1%{?dist}\n", '.snap202607161200.57');
    is($l, "Release:        1%{?dist}.snap202607161200.57\n", 'stamps a fresh Release, macro preserved');
    is($ch, 1, 'reports changed');
}
# Idempotent: the exact same suffix is a no-op (concurrent per-arch build / same-tree re-run).
{
    my $line = "Release:        1%{?dist}.snap202607161200.57\n";
    my ($l, $ch) = restamp_release_line($line, '.snap202607161200.57');
    is($l, $line, 're-stamping the SAME suffix is a no-op');
    is($ch, 0, 'reports unchanged');
}
# A DIFFERENT build-number REPLACES the prior stamp (does not accumulate) -- the double-stamp bug.
{
    my ($l, $ch) = restamp_release_line("Release: 1%{?dist}.snap202607161200.57\n", '.snap202607161200.58');
    is($l, "Release: 1%{?dist}.snap202607161200.58\n", 'a new build-number replaces the old stamp');
    is($ch, 1, 'reports changed');
    unlike($l, qr/\.snap\d{12}\.\d+\.snap/, 'never leaves two stacked .snap stamps');
}
# Even an already-corrupted (double-stamped) line is healed back to a single stamp.
{
    my ($l) = restamp_release_line("Release: 5.snap202601010000.1.snap202601020000.2\n", '.snap202607161200.9');
    is($l, "Release: 5.snap202607161200.9\n", 'strips multiple stacked prior stamps before re-stamping');
}
# A non-Release line is never touched.
{
    my ($l, $ch) = restamp_release_line("Version: 0.3.3\n", '.snap202607161200.57');
    is($l, "Version: 0.3.3\n", 'non-Release line untouched');
    is($ch, 0, 'reports unchanged');
}

# ---- rpm_is_signed: unreadable / missing -> not signed (used by the finalize idempotency fix) ---
is(rpm_is_signed(undef), 0, 'rpm_is_signed(undef) is 0');
is(rpm_is_signed("/no/such/file.rpm"), 0, 'rpm_is_signed on a missing file is 0');

# ---- rpm_release: absent package -> undef (used by the --build-number bump-landed check) ---------
is(rpm_release(tempdir(CLEANUP => 1), 'nonexistent-pkg'), undef, 'rpm_release is undef when no rpm matches');

# ---- manifest <-> docs consistency: conserver-xcat is in EVERY target section (PR #62 point 7c) --
# BUILD.md documents conserver-xcat as built for every target; guard that the manifest agrees so the
# doc and the manifest can never silently drift apart again.
{
    my %m = read_manifest("$RealBin/../packages-manifest.conf");
    my @targets = sort keys %m;
    cmp_ok(scalar(@targets), '>=', 1, 'packages-manifest.conf has at least one target section');
    my @missing = grep { !exists $m{$_}{'conserver-xcat'} } @targets;
    is_deeply(\@missing, [], 'conserver-xcat is present in every manifest target section')
        or diag("missing conserver-xcat in: @missing");
}

# ---- bump_dep_release_suffix: stamps xcat-dep specs, prunes nested xcat-core, idempotent --------
# Reviewer asked for a test on this path. It walks a tree, stamps the first Release: line of every
# xcat-dep spec, prunes a nested xcat-core/ checkout, and is idempotent on a re-run.
{
    my $tmp = tempdir(CLEANUP => 1);
    # (a) a top-level dep spec that MUST be stamped
    open my $a, '>', "$tmp/a.spec" or die;
    print $a "Name: a\nVersion: 1.0\nRelease: 5%{?dist}\n";
    close $a;
    # (b) a spec NESTED under xcat-core/ that MUST be pruned (left untouched)
    make_path("$tmp/xcat-core");
    open my $b, '>', "$tmp/xcat-core/b.spec" or die;
    print $b "Name: b\nVersion: 1.0\nRelease: 9\n";
    close $b;
    # (c) a spec with no Release: line at all (ignored, never stamped)
    open my $c, '>', "$tmp/c.spec" or die;
    print $c "Name: c\nVersion: 1.0\n";
    close $c;

    my $n = quiet { bump_dep_release_suffix($tmp, '.snap202601010000') };
    is($n, 1, 'bump_dep_release_suffix stamps exactly the one dep spec with a Release line');

    my $a_after = do { open my $fh, '<', "$tmp/a.spec" or die; local $/; <$fh> };
    like($a_after, qr/^Release: 5%\{\?dist\}\.snap202601010000$/m,
        'a.spec Release now carries the CD suffix, macro preserved');

    my $b_after = do { open my $fh, '<', "$tmp/xcat-core/b.spec" or die; local $/; <$fh> };
    is($b_after, "Name: b\nVersion: 1.0\nRelease: 9\n",
        'nested xcat-core/b.spec is pruned and left untouched');

    # A SECOND call is idempotent: nothing newly stamped, a.spec content unchanged.
    my $n2 = quiet { bump_dep_release_suffix($tmp, '.snap202601010000') };
    is($n2, 0, 'a second bump_dep_release_suffix call stamps nothing (idempotent)');
    my $a_again = do { open my $fh, '<', "$tmp/a.spec" or die; local $/; <$fh> };
    is($a_again, $a_after, 'a.spec content unchanged on the idempotent second call');
}

# ---- verify_repo_packages: pure repo-completeness decision (MISSING + VERSION + wildcard) ---------
# The gate's completeness layer: given manifest pins and the versions actually present in a repo,
# return the list of problems (empty = complete). No I/O -- exercised directly with plain hashes.
{
    # happy: every required package present, one exact-pinned + one wildcard -> no problems.
    my @p = verify_repo_packages({ a => '1.0', b => '*' }, { a => '1.0', b => '9.9' });
    is_deeply(\@p, [], 'verify_repo_packages: all present + pins satisfied -> 0 problems');

    # missing: present lacks 'a' entirely -> exactly one MISSING problem naming 'a'.
    my @m = verify_repo_packages({ a => '1.0', b => '*' }, { b => '9.9' });
    is(scalar(@m), 1, 'verify_repo_packages: an absent package yields exactly one problem');
    like($m[0], qr/^MISSING a\b/, 'verify_repo_packages: absent package reported as MISSING <pkg>');

    # missing via explicit undef present value is treated the same as absent.
    my @mu = verify_repo_packages({ a => '1.0' }, { a => undef });
    is(scalar(@mu), 1, 'verify_repo_packages: undef present version counts as MISSING');
    like($mu[0], qr/^MISSING a\b/, 'verify_repo_packages: undef present version reported as MISSING');

    # version: present but the wrong version -> exactly one VERSION problem naming 'a'.
    my @v = verify_repo_packages({ a => '1.0' }, { a => '2.0' });
    is(scalar(@v), 1, 'verify_repo_packages: a mismatched version yields exactly one problem');
    like($v[0], qr/^VERSION a\b/, 'verify_repo_packages: version mismatch reported as VERSION <pkg>');

    # wildcard: a '*' pin accepts any present version -> no problem.
    my @w = verify_repo_packages({ c => '*' }, { c => '0.0.1' });
    is_deeply(\@w, [], "verify_repo_packages: '*' pin accepts any present version");

    # combined: one MISSING and one VERSION -> two problems (sorted by package name: a before b).
    my @c = verify_repo_packages({ a => '1.0', b => '2.0' }, { b => '9.9' });
    is(scalar(@c), 2, 'verify_repo_packages: one MISSING + one VERSION -> two problems');
    like($c[0], qr/^MISSING a\b/,  'verify_repo_packages: combined case reports MISSING a');
    like($c[1], qr/^VERSION b\b/, 'verify_repo_packages: combined case reports VERSION b');
}

# ---- verify_repo_signature: pure signature decision (match / unsigned / wrongkey) ----------------
# Given the expected signing-key identity per unit and the key that actually signed, return the list
# of problems (empty = every unit signed by the expected key). Plain string compare -- no gpg here.
{
    # happy: repomd signed by exactly the expected key -> no problems.
    my @ok = verify_repo_signature({ repomd => 'KEYFPR' }, { repomd => 'KEYFPR' });
    is_deeply(\@ok, [], 'verify_repo_signature: observed == expected -> 0 problems');

    # unsigned: observed empty -> one UNSIGNED problem naming the unit + expected key.
    my @us = verify_repo_signature({ repomd => 'KEYFPR' }, { repomd => '' });
    is(scalar(@us), 1, 'verify_repo_signature: empty observed yields exactly one problem');
    like($us[0], qr/^UNSIGNED repomd\b/, 'verify_repo_signature: empty observed reported as UNSIGNED');
    like($us[0], qr/expected KEYFPR/,   'verify_repo_signature: UNSIGNED names the expected key');

    # unsigned via explicit undef observed is treated the same as empty.
    my @uu = verify_repo_signature({ repomd => 'KEYFPR' }, { repomd => undef });
    like($uu[0], qr/^UNSIGNED repomd\b/, 'verify_repo_signature: undef observed reported as UNSIGNED');

    # wrongkey: signed, but by a different key -> one WRONGKEY problem naming both.
    my @wk = verify_repo_signature({ repomd => 'GOODFPR' }, { repomd => 'EVILFPR' });
    is(scalar(@wk), 1, 'verify_repo_signature: a mismatched signer yields exactly one problem');
    like($wk[0], qr/^WRONGKEY repomd: signed by EVILFPR, expected GOODFPR$/,
        'verify_repo_signature: mismatch reported as WRONGKEY <unit>: signed by <obs>, expected <exp>');
}

# ---- verify_rpm_signatures: EVERY rpm must be signed by an accepted key (PR #62 review #4) -----
{
    my %accept = ( '4123c420cb60ad43' => 1, 'cb60ad43' => 1 );   # signing key's long + short id

    my @ok = verify_rpm_signatures(
        [ ['a-1.0.rpm', 'cb60ad43'], ['b-2.0.rpm', '4123C420CB60AD43'] ], \%accept);
    is_deeply(\@ok, [], 'verify_rpm_signatures: all rpms signed by an accepted key -> no problems (case-insensitive)');

    my @uns = verify_rpm_signatures([ ['c-3.0.rpm', undef], ['d-4.0.rpm', ''] ], \%accept);
    is(scalar(@uns), 2, 'verify_rpm_signatures: undef and empty key id both flagged');
    like($uns[0], qr/^UNSIGNED rpm c-3\.0\.rpm$/, 'verify_rpm_signatures: unsigned rpm reported by name');

    my @wrong = verify_rpm_signatures([ ['e-5.0.rpm', 'deadbeef'] ], \%accept);
    is(scalar(@wrong), 1, 'verify_rpm_signatures: a foreign-signed rpm yields one problem');
    like($wrong[0], qr/^WRONGKEY rpm e-5\.0\.rpm: signed by deadbeef, expected one of\b/,
        'verify_rpm_signatures: wrong key reported as WRONGKEY rpm <name>: signed by <obs>, expected one of ...');
}

# ---- build_mock_uniqueext: distinct per target so concurrent mock roots never collide ---------
# (PR #62 review) A long (timestamp) run id must not tail-truncate away the leading EL/arch token:
# for the 7-char "ppc64le" arch that dropped the EL digit, so alma+epel-{8,9,10}-ppc64le collapsed to
# one uniqueext -- and goconserver builds all three ELs in the SAME el10 chroot, so the roots raced.
{
    my $seq = 6; my $label = 'goconserver';
    # The reproducing case: the default timestamp run id (long), folded with the per-target prefix.
    my @ppc = map { build_mock_uniqueext("alma+epel-$_-ppc64le-20260821-210716", $seq, $label) } (8, 9, 10);
    my %seen; $seen{$_}++ for @ppc;
    is(scalar(keys %seen), 3,
        'build_mock_uniqueext: el8/el9/el10 ppc64le get DISTINCT uniqueext on a long run id (no collision)');
    like($ppc[0], qr/^mba-06-alma-epel-8-/,  'uniqueext keeps a readable leading EL/arch token');

    # x86_64 (6-char arch) was never broken -- assert it stays distinct too.
    my @x86 = map { build_mock_uniqueext("alma+epel-$_-x86_64-20260821-210716", $seq, $label) } (8, 9, 10);
    my %sx; $sx{$_}++ for @x86;
    is(scalar(keys %sx), 3, 'build_mock_uniqueext: el8/el9/el10 x86_64 also distinct');

    # Short run ids (e.g. the CD "$BUILD_NUMBER") are unchanged and already distinct per target.
    isnt(build_mock_uniqueext('alma+epel-8-ppc64le-104', $seq, $label),
         build_mock_uniqueext('alma+epel-9-ppc64le-104', $seq, $label),
        'build_mock_uniqueext: short (build-number) run ids distinct per target');

    # Same run id + same step -> stable (deterministic; a re-run reuses/scrubs the same root).
    is(build_mock_uniqueext('alma+epel-8-ppc64le-20260821-210716', $seq, $label),
       build_mock_uniqueext('alma+epel-8-ppc64le-20260821-210716', $seq, $label),
        'build_mock_uniqueext: deterministic for a given (run, seq, label)');
}

done_testing;
