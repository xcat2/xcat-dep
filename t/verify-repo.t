#!/usr/bin/perl
# Focused end-to-end tests for the PUBLISHED-REPO GATE, driving the real `sbuild-all.pl --verify-repo`
# against hand-built fixture apt trees. The pure decisions are unit-tested in t/sbuild-all.t; what is
# tested HERE is the wiring that the PR #63 review found to have false-PASS cases (concern #3):
#
#   * the standalone gate must verify Release SIGNATURES BY DEFAULT -- it used to skip the check
#     silently unless --gpg-home happened to be passed, so `--verify-repo <dir>` on an unsigned tree
#     reported success;
#   * an entirely MISSING secondary architecture must be reported, not read as "this run did not build
#     that arch". The expected arch set is a claim (--expect-arch, else the repo's own Release
#     "Architectures:" line), never an inference from which binary-<arch> dirs happen to be populated.
#
# The fixtures are plain text (Packages/Release), so no dpkg/apt/gpg tooling is required.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);

my $SCRIPT = "$RealBin/../sbuild-all.pl";
plan skip_all => "sbuild-all.pl not found at $SCRIPT" unless -f $SCRIPT;

my $tmp = tempdir(CLEANUP => 1);

# An empty GNUPGHOME makes the signature outcome deterministic wherever this runs: --gpg-key-id can
# never resolve to a fingerprint here, so "signatures are checked" is observable as a hard failure
# rather than depending on the developer's keyring.
my $gpghome = "$tmp/gpg-home";
make_path($gpghome);
chmod 0700, $gpghome;

sub write_file {
    my ($path, $body) = @_;
    make_path($path =~ m{^(.*)/[^/]+$} ? $1 : '.');
    open my $fh, '>', $path or die "write $path: $!";
    print $fh $body;
    close $fh;
}

sub stanza {
    my ($pkg, $ver, $arch) = @_;
    return "Package: $pkg\nVersion: $ver\nArchitecture: $arch\n"
         . "Filename: pool/main/noble/${pkg}_${ver}_${arch}.deb\nDescription: fixture\n\n";
}

# The two Architecture:all packages ride into EVERY binary-<arch> index, exactly as apt-ftparchive
# emits them -- which is why a non-empty ppc index is not evidence that ppc64el was built.
sub arch_all_stanzas {
    my ($genesis_arch, %o) = @_;
    my $body = stanza('grub2-xcat', '2.12-1', 'all');
    $body .= stanza("xcat-genesis-base-$genesis_arch", '2.19.0-snap202608211200', 'all')
        unless $o{no_genesis};
    return $body;
}

sub native_stanzas {
    my ($a, %o) = @_;
    my $body = stanza('ipmitool-xcat', $o{ipmi_version} // '1.8.18-snap202608211200', $a);
    # drop_dep names ONE compiled dep to leave out, so a "missing dep" fixture still carries native
    # stanzas for this arch -- otherwise the arch itself reads as absent and the gate fails for that
    # reason instead of the one under test.
    $body .= stanza('goconserver', '0.3.3-snap202608211200', $a)
        unless ($o{drop_dep} // '') eq 'goconserver';
    return $body;
}

# make_repo(%opt): a fixture apt tree for codename 'noble'.
#   arches         => the arches to write a binary-<arch>/Packages for (default both)
#   release_arches => what Release advertises (default: the same list)
#   native         => arches that get NATIVE stanzas (default: all of `arches`)
my $repo_seq = 0;
sub make_repo {
    my (%o) = @_;
    my @arches  = @{ $o{arches}         // ['amd64', 'ppc64el'] };
    my @rel     = @{ $o{release_arches}  // [@arches] };
    my %native  = map { $_ => 1 } @{ $o{native} // [@arches] };
    my $dir = "$tmp/repo" . (++$repo_seq);
    for my $a (@arches) {
        my $body = ($native{$a}
                      ? native_stanzas($a, ipmi_version => $o{ipmi_version},
                                           drop_dep => $o{drop_dep})
                      : '')
                 . arch_all_stanzas($a, no_genesis => $o{no_genesis});
        write_file("$dir/dists/noble/main/binary-$a/Packages", $body);
    }
    write_file("$dir/dists/noble/Release",
        "Origin: xCAT\nLabel: xcat-dep\nSuite: noble\nCodename: noble\n"
      . "Architectures: " . join(' ', @rel) . "\nComponents: main\n"
      . "Date: Thu, 21 Aug 2026 12:00:00 +0000\n");
    return $dir;
}

# The manifest is the source of truth for what each codename x arch must carry.
my $manifest = "$tmp/debs-manifest.conf";
# Pins are matched against the FULL Debian version, so the fixtures pin revisions too.
write_file($manifest, <<'MAN');
[noble-amd64]
ipmitool-xcat=1.8.18-snap202608211200
goconserver=0.3.3-snap*
grub2-xcat=*
xcat-genesis-base=2.*

[noble-ppc64el]
ipmitool-xcat=1.8.18-snap202608211200
goconserver=0.3.3-snap*
grub2-xcat=*
xcat-genesis-base=2.*
MAN

# run_cmd(@argv) -> ($exit_code, $combined_output)
sub run_cmd {
    my (@cmd) = @_;
    my $line = join(' ', map { my $x = $_; $x =~ s/'/'"'"'/g; "'$x'" } @cmd) . ' 2>&1';
    local $ENV{GNUPGHOME} = $gpghome;
    open my $ph, '-|', $line or die "cannot run: $line: $!";
    my $out = do { local $/; <$ph> };
    close $ph;
    return ($? >> 8, defined $out ? $out : '');
}

# run_gate($repo, @extra) -> ($exit_code, $output). --arch amd64 is always pinned so the result does
# not depend on the host running the test. Note that --gpg-home is deliberately NOT passed: the
# reviewer's report was that omitting it silently disabled the signature check, so the tests below
# exercise exactly that invocation. (run_cmd still points GNUPGHOME at an empty keyring, so the
# outcome does not depend on the developer's own keys.)
sub run_gate {
    my ($repo, @extra) = @_;
    return run_cmd($^X, $SCRIPT, '--verify-repo', $repo, '--manifest', $manifest,
                   '--dists', 'noble', '--arch', 'amd64', @extra);
}

# ---- a --skip-* flag must NOT weaken the PUBLICATION gate (PR #63 review) -----------------------
# The documented publish-only invocation is `--skip-build --skip-genesis --publish`, and the gate fed
# those flags into required_pkgs() when deciding what the PUBLISHED repository must carry. So a
# repository with no Genesis package passed its own publication gate. The flags say what this
# INVOCATION built; they never say what the published repository is allowed to be missing -- the
# manifest is the source of truth for that, whole, every time.
{
    my $repo = make_repo(no_genesis => 1);
    my ($rc, $out) = run_gate($repo, '--no-verify-signature', '--skip-genesis');
    isnt($rc, 0, 'a published repo missing Genesis fails the gate even with --skip-genesis')
        or diag($out);
    like($out, qr/xcat-genesis-base/, '... and the failure names the missing package');
}

# The same reasoning for the compiled deps: --skip-xcat-dep means this invocation did not build
# them, not that the repository may ship without them.
{
    my $repo = make_repo(drop_dep => 'goconserver');
    my ($rc, $out) = run_gate($repo, '--no-verify-signature', '--skip-xcat-dep');
    isnt($rc, 0, 'a published repo missing a compiled dep fails the gate even with --skip-xcat-dep')
        or diag($out);
    like($out, qr/goconserver/, '... and the failure names the missing dep');
}

# ---- a complete two-arch repo passes (the baseline: the gate is not simply always-red) -----------
{
    my $repo = make_repo();
    my ($rc, $out) = run_gate($repo, '--no-verify-signature');
    is($rc, 0, 'complete two-arch repo passes the gate') or diag($out);
    like($out, qr/\[verify-repo\] complete/, '... and says so');
    like($out, qr/expected arches: amd64 ppc64el/,
        '... having taken the expected arch set from the repo\'s own Release claim');
}

# ---- THE FALSE-PASS: an entirely missing secondary architecture -----------------------------------
# The repo advertises amd64 + ppc64el but ships no binary-ppc64el at all. Verified with --arch amd64
# and no --expect-arch -- the exact invocation that used to report success.
{
    my $repo = make_repo(arches => ['amd64'], release_arches => ['amd64', 'ppc64el']);
    my ($rc, $out) = run_gate($repo, '--no-verify-signature');
    isnt($rc, 0, 'a repo missing an advertised architecture FAILS (was a silent pass)') or diag($out);
    like($out, qr/MISSING-ARCH ppc64el|\[noble\/ppc64el\] MISSING-INDEX/,
        '... naming the missing architecture');
}

# ... and the same tree with the expected set passed EXPLICITLY, which is what the CD pipeline does.
{
    my $repo = make_repo(arches => ['amd64'], release_arches => ['amd64']);
    my ($rc, $out) = run_gate($repo, '--no-verify-signature', '--expect-arch', 'amd64 ppc64el');
    isnt($rc, 0, '--expect-arch demands the arch even when Release does not advertise it') or diag($out);
    like($out, qr/MISSING-ARCH ppc64el|\[noble\/ppc64el\] MISSING-INDEX/, '... naming it');
}

# An index that exists but carries ONLY the Architecture:all packages is not a built architecture:
# grub2-xcat and the genesis debs land in every binary-<arch>/Packages.
{
    my $repo = make_repo(arches => ['amd64', 'ppc64el'], native => ['amd64']);
    my ($rc, $out) = run_gate($repo, '--no-verify-signature');
    isnt($rc, 0, 'an arch:all-only ppc index does not count as a built ppc64el') or diag($out);
    like($out, qr/MISSING-ARCH ppc64el/, '... reported as MISSING-ARCH');
    like($out, qr/MISSING ipmitool-xcat|MISSING goconserver/,
        '... and its native packages are reported missing');
}

# A genuinely single-arch repo (BUILD_PPC=false) that advertises only amd64 must NOT false-fail.
{
    my $repo = make_repo(arches => ['amd64'], release_arches => ['amd64']);
    my ($rc, $out) = run_gate($repo, '--no-verify-signature');
    is($rc, 0, 'an honest single-arch repo passes (no false MISSING-ARCH)') or diag($out);
}

# A stale architecture left in a tree that is no longer expected is also a problem.
{
    my $repo = make_repo();
    my ($rc, $out) = run_gate($repo, '--no-verify-signature', '--expect-arch', 'amd64');
    isnt($rc, 0, 'natives for an arch outside --expect-arch FAIL (stale architecture)') or diag($out);
    like($out, qr/UNEXPECTED-ARCH ppc64el/, '... reported as UNEXPECTED-ARCH');
}

# ---- THE OTHER FALSE-PASS: standalone verification skipped signatures ----------------------------
# Same complete tree, without --no-verify-signature AND without --gpg-home -- the invocation that used
# to report success because the signature check was silently skipped. The fixture has no
# InRelease/Release.gpg, so a gate that actually checks signatures must fail.
{
    my $repo = make_repo();
    my ($rc, $out) = run_gate($repo);
    isnt($rc, 0, 'an UNSIGNED repo fails standalone verification by default') or diag($out);
    like($out, qr/signature check: on/, '... the signature check is on by default');
    like($out, qr/UNSIGNED noble|SIGKEY/, '... and the problem is reported');
}

# ... and the opt-out is explicit, not accidental.
{
    my $repo = make_repo();
    my ($rc, $out) = run_gate($repo, '--no-verify-signature');
    is($rc, 0, '--no-verify-signature is the deliberate opt-out') or diag($out);
    like($out, qr/signature check: OFF \(--no-verify-signature\)/,
        '... and the log names the flag that turned it off');
}

# ---- a stale PACKAGING REVISION is caught, not just a wrong upstream version ----------------------
# The manifest pin is matched against the FULL [epoch:]upstream[-revision]. An upstream-only gate
# reported this repo as complete: upstream 1.8.18 is what the pin used to say, and it matches -- while
# the published deb is an older packaging revision than xCAT's own Depends require.
{
    my $repo = make_repo(ipmi_version => '1.8.18-snap202501010000');   # older revision, same upstream
    my ($rc, $out) = run_gate($repo, '--no-verify-signature');
    isnt($rc, 0, 'a stale packaging revision FAILS the gate') or diag($out);
    like($out, qr/VERSION ipmitool-xcat: repo has 1\.8\.18-snap202501010000, manifest pins 1\.8\.18-snap202608211200/,
        '... reported as a VERSION problem naming both revisions');
}

# An EPOCH the pin does not name is likewise a mismatch -- the epoch outranks the version entirely,
# so silently accepting it would let an un-pinned epoch bump through.
{
    my $repo = make_repo(ipmi_version => '2:1.8.18-snap202608211200');
    my ($rc, $out) = run_gate($repo, '--no-verify-signature');
    isnt($rc, 0, 'an epoch the pin does not name FAILS the gate') or diag($out);
    like($out, qr/VERSION ipmitool-xcat: repo has 2:1\.8\.18-snap202608211200/, '... naming the epoch');
}

# ---- a cell with no manifest section is a configuration error, not a free pass --------------------
{
    my $thin = "$tmp/thin-manifest.conf";
    write_file($thin, "[noble-amd64]\nipmitool-xcat=1.8.18\ngoconserver=0.3.3\n"
                    . "grub2-xcat=*\nxcat-genesis-base=2.*\n");
    my $repo = make_repo();
    my ($rc, $out) = run_cmd($^X, $SCRIPT, '--verify-repo', $repo, '--manifest', $thin,
                             '--dists', 'noble', '--arch', 'amd64', '--no-verify-signature');
    isnt($rc, 0, 'an expected cell with no manifest section FAILS (was silently skipped)') or diag($out);
    like($out, qr/NO-MANIFEST section \[noble-ppc64el\]/, '... naming the missing section');
}

done_testing;
