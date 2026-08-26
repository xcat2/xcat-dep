#!/usr/bin/perl
# Focused end-to-end test for the PER-TARGET REPO GATE, driving the real
# `mockbuild-all.pl --verify-repo` against a hand-built fixture repo.
#
# What is tested here is the wiring the PR #62 review found: the gate filtered the manifest through
# required_pkgs() with THIS invocation's --skip-* flags, so the flags that say what an invocation
# BUILT also decided what the published repository was allowed to be missing. A repo carrying no
# xCAT-genesis-base therefore passed when the run that verified it had been given --skip-genesis.
#
# The assertions are on the REPORTED PROBLEMS, not on the exit code: a standalone --verify-repo also
# demands a repomd signature by contract, and these fixtures are unsigned, so it exits non-zero
# either way. What distinguishes a fixed gate from a broken one is whether the missing package is
# NAMED.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use File::Temp qw(tempdir);
use File::Path qw(make_path);

my $SCRIPT = "$RealBin/../mockbuild-all.pl";
plan skip_all => "mockbuild-all.pl not found" unless -f $SCRIPT;
plan skip_all => "rpm tooling required"
    unless $^O eq 'linux'
    && !system('sh', '-c', 'command -v rpmbuild >/dev/null 2>&1')
    && !system('sh', '-c', 'command -v rpm      >/dev/null 2>&1')
    && !system('sh', '-c', 'command -v createrepo_c >/dev/null 2>&1');

my $tmp = tempdir(CLEANUP => 1);
my $target = 'alma+epel-10-x86_64';

# build_rpm($name, $version): a minimal noarch rpm, so the gate reads a REAL header name.
sub build_rpm {
    my ($name, $version) = @_;
    my $top = "$tmp/rpmbuild";
    make_path("$top/SPECS");
    my $spec = "$top/SPECS/$name.spec";
    open my $fh, '>', $spec or die $!;
    print $fh <<"SPEC";
Name:           $name
Version:        $version
Release:        1
Summary:        fixture
License:        EPL
BuildArch:      noarch
%description
fixture package for the repository gate test
%install
mkdir -p %{buildroot}/usr/share/$name
%files
/usr/share/$name
SPEC
    close $fh;
    my $rc = system('rpmbuild', '--quiet', '-bb', '--define', "_topdir $top", $spec);
    die "cannot build fixture rpm $name\n" if $rc != 0;
    my ($built) = glob("$top/RPMS/noarch/$name-$version-1.noarch.rpm");
    die "fixture rpm $name not produced\n" unless $built && -f $built;
    return $built;
}

# make_repo(%opt): an indexed repo carrying ipmitool-xcat, and xCAT-genesis-base unless with_genesis
# is turned off.
sub make_repo {
    my (%o) = @_;
    my $dir = "$tmp/repo" . ($o{tag} // '');
    make_path($dir);
    system('cp', build_rpm('ipmitool-xcat', '1.8.18'), $dir) == 0 or die $!;
    system('cp', build_rpm('xCAT-genesis-base-x86_64', '2.18.0'), $dir) == 0 or die $!
        if $o{with_genesis};
    system('createrepo_c', '--quiet', $dir) == 0 or die "createrepo_c failed\n";
    return $dir;
}

# The manifest is the source of truth for what the target must carry.
my $root = "$tmp/repo-root";
make_path($root);
open my $m, '>', "$root/packages-manifest.conf" or die $!;
print $m "[$target]\nipmitool-xcat=1.8.18\nxCAT-genesis-base=2.*\n";
close $m;

sub run_gate {
    my ($repo, @extra) = @_;
    my $cmd = join(' ', map { my $x = $_; $x =~ s/'/'"'"'/g; "'$x'" }
        ($^X, $SCRIPT, '--verify-repo', $repo, '--target', $target, '--repo-root', $root, @extra))
        . ' 2>&1';
    my $out = `$cmd`;
    return ($? >> 8, defined $out ? $out : '');
}

# ---- baseline: a complete repo reports no MISSING package ---------------------------------------
{
    my $repo = make_repo(tag => '-full', with_genesis => 1);
    my (undef, $out) = run_gate($repo);
    unlike($out, qr/MISSING/, 'a complete repo reports no missing package') or diag($out);
}

# ---- --skip-genesis must not excuse a repo that lacks Genesis ------------------------------------
{
    my $repo = make_repo(tag => '-nogenesis');
    my (undef, $out) = run_gate($repo, '--skip-genesis');
    like($out, qr/xCAT-genesis-base/,
        'a repo missing Genesis is reported even when the run passed --skip-genesis') or diag($out);
}

# ---- the same for the compiled deps ---------------------------------------------------------------
{
    my $repo = make_repo(tag => '-nodeps');
    system('rm', '-f', glob("$repo/ipmitool-xcat-*.rpm")) == 0 or die $!;
    system('createrepo_c', '--quiet', '--update', $repo) == 0 or die $!;
    my (undef, $out) = run_gate($repo, '--skip-xcat-dep');
    like($out, qr/ipmitool-xcat/,
        'a repo missing a compiled dep is reported even when the run passed --skip-xcat-dep')
        or diag($out);
}

done_testing();
