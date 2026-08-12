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
                      bump_dep_release_suffix);

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

done_testing;
