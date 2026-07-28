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
use MockBuildUtils qw(required_pkgs version_matches rpm_sigmd5 rpm_version
                      cross_copy_genesis finalize_xcat_dep read_manifest);

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

done_testing;
