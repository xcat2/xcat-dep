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
                  verify_repo_packages verify_repo_signature parse_packages_index resolve_present_names
                  index_has_native_arch control_binary_arch skip_arch_all_on
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

# ---- verify_repo_packages: PURE completeness decision (no I/O; manifest = source of truth) -------
{
    my %req = ('ipmitool-xcat' => '1.8.18', 'goconserver' => '0.3.3', 'xcat-genesis-base' => '*');

    # happy: every required package present at a matching version (incl a '*' pin) -> no problems.
    my %ok = ('ipmitool-xcat' => '1.8.18', 'goconserver' => '0.3.3', 'xcat-genesis-base' => '2.18.0');
    is_deeply([verify_repo_packages(\%req, \%ok)], [],
        'all present + version-matching (incl * pin) -> no problems');

    # missing: a required package absent -> exactly one MISSING problem.
    my %miss = ('ipmitool-xcat' => '1.8.18', 'xcat-genesis-base' => '2.18.0');   # goconserver absent
    my @m = verify_repo_packages(\%req, \%miss);
    is(scalar(@m), 1, 'a missing required package -> one problem');
    like($m[0], qr/^MISSING goconserver /, 'missing package -> "MISSING <pkg> ..."');

    # version: present but the pin is not satisfied -> exactly one VERSION problem.
    my %ver = ('ipmitool-xcat' => '1.8.17', 'goconserver' => '0.3.3', 'xcat-genesis-base' => '2.18.0');
    my @v = verify_repo_packages(\%req, \%ver);
    is(scalar(@v), 1, 'a version-pin mismatch -> one problem');
    like($v[0], qr/^VERSION ipmitool-xcat: repo has 1\.8\.17, manifest pins 1\.8\.18$/,
        'mismatch -> "VERSION <pkg>: repo has <got>, manifest pins <pin>"');

    # combined: one missing AND one mismatched -> two problems (one MISSING + one VERSION).
    my %both = ('ipmitool-xcat' => '1.8.17', 'xcat-genesis-base' => '2.18.0');   # goconserver absent too
    my @b = verify_repo_packages(\%req, \%both);
    is(scalar(@b), 2, 'combined missing + mismatch -> two problems');
    ok((grep { /^MISSING goconserver/ } @b),   'combined carries the MISSING problem');
    ok((grep { /^VERSION ipmitool-xcat/ } @b), 'combined carries the VERSION problem');
}

# ---- verify_repo_signature: PURE signer decision (no gpg; IO layer passes %observed in) ----------
{
    my $KEY = 'C55A3A47C780A856';                        # the expected signing key identity (a unit)
    my %exp = (focal => $KEY, jammy => $KEY, noble => $KEY);

    # happy: every codename signed by the expected key -> no problems.
    is_deeply([verify_repo_signature(\%exp, { focal => $KEY, jammy => $KEY, noble => $KEY })], [],
        'all codenames signed by the expected key -> no problems');

    # unsigned: undef AND '' both count as unsigned/failed -> UNSIGNED.
    my @u = verify_repo_signature(\%exp, { focal => $KEY, jammy => undef, noble => '' });
    is(scalar(@u), 2, 'two unsigned/failed codenames -> two problems');
    ok((grep { $_ eq "UNSIGNED jammy (expected $KEY)" } @u), 'undef observed -> UNSIGNED <unit> (expected <key>)');
    ok((grep { $_ eq "UNSIGNED noble (expected $KEY)" } @u), "empty observed -> UNSIGNED <unit> (expected <key>)");

    # wrongkey: signed, but by a different key -> WRONGKEY (no false UNSIGNED for the good ones).
    my @w = verify_repo_signature(\%exp, { focal => $KEY, jammy => 'DEADBEEFDEADBEEF', noble => $KEY });
    is_deeply(\@w, ["WRONGKEY jammy: signed by DEADBEEFDEADBEEF, expected $KEY"],
        'a different signer -> WRONGKEY <unit>: signed by <observed>, expected <key>');
}

# ---- parse_packages_index: PURE apt 'Packages' index parser (name => full version) --------------
{
    my $idx = <<'PKG';
Package: ipmitool-xcat
Version: 1.8.18-4snap202608101400
Architecture: amd64
Description: fixture

Package: xcat-genesis-base-amd64
Version: 2.18.0-snap202608101400.5
Architecture: all
Description: genesis netboot image

Package: goconserver
Version: 2:0.3.3-snap202608101400.57
Architecture: amd64
Description: fixture
PKG
    my $m = parse_packages_index($idx);
    is($m->{'ipmitool-xcat'}, '1.8.18-4snap202608101400', 'first stanza name => version');
    is($m->{'xcat-genesis-base-amd64'}, '2.18.0-snap202608101400.5',
        'arch-suffixed genesis name parsed (across a blank-line separator)');
    is($m->{'goconserver'}, '2:0.3.3-snap202608101400.57', 'epoch version kept verbatim');
    is(scalar(keys %$m), 3, 'exactly the three stanzas parsed');

    # malformed / empty input -> empty hash (a stanza lacking Package:/Version: is skipped).
    is_deeply(parse_packages_index(''), {}, 'empty input -> empty hash');
    is_deeply(parse_packages_index("garbage without fields\nno colon here\n"), {},
        'malformed input (no Package:/Version:) -> empty hash');
}

# DUPLICATE = loud error: a package appearing twice with DISTINCT versions (a stale .deb left in the
# pool) must DIE -- so EL and Ubuntu AGREE that a duplicate is a hard failure, never a silent keep-one.
{
    my $dup  = "Package: ipmitool-xcat\nVersion: 1.8.18-4\n\nPackage: ipmitool-xcat\nVersion: 1.8.17-3\n";
    my $ok   = eval { parse_packages_index($dup); 1 };
    ok(!$ok, 'duplicate package with distinct versions dies (loud error)');
    like($@, qr/duplicate package 'ipmitool-xcat'/, '... and names the offending package');
    # an IDENTICAL repeated version is harmless (idempotent) and must NOT die.
    my $m2 = eval { parse_packages_index("Package: a\nVersion: 1-1\n\nPackage: a\nVersion: 1-1\n") };
    is(($m2 && $m2->{a}), '1-1', 'an identical repeated version is kept, not an error');
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

    # The noarch boot components (syslinux-xcat, grub2-xcat, elilo-xcat, xnba-undi) are Architecture:all
    # single-producer (built ONCE on amd64) but REQUIRED-PRESENT on EVERY target incl. ppc64el, so the
    # gate verifies the ppc repo actually carries them (matches the EL manifest + the 2.16 ppc dep repo;
    # a ppc MN needs them for netboot). It is the BUILD PHASE -- not the manifest -- that avoids
    # rebuilding them on ppc (build_one_codename skips an Architecture:all package on non-amd64; see the
    # control_binary_arch test below).
    for my $t (@targets) {
        for my $boot (qw(syslinux-xcat grub2-xcat elilo-xcat xnba-undi)) {
            ok(exists $m{$t}{$boot}, "$boot required-present on $t (arch:all, verified on every arch)");
        }
    }
}

# ---- resolve_present_names: PURE name-resolution incl. per-arch genesis (guards the #7610 false-PASS)
{
    # An index as it is actually published: exact-named compiled deps + BOTH Architecture:all genesis
    # debs (they appear in every arch's binary index). Versions carry the debian revision.
    my %parsed = (
        'ipmitool-xcat'          => '1.8.18-snap202601010000',
        'xcat-genesis-base-amd64'   => '2.19.0-snap202601010000',
        'xcat-genesis-base-ppc64el' => '2.19.0-snap202601010000',
    );
    my @names = ('ipmitool-xcat', 'xcat-genesis-base');

    my $amd = resolve_present_names(\%parsed, 'amd64', \@names);
    is($amd->{'ipmitool-xcat'}, '1.8.18', 'resolve: exact name reduced to upstream');
    is($amd->{'xcat-genesis-base'}, '2.19.0', 'resolve: genesis -> amd64-suffixed for the amd64 cell');

    my $ppc = resolve_present_names(\%parsed, 'ppc64el', \@names);
    is($ppc->{'xcat-genesis-base'}, '2.19.0', 'resolve: genesis -> ppc64el-suffixed for the ppc64el cell');

    # The false-PASS the reviewer caught: only the amd64 genesis is published. The ppc64el cell MUST
    # NOT resolve to it (that would mask a missing native ppc genesis, #7610) -> undef -> later MISSING.
    my %only_amd = ('xcat-genesis-base-amd64' => '2.19.0-snap202601010000');
    my $miss = resolve_present_names(\%only_amd, 'ppc64el', ['xcat-genesis-base']);
    is($miss->{'xcat-genesis-base'}, undef,
        'resolve: ppc64el cell does NOT borrow the amd64 genesis (guards the #7610 false-PASS)');
    my @prob = verify_repo_packages({ 'xcat-genesis-base' => '2.*' }, $miss);
    like($prob[0], qr/^MISSING xcat-genesis-base\b/, '... and the gate then reports it MISSING');
}

# ---- index_has_native_arch: PURE "was this arch actually built?" (native deb vs arch:all-only) ----
# Guards the verify gate against treating an arch:all-only index (grub2-xcat/genesis, which ride into
# EVERY binary-<arch>/Packages) as evidence the arch was built -- the BUILD_PPC=false false-fail.
{
    my $native_ppc = "Package: ipmitool-xcat\nVersion: 1.8.18-1\nArchitecture: ppc64el\n\n"
                   . "Package: grub2-xcat\nVersion: 2.12-1\nArchitecture: all\n";
    ok( index_has_native_arch($native_ppc, 'ppc64el'), 'native ppc64el deb -> ppc64el counts as built');
    ok(!index_has_native_arch($native_ppc, 'amd64'),   'no native amd64 stanza here -> amd64 not built');

    my $allonly_ppc = "Package: grub2-xcat\nVersion: 2.12-1\nArchitecture: all\n\n"
                    . "Package: xcat-genesis-base-ppc64el\nVersion: 2.19.0\nArchitecture: all\n";
    ok(!index_has_native_arch($allonly_ppc, 'ppc64el'),
        'arch:all-only index (grub2/genesis) does NOT count ppc64el as built (BUILD_PPC=false shape)');

    ok( index_has_native_arch("Package: x\nVersion: 1\nArchitecture: amd64\n", 'amd64'),
        'native amd64 deb -> amd64 counts as built');
    ok(!index_has_native_arch('',    'amd64'), 'empty index text -> not built');
    ok(!index_has_native_arch(undef, 'amd64'), 'undef index text -> not built (no crash)');
}

# ---- control_binary_arch: PURE Architecture lookup for a specific BINARY package in debian/control --
# Drives build_one_codename's "skip arch:all on non-amd64" (single-producer) decision. Must pick the
# right binary paragraph -- e.g. the syslinux SOURCE is 'any' but the syslinux-xcat subpackage is 'all'.
{
    my $ctl = "Source: syslinux\n\nPackage: syslinux\nArchitecture: any\n\n"
            . "Package: syslinux-xcat\nArchitecture: all\n\n"
            . "Package: syslinux-extlinux\nArchitecture: any\n";
    is(control_binary_arch($ctl, 'syslinux-xcat'), 'all', 'picks the arch:all subpackage, not the source');
    is(control_binary_arch($ctl, 'syslinux'),      'any', 'picks the per-arch main package by name');
    is(control_binary_arch($ctl, 'nonesuch'),      undef, 'absent package -> undef');
    is(control_binary_arch('',   'syslinux-xcat'), undef, 'empty control -> undef');
    is(control_binary_arch(undef,'x'),             undef, 'undef control -> undef (no crash)');
    is(control_binary_arch("Package: ipmitool-xcat\nArchitecture: ppc64el\n", 'ipmitool-xcat'),
        'ppc64el', 'native per-arch value returned verbatim');
    is(control_binary_arch("Package: ipmitool-xcat\nArchitecture: i386 amd64 ia64 ppc64el\n", 'ipmitool-xcat'),
        'i386 amd64 ia64 ppc64el', 'multi-arch Architecture returned in FULL, not just the first token');
}

# ---- skip_arch_all_on: the SHARED build/validate skip rule -----------------------------------------
# build_one_codename AND validate_manifest both consult this, so the arch:all boot tools the ppc build
# skips are ALSO exempt from the per-arch validation (else the ppc build stage would false-fail MISSING
# on packages it deliberately did not build -- the regression this guards).
{
    my $ctl = "Package: syslinux\nArchitecture: any\n\nPackage: syslinux-xcat\nArchitecture: all\n";
    ok( skip_arch_all_on($ctl, 'syslinux-xcat', 'ppc64el'), 'arch:all pkg skipped on ppc64el (build+validate)');
    ok(!skip_arch_all_on($ctl, 'syslinux-xcat', 'amd64'),   'arch:all pkg NOT skipped on amd64 (its producer)');
    ok(!skip_arch_all_on("Package: ipmitool-xcat\nArchitecture: i386 amd64 ppc64el\n", 'ipmitool-xcat', 'ppc64el'),
        'native multi-arch pkg NOT skipped on ppc64el (it IS built there)');
    ok(!skip_arch_all_on('',   'x',             'ppc64el'), 'absent control -> not skipped (fail-safe)');
    ok(!skip_arch_all_on($ctl, 'syslinux-xcat', undef),     'undef arch -> not skipped (no crash)');
}

done_testing;
