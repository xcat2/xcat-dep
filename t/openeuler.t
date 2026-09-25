#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/..";
use Test::More;
use MockBuildUtils qw(openeuler_build_target openeuler_repo_subdir install_deps_command
                      install_deps_packages derive_target_from_repo_path);

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

done_testing();
