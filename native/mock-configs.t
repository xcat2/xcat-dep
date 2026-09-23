#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($RealBin);
use JSON::PP qw(decode_json);
use Test::More;

plan skip_all => 'native Mock Python library and templates required'
    if system('python3 -c "import mockbuild.config" >/dev/null 2>&1') != 0
    || !-f '/etc/mock/templates/openeuler-24.03.tpl';

my @cells = (
    ['20.03sp4', '20.03-LTS-SP4', '20.03LTS_SP4', 'x86_64'],
    ['22.03sp4', '22.03-LTS-SP4', '22.03LTS_SP4', 'x86_64'],
    ['24.03sp1', '24.03-LTS-SP1', '24.03LTS_SP1', 'x86_64'],
    ['24.03sp3', '24.03-LTS-SP3', '24.03LTS_SP3', 'x86_64'],
    ['24.03sp4', '24.03-LTS-SP4', '24.03LTS_SP4', 'x86_64'],
    ['24.03', '24.03-LTS', '24.03LTS', 'ppc64le'],
);
open(my $pipe, '-|', 'python3', "$RealBin/fixtures/mock-configs.py", "$RealBin/../mock-configs") or die $!;
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
done_testing();
