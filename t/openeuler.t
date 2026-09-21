#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/..";
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use JSON::PP qw(decode_json);
use Test::More;
use MockBuildUtils qw(openeuler_build_target openeuler_repo_subdir install_deps_command install_deps_packages);

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

{
    my $tmp = tempdir(CLEANUP => 1);
    open(my $manifest, '>', "$tmp/packages-manifest.conf") or die $!;
    for my $cell (@cells) {
        my ($version, undef, undef, $arch) = @$cell;
        print {$manifest} "[openeuler-$version-$arch]\nnative-fixture-$version=1\n";
    }
    close($manifest) or die $!;
    for my $cell (@cells) {
        my ($version, undef, undef, $arch) = @$cell;
        my $repo = "$tmp/openeuler$version/$arch";
        make_path($repo);
        my $pid = fork();
        die $! unless defined $pid;
        if (!$pid) {
            open(STDOUT, '>', "$tmp/output") or die $!;
            open(STDERR, '>&', \*STDOUT) or die $!;
            exec($^X, "$RealBin/../mockbuild-all.pl", '--verify-repo', $repo, '--repo-root', $tmp) or die $!;
        }
        waitpid($pid, 0);
        isnt($? >> 8, 0, "$version/$arch empty repository fails the full publication gate");
        open(my $output, '<', "$tmp/output") or die $!;
        my $text = do {local $/; <$output>};
        close($output);
        like($text, qr/MISSING native-fixture-\Q$version\E\b/, "$version/$arch path selects its own exact manifest section");
    }
}

SKIP: {
    skip 'native mock Python library and templates required', 66
        if system('python3 -c "import mockbuild.config" >/dev/null 2>&1') != 0
        || !-f '/etc/mock/templates/openeuler-24.03.tpl';
    my $tmp = tempdir(CLEANUP => 1);
    my $loader = "$tmp/load.py";
    open(my $fh, '>', $loader) or die $!;
    print {$fh} <<'PYTHON';
import configparser
import json
from pathlib import Path
import shutil
import sys
import tempfile
from mockbuild.config import load_config

source = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory() as directory:
    config_path = Path(directory)
    (config_path / 'templates').mkdir()
    for parent in ('openeuler-20.03-sp4.tpl', 'openeuler-22.03-sp4.tpl', 'openeuler-24.03.tpl'):
        shutil.copyfile(Path('/etc/mock/templates') / parent, config_path / 'templates' / parent)
    shutil.copyfile(source / 'templates/openeuler-lts-xcat.tpl', config_path / 'templates/openeuler-lts-xcat.tpl')
    result = {}
    for wrapper in sorted(source.glob('openeuler-*.cfg')):
        config = load_config(str(config_path), str(wrapper))
        repos = configparser.ConfigParser(interpolation=None)
        repos.read_string(config['dnf.conf'])
        result[wrapper.stem] = {key: config[key] for key in ('root', 'target_arch', 'legal_host_arches', 'releasever', 'dist', 'use_bootstrap_image')}
        result[wrapper.stem]['repos'] = {section: dict(repos[section]) for section in repos.sections()}
    print(json.dumps(result))
PYTHON
    close($fh) or die $!;
    open(my $pipe, '-|', 'python3', $loader, "$RealBin/../mock-configs") or die $!;
    my $json = do {local $/; <$pipe>};
    close($pipe) or die "native mock config loader failed: $?";
    my $configs = decode_json($json);
    for my $cell (@cells) {
        my ($version, $release, $releasever, $arch) = @$cell;
        my $target = "openeuler-$version-$arch";
        my $config = $configs->{$target};
        is($config->{root}, $target, "$target selects its own buildroot");
        is($config->{target_arch}, $arch, "$target selects its native architecture");
        is_deeply($config->{legal_host_arches}, [$arch], "$target requires a native host");
        is($config->{releasever}, $releasever, "$target retains the release package convention");
        is($config->{dist}, '', "$target retains the native empty dist macro");
        ok(!$config->{use_bootstrap_image}, "$target constructs its bootstrap from signed native RPMs");
        my $repos = $config->{repos};
        my @names = $arch eq 'ppc64le' ? ('OS') : ('OS', 'everything', 'update');
        is_deeply([sort grep {$_ ne 'main'} keys %$repos], [sort @names], "$target selects only published native repositories");
        is($repos->{main}{gpgcheck}, '1', "$target requires native package signatures");
        my $base = "https://repo.openeuler.org/openEuler-$release";
        is_deeply([map {$repos->{$_}{baseurl}} @names], [map {"$base/$_/$arch/"} @names], "$target pins repository URLs to its exact release");
        is_deeply([map {$repos->{$_}{gpgkey}} @names], [map {"$base/OS/$arch/RPM-GPG-KEY-openEuler"} @names], "$target uses the release signing key");
        ok(!grep({$repos->{$_}{gpgcheck} ne '1' || $repos->{$_}{skip_if_unavailable} ne '0'} @names), "$target fails on unsigned packages or unavailable repositories");
    }
}
done_testing();
