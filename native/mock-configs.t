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
    if ($config->{error}) {
        fail("$target loads: $config->{error}");
        next;
    }
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
    ok(!exists $repos->{main}{minrate}, "$target keeps dnf's rate abort, which is what tries a mirror");
    cmp_ok($repos->{main}{timeout}, '>=', 300, "$target waits before it abandons a slow host");
    my $base = "https://repo.openeuler.org/openEuler-$release";
    for my $repo (@names) {
        my @urls = split ' ', $repos->{$repo}{baseurl};
        isnt($urls[0], "$base/$repo/$arch/", "$target does not read $repo from the slowest host first");
        ok(scalar(grep { $_ eq "$base/$repo/$arch/" } @urls),
            "$target still carries the canonical $repo url");
        cmp_ok(scalar @urls, '>', 1, "$target has a fallback for $repo");
        ok(!grep({ $_ !~ m{/openEuler-\Q$release\E/\Q$repo\E/\Q$arch\E/$} } @urls),
            "$target pins every $repo url to its exact release and architecture");
    }
    is_deeply([map {$repos->{$_}{gpgkey}} @names], [map {"$base/OS/$arch/RPM-GPG-KEY-openEuler"} @names], "$target uses the release signing key");
    ok(!grep({$repos->{$_}{gpgcheck} ne '1' || $repos->{$_}{skip_if_unavailable} ne '0'} @names), "$target fails on unsigned packages or unavailable repositories");
}
done_testing();
