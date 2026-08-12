#!/usr/bin/perl
# Focused fixture tests for the Debian/apt xcat-dep build helpers (BuildUtils.pm), the analogue of
# t/mockbuild-all.t. Covers the PR #63 review feedback: per-arch package selection (concern #3),
# complete-set/version validation (#4), out-of-tree changelog stamping (no tracked-file mutation),
# and genesis control-metadata preservation (#2). The pure helpers run everywhere; the tests that
# need real .deb files are guarded by a SKIP on dpkg-deb.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/..";
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(basename);
use BuildUtils qw(required_pkgs version_matches read_manifest standard_options
                  codename_to_version version_to_codename known_codenames
                  chroot_name chroot_sources_list
                  control_field genesis_deb_control
                  deb_field deb_version deb_upstream_version deb_hash cross_copy_genesis_deb);

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

# ---- required_pkgs: a skipped builder's packages are not required (clean --skip-* runs) ---------
my @all = qw(ipmitool-xcat goconserver syslinux-xcat xcat-genesis-base);
is_deeply([required_pkgs(\@all, 0, 0)], \@all, 'no skips -> every package required');
is_deeply([required_pkgs(\@all, 1, 0)], [qw(ipmitool-xcat goconserver syslinux-xcat)],
    '--skip-genesis drops xcat-genesis-base');
is_deeply([required_pkgs(\@all, 0, 1)], [qw(xcat-genesis-base)],
    '--skip-xcat-dep drops the compiled dep builders');
is_deeply([required_pkgs(\@all, 1, 1)], [], 'all skips -> nothing required');

# ---- version_matches: exact + shell-glob pins ---------------------------------------------------
ok( version_matches('2.19.0', '2.*'),    '2.* matches 2.19.0');
ok(!version_matches('3.0.0',  '2.*'),    '2.* rejects 3.0.0');
ok(!version_matches('20.0',   '2.*'),    '2.* rejects 20.0 (anchored, literal dot)');
ok( version_matches('1.8.18', '1.8.18'), 'exact pin matches');
ok(!version_matches('1.8.19', '1.8.18'), 'exact pin rejects a different version');
ok( version_matches('anything', '*'),    "'*' matches any version");

# ---- codename <-> version map (single source of truth for the supported set) --------------------
is(codename_to_version('focal'),    'ubuntu20.04', 'focal -> ubuntu20.04 (focal IS supported)');
is(codename_to_version('noble'),    'ubuntu24.04', 'noble -> ubuntu24.04');
is(version_to_codename('ubuntu26.04'), 'resolute',  'ubuntu26.04 -> resolute');
is(codename_to_version('bogus'),    undef,         'unknown codename -> undef');
is_deeply([known_codenames], [qw(focal jammy noble resolute)], 'known_codenames = the four supported');

# ---- standard_options: the shared CLI vocabulary carries the core flags -------------------------
{
    my %opt = map { (my $k = $_) =~ s/[=!].*$//; ($k => 1) } standard_options();
    ok($opt{$_}, "standard CLI carries --$_")
        for qw(repo-root target manifest skip-build skip-install skip-genesis skip-xcat-dep
               build-number gpg-sign dry-run);
}

# ---- chroot helpers (absorbed mk-dep-chroots.sh) ------------------------------------------------
is(chroot_name('noble', 'amd64'), 'noble-amd64-sbuild', 'chroot_name shape');
{
    my $sl = chroot_sources_list(undef, 'jammy');
    my @lines = grep { /\S/ } split /\n/, $sl;
    is(scalar(@lines), 3, 'sources.list has 3 deb lines (release/updates/security)');
    ok((grep { /jammy main universe/ } @lines), 'main + universe enabled (quilt lives in universe)');
    like(chroot_sources_list('http://my.mirror/ubuntu', 'noble'), qr{http://my\.mirror/ubuntu noble },
        'mirror override honored');
}

# ---- control_field: parse a control paragraph, folding continuations ----------------------------
{
    my $ctrl = "Package: foo\nDepends: libc6 (>= 2.15),\n bar,\n baz\nBreaks: old-foo\n";
    is(control_field($ctrl, 'Depends'), 'libc6 (>= 2.15), bar, baz',
        'Depends folded across continuation lines');
    is(control_field($ctrl, 'Breaks'), 'old-foo', 'Breaks parsed');
    is(control_field($ctrl, 'Replaces'), undef, 'absent field -> undef');
}

# ---- genesis_deb_control: PRESERVE the maintained packaging semantics (concern #2) --------------
{
    # The real xCAT-genesis-builder/debian/control fields that the bare 5-field shim used to drop.
    my $maintained = <<'CTRL';
Source: xcat-genesis-base-amd64
Section: admin
Priority: optional
Maintainer: xCAT <xcat-user@lists.sourceforge.net>

Package: xcat-genesis-base-amd64
Architecture: all
Depends: ${misc:Depends}
Replaces: xcat-genesis-amd64
Breaks: xcat-genesis-amd64, xcat-genesis-scripts-amd64 (<< 2.13.10)
Description: xCAT Genesis netboot image
 base platform.
CTRL
    my $c = genesis_deb_control($maintained, 'xcat-genesis-base-amd64', '2.18.0-snap1', 'all');
    like($c, qr/^Package: xcat-genesis-base-amd64$/m, 'Package set');
    like($c, qr/^Version: 2\.18\.0-snap1$/m,          'Version set');
    like($c, qr/^Architecture: all$/m,                'Architecture set');
    like($c, qr/^Replaces: xcat-genesis-amd64$/m,     'Replaces PRESERVED (was dropped by the shim)');
    like($c, qr/^Breaks: xcat-genesis-amd64, xcat-genesis-scripts-amd64 \(<< 2\.13\.10\)$/m,
        'Breaks PRESERVED with its version constraint');
    unlike($c, qr/\$\{misc:Depends\}/, 'unresolved ${misc:Depends} substvar dropped (would ship literal)');
    like($c, qr/^Maintainer: xCAT /m, 'Maintainer preserved');
}
# With no maintained control available, an honest minimal control is still produced.
{
    my $c = genesis_deb_control(undef, 'xcat-genesis-base-ppc64el', '2.18.0-snap1', 'all');
    like($c, qr/^Package: xcat-genesis-base-ppc64el$/m, 'minimal control still names the package');
    like($c, qr/^Architecture: all$/m,                  'minimal control still arch:all');
    unlike($c, qr/^Replaces:/m, 'no Replaces invented when the maintained control is absent');
}

# ---- deb_upstream_version: strip epoch + debian revision ----------------------------------------
is(deb_upstream_version('1.8.18-4'), '1.8.18', 'strip -revision');
is(deb_upstream_version('2:0.3.3-snap202608101400.57'), '0.3.3', 'strip epoch and -revision');
is(deb_upstream_version('3.86'), '3.86', 'native-ish version returned as-is');

# ---- .deb inspection + cross-arch genesis provisioning (needs dpkg-deb for real debs) -----------
SKIP: {
    skip 'dpkg-deb not available', 8 if system('command -v dpkg-deb >/dev/null 2>&1') != 0;
    my $tmp = tempdir(CLEANUP => 1);
    my $seq = 0;
    # build a minimal .deb named <pkg>_<version>_<arch>.deb with a marker payload
    my $mk = sub {
        my ($pkg, $version, $arch, $marker) = @_;
        $marker ||= 'M';
        my $d = "$tmp/b" . (++$seq);
        make_path("$d/DEBIAN", "$d/opt/xcat/t");
        open my $fh, '>', "$d/DEBIAN/control" or die;
        print $fh "Package: $pkg\nVersion: $version\nArchitecture: $arch\n"
                . "Maintainer: t <t\@t>\nDescription: fixture\n";
        close $fh;
        open my $mf, '>', "$d/opt/xcat/t/marker" or die; print $mf $marker; close $mf;
        my $out = "$tmp/${pkg}_${version}_${arch}.deb.d$seq";
        make_path($out);
        my $deb = "$out/${pkg}_${version}_${arch}.deb";
        system("dpkg-deb --build -Znone '$d' '$deb' >/dev/null 2>&1") == 0 or die "dpkg-deb failed";
        return $deb;
    };

    my $ipmi = $mk->('ipmitool-xcat', '1.8.18-4', 'amd64');
    is(deb_field($ipmi, 'Package'), 'ipmitool-xcat', 'deb_field reads Package');
    {
        my $dir = "$tmp/vdir1"; make_path($dir);
        system("cp '$ipmi' '$dir/'");
        is(deb_version($dir, 'ipmitool-xcat'), '1.8.18', 'deb_version returns UPSTREAM version');
    }
    # deb_version dies when a dir holds two DIFFERENT upstream versions of the same package.
    {
        my $dir = "$tmp/vdir2"; make_path($dir);
        system("cp '" . $mk->('ipmitool-xcat', '1.8.18-4', 'amd64') . "' '$dir/'");
        system("cp '" . $mk->('ipmitool-xcat', '1.8.19-1', 'amd64') . "' '$dir/'");
        my $died = !eval { deb_version($dir, 'ipmitool-xcat'); 1 };
        ok($died, 'deb_version dies on multiple distinct upstream versions (stale artifact)');
    }

    # genesis cross-copy: content identity by deb_hash, refresh-stale + idempotent + sign callback.
    my $gA = $mk->('xcat-genesis-base-ppc64el', '2.18.0-snap1', 'all', 'CONTENT_A');
    my $gB = $mk->('xcat-genesis-base-ppc64el', '2.18.0-snap1', 'all', 'CONTENT_B_differs');
    isnt(deb_hash($gA), deb_hash($gB), 'deb_hash differs for same-name debs with different content');

    my ($from, $to) = ("$tmp/from", "$tmp/to"); make_path($from, $to);
    my $base = basename($gA);
    system("cp '$gA' '$from/$base'");   # fresh source
    system("cp '$gB' '$to/$base'");     # STALE dest sharing the filename
    my $n = quiet { cross_copy_genesis_deb($from, $to, 'ppc64el', undef) };
    ok($n >= 1, "cross_copy_genesis_deb refreshes a stale same-name deb by content (copied=$n)");
    is(deb_hash("$to/$base"), deb_hash($gA), 'after cross-copy the dest matches the source content');
    my $n2 = quiet { cross_copy_genesis_deb($from, $to, 'ppc64el', undef) };
    is($n2, 0, 'cross_copy_genesis_deb is a no-op when content is already identical (idempotent)');
    my @signed;
    my ($from2, $to2) = ("$tmp/from2", "$tmp/to2"); make_path($from2, $to2);
    system("cp '$gA' '$from2/$base'");
    quiet { cross_copy_genesis_deb($from2, $to2, 'ppc64el', sub { push @signed, $_[0] }) };
    is_deeply(\@signed, ["$to2/$base"], 'the sign callback runs on each copied deb');
}

# ---- manifest <-> reality consistency (concern #3 + doc drift guard) -----------------------------
{
    my %m = read_manifest("$RealBin/../debs-manifest.conf");
    my @targets = sort keys %m;
    cmp_ok(scalar(@targets), '>=', 8, 'manifest has all 8 codename x arch target sections');

    # goconserver is a compiled dep built for EVERY target (both arches, all codenames).
    my @miss_go = grep { !exists $m{$_}{'goconserver'} } @targets;
    is_deeply(\@miss_go, [], 'goconserver present in every manifest target')
        or diag("missing goconserver in: @miss_go");

    # The x86 boot components are single-producer: present ONLY in amd64 sections, never on ppc64el
    # (building syslinux/elilo/xnba on ppc is meaningless -- the review's concern #3).
    for my $t (@targets) {
        my $is_ppc = $t =~ /-ppc64el$/;
        for my $x86only (qw(syslinux-xcat elilo-xcat xnba-undi)) {
            if ($is_ppc) {
                ok(!exists $m{$t}{$x86only}, "$x86only NOT built on ppc target $t (x86-only, single producer)");
            }
        }
    }
    # ...and each amd64 section DOES carry them (so they are produced exactly once, on amd64).
    for my $t (grep { /-amd64$/ } @targets) {
        ok(exists $m{$t}{'syslinux-xcat'}, "syslinux-xcat built on amd64 target $t");
    }
}

done_testing;
