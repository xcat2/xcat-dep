#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/..", "$RealBin/../lib";
use XCAT::NativeInputs qw(load_inputs);
use Test::More;
use MockBuildUtils qw(openeuler_build_target openeuler_repo_subdir install_deps_command
                      install_deps_packages derive_target_from_repo_path read_manifest);

my %manifest = read_manifest("$RealBin/../packages-manifest.conf");
my @cells = (
    ['20.03sp4', '20.03-LTS-SP4', '20.03LTS_SP4', 'x86_64'],
    ['22.03sp4', '22.03-LTS-SP4', '22.03LTS_SP4', 'x86_64'],
    ['24.03sp1', '24.03-LTS-SP1', '24.03LTS_SP1', 'x86_64'],
    ['24.03sp3', '24.03-LTS-SP3', '24.03LTS_SP3', 'x86_64'],
    ['24.03sp4', '24.03-LTS-SP4', '24.03LTS_SP4', 'x86_64'],
    ['24.03', '24.03-LTS', '24.03LTS', 'ppc64le'],
);
for my $cell (@cells) {
    my ($version, $release, undef, $arch) = @$cell;
    my ($base, $sp) = $version =~ /^(\d+\.\d+)(?:sp(\d+))?$/;
    my $native_version = "$base (LTS" . (defined($sp) ? "-SP$sp" : '') . ')';
    my $target = "openeuler-$version-$arch";
    ok(-f "$RealBin/../mock-configs/$target.cfg", "$target has a native mock config");
    ok(exists $manifest{$target}{goconserver}, "$target has a native package manifest");
    is(openeuler_build_target({ID => 'openEuler', VERSION => $native_version}, $arch), $target,
        "$target retains the native service pack");
    is(openeuler_repo_subdir($target), "openeuler$version/$arch", "$target preserves repository provenance");
    for my $suffix ('', '/', '//') {
        my $path = "/repo/openeuler$version/$arch$suffix";
        is(derive_target_from_repo_path($path), $target, "$path selects $target");
    }
}
is(openeuler_build_target({ID => 'rocky', VERSION_ID => '9.6'}, 'x86_64'), undef, 'EL uses existing target selection');
is(openeuler_repo_subdir('alma+epel-10-x86_64'), undef, 'EL uses existing repository layout');
for my $target ('openeuler-24.09-x86_64', 'openeuler-24.03sp0-x86_64', 'openeuler-24.03-ppc64') {
    eval {openeuler_repo_subdir($target)};
    like($@, qr/Unsupported openEuler build target/, "$target is rejected");
}
my @native_install = install_deps_command('openEuler');
is_deeply([@native_install[0..6]], ['dnf', '--setopt=gpgcheck=1', '--setopt=*.gpgcheck=1', '--setopt=strict=1', '--setopt=install_weak_deps=False', '-y', 'install'],
    'native prerequisites require signatures and dependency closure');
ok(grep($_ eq '/usr/bin/systemd-nspawn', @native_install), 'native prerequisites request the mock isolation executable across package splits');
ok(!grep(/epel|crb|codeready/i, @native_install), 'native prerequisites do not enable EL repositories');
is_deeply([install_deps_command('rocky')], ['dnf', '-y', 'install', install_deps_packages('rocky')], 'EL prerequisite command remains unchanged');

for my $path (
    '/repo/openeuler24.09/x86_64',
    '/repo/openeuler24.03sp0/x86_64',
    '/repo/openeuler24.03/ppc64',
    '/repo/openeuler24.03',
    '/repo/openeuler24.03/x86_64/repodata',
    '/repo/notopeneuler24.03/x86_64',
) {
    is(derive_target_from_repo_path($path), undef, "$path has no native target");
}

# xCAT and xCATsn name the netboot loaders and the console backend as Requires on every arch, so a
# package missing from a target section is not a smaller build: it is "nothing provides <pkg>" when
# dnf installs xCAT on the management node. The EL section of the same arch is the reference set,
# because openEuler is rpm-md and installs the same core packages. Both exemptions were measured
# against the built core rpms with rpm -qp --requires, not read off a spec conditional.
my %exempt = (
    'conserver-xcat' => 'xCAT requires goconserver; no core rpm requires conserver-xcat',
    'elilo-xcat'     => 'no core rpm requires elilo-xcat',
);
my $reference = 'alma+epel-10-ppc64le';
ok(scalar keys %{$manifest{$reference}}, "$reference is the reference section and is not empty");
for my $pkg (sort keys %{$manifest{$reference}}) {
    next if $exempt{$pkg};
    ok(exists $manifest{'openeuler-24.03-ppc64le'}{$pkg},
        "openeuler-24.03-ppc64le declares $pkg, which $reference also declares");
}

# A manifest entry alone is not enough. The ppc64le target resolves its whole manifest through the
# native input catalog, which refuses a name no node produces, so the catalog has to declare an
# owner for the package as well.
my $plan = eval { load_inputs("$RealBin/..", $manifest{'openeuler-24.03-ppc64le'}) };
ok($plan, 'every package the ppc64le manifest requires has a native output owner') or diag($@);
done_testing();
