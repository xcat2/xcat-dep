use strict;
use warnings;

use Cwd qw(abs_path);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use JSON::PP;
use Test::More;

use lib "$RealBin/..", "$RealBin/../lib", "$RealBin/lib";
use MockBuildUtils qw(read_manifest);
use XCAT::BuildUtils qw(capture_command command_exists digest_file read_binary write_binary);
use XCAT::GenesisReleaseTest qw(run_capture dies_like);
use XCAT::NativeInputs qw(load_inputs stage_inputs publisher_trust verify_input validate_outputs);

plan skip_all => 'Native Linux RPM tools are required' unless $^O eq 'linux'
    && !grep { !command_exists($_) } qw(rpm rpmkeys rpmbuild rpmsign gpg gpgconf createrepo_c unshare python3);
my $build_user = $ENV{XCAT_TEST_BUILD_USER} // '';
plan skip_all => 'Set XCAT_TEST_BUILD_USER to an unprivileged fixture builder' if $> == 0 && !$build_user;
my $build_uid = $> == 0 ? getpwnam($build_user) : $>;
plan skip_all => 'The fixture builder must be unprivileged' unless defined($build_uid) && $build_uid != 0;
my @rpm_user = $> == 0 ? ('runuser', '-u', $build_user, '--') : ();
my $tmp = tempdir(CLEANUP => !$ENV{XCAT_TEST_KEEP});
diag("native input fixtures: $tmp");
my $repo = abs_path("$RealBin/..");
my $owner = $ENV{XCAT_TEST_COLLECTOR} // "$repo/mockbuild-all.pl";
my $target = 'openeuler-24.03-ppc64le';
my $json = JSON::PP->new->canonical->pretty;
my $epoch = 1788718796;
my $host_arch = capture_command('uname', '-m');
my %manifest = read_manifest("$repo/packages-manifest.conf");
my $production_plan = eval { load_inputs($repo, $manifest{$target}); };
ok($production_plan, 'the shipped full POWER manifest has an executable native input plan') or BAIL_OUT($@);
is($production_plan->{nodes}{'xCAT-genesis-base'}{build_uid}, 0, 'the shipped Genesis owner declares its root assembly exception');
my %homes;
my %keys;
make_path("$tmp/bin", "$tmp/rpmbuild/SPECS");
chmod 0755, $tmp;
chown $build_uid, -1, "$tmp/rpmbuild", "$tmp/rpmbuild/SPECS" if $> == 0;
for my $key (qw(publisher build foreign)) {
    my $home = "$tmp/key-$key";
    $homes{$key} = $home;
    make_path($home);
    chmod 0700, $home;
    is(run_capture("$tmp/key-$key.log", 'gpg', '--homedir', $home, '--batch', '--pinentry-mode', 'loopback',
        '--passphrase', '', '--quick-generate-key', "$key\@example.invalid", 'rsa2048', 'sign', '0'), 0,
        "create private $key key") or BAIL_OUT(read_binary("$tmp/key-$key.log"));
    my $listing = capture_command('gpg', '--homedir', $home, '--with-colons', '--list-keys');
    ($keys{$key}) = $listing =~ /^fpr:::::::::([0-9A-F]+):/m;
    write_binary("$home/public.asc", capture_command('gpg', '--homedir', $home, '--armor', '--export', $keys{$key}));
}
END {
    for my $home (values %homes) {
        run_capture("$home/cleanup.log", 'gpgconf', '--homedir', $home, '--kill', 'gpg-agent') if -d $home;
    }
}

my %rpm;
for my $name (qw(native-leaf native-child publisher-package publisher-elf publisher-arch)) {
    my $arch = $name eq 'publisher-arch' ? $host_arch : 'noarch';
    my $payload = $name eq 'publisher-elf' ? q{printf '\177ELFfixture\n'} : q{printf 'fixture\n'};
    my $spec = <<'SPEC';
Name: NAME
Version: 1
Release: 1.oe2403
Summary: Native input contract fixture
License: MIT
BuildArch: ARCH
%description
Native input contract fixture.
%install
mkdir -p %{buildroot}/usr/share/native-inputs
PAYLOAD > %{buildroot}/usr/share/native-inputs/%{name}
%check
test "$(id -u)" -ne 0
%files
/usr/share/native-inputs/%{name}
SPEC
    $spec =~ s/NAME/$name/;
    $spec =~ s/ARCH/$arch/;
    $spec =~ s/PAYLOAD/$payload/;
    write_binary("$tmp/rpmbuild/SPECS/$name.spec", $spec);
    is(run_capture("$tmp/fixture-$name.log", @rpm_user, 'rpmbuild', '-ba', '--define', "_topdir $tmp/rpmbuild",
        "$tmp/rpmbuild/SPECS/$name.spec"), 0, "build real $name fixture with nonroot check")
        or BAIL_OUT(read_binary("$tmp/fixture-$name.log"));
    $rpm{$name} = "$tmp/rpmbuild/RPMS/$arch/$name-1-1.oe2403.$arch.rpm";
    $rpm{"$name-src"} = "$tmp/rpmbuild/SRPMS/$name-1-1.oe2403.src.rpm";
}

sub signed_copy {
    my ($source, $name, $key) = @_;
    my $dest = "$tmp/$name.rpm";
    copy($source, $dest) or die $!;
    local $ENV{GNUPGHOME} = $homes{$key};
    is(run_capture("$tmp/sign-$name.log", 'rpmsign', '--define', "_gpg_name $keys{$key}",
        '--define', '__gpg /usr/bin/gpg', '--addsign', $dest), 0, "sign $name with $key key")
        or BAIL_OUT(read_binary("$tmp/sign-$name.log"));
    return $dest;
}
my %signed;
for my $name (qw(native-leaf-src native-child-src publisher-package publisher-elf publisher-arch)) {
    $signed{$name} = signed_copy($rpm{$name}, "signed-$name", 'publisher');
}
my $foreign = signed_copy($rpm{'native-leaf-src'}, 'foreign-source', 'foreign');

write_binary("$tmp/bin/wget", <<'PY');
#!/usr/bin/python3
import json, os, pathlib, shutil, sys
args = sys.argv[1:]
source = json.loads(pathlib.Path(os.environ['NATIVE_DOWNLOADS']).read_text())[args[-1]]
with open(os.environ['NATIVE_CALLS'], 'a') as f: f.write(json.dumps({'wget': args[-1]}) + '\n')
shutil.copyfile(source, args[args.index('-O')+1])
PY
write_binary("$tmp/bin/mock", <<'PY');
#!/usr/bin/python3
import json, os, pathlib, shutil, subprocess, sys
args = sys.argv[1:]
call = {'mock': args}
def value(name): return args[args.index(name)+1]
if '--rebuild' in args or '--buildsrpm' in args:
    loader = '''import json, pathlib, sys, mockbuild
from mockbuild.util import load_config
config = load_config('/etc/mock', sys.argv[1], None, 'native-contract', str(pathlib.Path(mockbuild.__file__).parent))
print(json.dumps({'uid': config['chrootuid'], 'dnf': config['dnf.conf']}))
'''
    config = subprocess.run([sys.executable, '-c', loader, value('-r')],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    call['config_rc'] = config.returncode
    if config.returncode:
        print(config.stdout)
        sys.exit(config.returncode)
if '--rebuild' in args:
    name = pathlib.Path(value('--rebuild')).name.split('-1-1.oe2403')[0]
    call['name'] = name
if '--buildsrpm' in args:
    call['spec'] = pathlib.Path(value('--spec')).read_text()
with open(os.environ['NATIVE_CALLS'], 'a') as f: f.write(json.dumps(call) + '\n')
if '--buildsrpm' in args:
    dest = pathlib.Path(value('--resultdir')); dest.mkdir(parents=True, exist_ok=True)
    source = json.loads(pathlib.Path(os.environ['NATIVE_OUTPUTS']).read_text())['native-leaf'][1]
    shutil.copyfile(source, dest / pathlib.Path(source).name)
    sys.exit(0)
if '--rebuild' not in args: sys.exit(0)
if name == os.environ.get('NATIVE_FAIL'): sys.exit(42)
dest = pathlib.Path(value('--resultdir')); dest.mkdir(parents=True, exist_ok=True)
if name == os.environ.get('NATIVE_EMPTY'): sys.exit(0)
fixtures = json.loads(pathlib.Path(os.environ['NATIVE_OUTPUTS']).read_text())
for source in fixtures[name]: shutil.copyfile(source, dest / pathlib.Path(source).name)
PY
chmod 0755, "$tmp/bin/wget", "$tmp/bin/mock";
local $ENV{PATH} = "$tmp/bin:$ENV{PATH}";
local $ENV{NATIVE_DOWNLOADS} = "$tmp/downloads.json";
local $ENV{NATIVE_OUTPUTS} = "$tmp/outputs.json";
local $ENV{NATIVE_CALLS} = "$tmp/calls.jsonl";
write_binary($ENV{NATIVE_OUTPUTS}, $json->encode({map { $_ => [$rpm{$_}, $rpm{"$_-src"}] } qw(native-leaf native-child)}));

sub catalog {
    return {version => 1, target => $target, publisher_key => {
        path => 'openeuler/publisher.asc', sha256 => digest_file("$homes{publisher}/public.asc"),
        fingerprint => $keys{publisher}}, build_inputs => [], inputs => [
        {name => 'native-leaf', type => 'srpm', build_uid => 1000, needs => [], outputs => ['native-leaf'],
         url => 'https://repo.openeuler.org/openEuler-24.03-LTS/source/Packages/native-leaf-1-1.oe2403.src.rpm',
         sha256 => digest_file($signed{'native-leaf-src'})},
        {name => 'native-child', type => 'srpm', build_uid => 1000, needs => ['native-leaf'], outputs => ['native-child'],
         url => 'https://repo.openeuler.org/openEuler-24.03-LTS/source/Packages/native-child-1-1.oe2403.src.rpm',
         sha256 => digest_file($signed{'native-child-src'})},
        {name => 'publisher-package', type => 'publisher', needs => [], outputs => ['publisher-package'],
         url => 'https://repo.openeuler.org/openEuler-24.03-LTS/Everything/x86_64/Packages/publisher-package-1-1.oe2403.noarch.rpm',
         sha256 => digest_file($signed{'publisher-package'})}]};
}

sub prepare {
    my ($name, $mutate) = @_;
    my $root = "$tmp/$name source";
    make_path("$root/openeuler", "$root/mock-configs/templates");
    my $data = catalog();
    $mutate->($data) if $mutate;
    copy("$homes{publisher}/public.asc", "$root/openeuler/publisher.asc") or die $!;
    write_binary("$root/openeuler/24.03-ppc64le.inputs.json", $json->encode($data));
    write_binary("$root/packages-manifest.conf", "[$target]\nnative-child=1\npublisher-package=1\n");
    write_binary("$root/Gitepoch", "$epoch\n");
    write_binary("$root/Gitinfo", ('a' x 40) . "\n");
    write_binary("$root/mock-configs/$target.cfg", "config_opts['root'] = 'native-contract'\nconfig_opts['dnf.conf'] = ''\n");
    my %downloads = map { $_->{url} => $signed{$_->{name} . ($_->{type} eq 'srpm' ? '-src' : '')} } @{$data->{inputs}};
    write_binary($ENV{NATIVE_DOWNLOADS}, $json->encode(\%downloads));
    unlink $ENV{NATIVE_CALLS};
    return ($root, $data);
}

my ($valid) = prepare('valid');
my $plan = load_inputs($valid, {'native-child' => '1', 'publisher-package' => '1'});
is_deeply($plan->{order}, [qw(native-leaf native-child publisher-package)], 'public plan orders prerequisites before consumers');
stage_inputs($plan, "$tmp/valid-stage");
is(digest_file($plan->{nodes}{'publisher-package'}{staged}), digest_file($signed{'publisher-package'}), 'publisher admission preserves signed bytes');
is(digest_file($plan->{nodes}{'native-leaf'}{staged}), digest_file($signed{'native-leaf-src'}), 'source admission preserves signed bytes');
ok(-f "$tmp/valid-stage/inputs.json", 'admission records input identity and catalog digest');
validate_outputs($plan->{nodes}{'native-leaf'}, [$rpm{'native-leaf'}], 1);
pass('declared real native output passes ownership validation');
dies_like(sub { validate_outputs($plan->{nodes}{'native-leaf'}, [$rpm{'native-child'}], 1) }, qr/Unexpected output/, 'wrong owner output fails');
dies_like(sub { validate_outputs($plan->{nodes}{'native-leaf'}, [$rpm{'native-leaf'}, $rpm{'native-leaf'}], 1) }, qr/Duplicate output/, 'duplicate output fails');
dies_like(sub { validate_outputs($plan->{nodes}{'native-leaf'}, [], 1) }, qr/Missing output/, 'empty successful build fails');

my @bad = (
    ['cycle', sub { $_[0]{inputs}[0]{needs} = ['native-child'] }, qr/Cyclic native dependency/],
    ['missing', sub { $_[0]{inputs}[0]{needs} = ['absent'] }, qr/Missing native dependency/],
    ['conflict', sub { $_[0]{inputs}[1]{outputs} = ['native-leaf'] }, qr/Conflicting output ownership/],
    ['uid', sub { $_[0]{inputs}[0]{build_uid} = 0 }, qr/Invalid native build UID/],
    ['foreign-release', sub { $_[0]{inputs}[2]{url} =~ s/LTS\//LTS-SP3\// }, qr/Publisher binary must be exact GA/],
    ['unsafe-define', sub { $_[0]{inputs}[0]{defines} = ['llvmjit 0; touch injected'] }, qr/Invalid native spec definition/],
    ['missing-patch', sub { $_[0]{inputs}[0]{patches} = [{path => 'absent.patch', sha256 => 'a' x 64}] }, qr/Missing input/],
    ['source-needs-owner', sub {
        push @{$_[0]{inputs}}, {name => 'goconserver', type => 'owner', build_uid => 1000,
            outputs => ['goconserver'], needs => []};
        $_[0]{inputs}[0]{needs} = ['goconserver'];
    }, qr/Unsupported native execution edge/],
    ['owner-needs-owner', sub {
        push @{$_[0]{inputs}}, {name => 'goconserver', type => 'owner', build_uid => 1000,
            outputs => ['goconserver'], needs => ['ipmitool-xcat']},
            {name => 'ipmitool-xcat', type => 'owner', build_uid => 1000, outputs => ['ipmitool-xcat'], needs => []};
    }, qr/Unsupported native execution edge/],
);
for my $case (@bad) {
    my ($root) = prepare($case->[0], $case->[1]);
    dies_like(sub { load_inputs($root, {'native-child' => '1'}) }, $case->[2], "$case->[0] fails before input acquisition");
    ok(!-f $ENV{NATIVE_CALLS}, "$case->[0] executes no downloader or builder");
}

for my $case (
    ['bad-hash', $signed{'native-leaf-src'}, 'b' x 64, qr/SHA256 mismatch/],
    ['unsigned', $rpm{'native-leaf-src'}, digest_file($rpm{'native-leaf-src'}), qr/Publisher signature missing/],
    ['wrong-key', $foreign, digest_file($foreign), qr/Command failed/],
) {
    my %node = %{$plan->{nodes}{'native-leaf'}};
    $node{sha256} = $case->[2];
    dies_like(sub { verify_input($plan, \%node, $case->[1], $plan->{trust_db}) }, $case->[3], "$case->[0] cannot enter a native root");
}
for my $case (['publisher-elf', qr/ELF payload/], ['publisher-arch', qr/not a noarch binary/]) {
    my %node = (%{$plan->{nodes}{'publisher-package'}}, name => $case->[0], sha256 => digest_file($signed{$case->[0]}));
    dies_like(sub { verify_input($plan, \%node, $signed{$case->[0]}, $plan->{trust_db}) }, $case->[1], "$case->[0] is rejected using the real RPM payload/header");
}

{
    my ($root) = prepare('standalone-signers');
    my $dest = "$tmp/standalone-repo";
    make_path($dest);
    my $generated = signed_copy($rpm{'native-child'}, 'generated-build-signer', 'build');
    my $publisher = "$dest/publisher-package-1-1.oe2403.noarch.rpm";
    my $child = "$dest/native-child-1-1.oe2403.noarch.rpm";
    copy($signed{'publisher-package'}, $publisher) or die $!;
    copy($generated, $child) or die $!;
    is(run_capture("$tmp/standalone-createrepo.log", 'createrepo_c', $dest), 0,
        'create metadata for the mixed-signer repository');
    is(run_capture("$tmp/standalone-sign.log", 'gpg', '--homedir', $homes{build}, '--batch', '--yes',
        '--armor', '--detach-sign', '--default-key', $keys{build}, "$dest/repodata/repomd.xml"), 0,
        'sign repository metadata with the build key');
    my @verify = ($^X, $owner, '--repo-root', $root, '--target', $target,
        '--verify-repo', $dest, '--gpg-home', $homes{build}, '--gpg-key-name', $keys{build});
    is(run_capture("$tmp/standalone-valid.log", @verify), 0,
        'standalone native verification accepts each declared signing authority')
        or diag(read_binary("$tmp/standalone-valid.log"));
    my $resigned = signed_copy($rpm{'publisher-package'}, 'publisher-build-signer', 'build');
    copy($resigned, $publisher) or die $!;
    isnt(run_capture("$tmp/standalone-resigned.log", @verify), 0,
        'standalone verification rejects a publisher package signed by the build key');
    like(read_binary("$tmp/standalone-resigned.log"), qr/SHA256 mismatch/,
        'the publisher failure identifies the changed pinned bytes');
    copy($signed{'publisher-package'}, $publisher) or die $!;
    my $wrong_generated = signed_copy($rpm{'native-child'}, 'generated-publisher-signer', 'publisher');
    copy($wrong_generated, $child) or die $!;
    isnt(run_capture("$tmp/standalone-wrong-generated.log", @verify), 0,
        'standalone verification rejects the publisher key for generated output');
    like(read_binary("$tmp/standalone-wrong-generated.log"), qr/NOKEY|WRONGKEY|checksig/i,
        'the generated output failure identifies the unexpected signer');
    copy($generated, $child) or die $!;
    is(run_capture("$tmp/standalone-restored.log", @verify), 0,
        'restoring both original package signatures restores standalone acceptance');
    ok(!-f $ENV{NATIVE_CALLS}, 'standalone verification runs no downloader or builder');
}

my @namespace = ('unshare', ($> == 0 ? () : ('--user', '--map-root-user')), '--mount', '--propagation', 'private');
my $can_owner = $host_arch eq 'ppc64le'
    && run_capture("$tmp/mock-loader.log", 'python3', '-c', 'from mockbuild.util import load_config') == 0
    && run_capture("$tmp/namespace.log", @namespace, 'true') == 0;
SKIP: {
    skip 'Whole native owner requires POWER, native Mock and a private mount namespace', 52 unless $can_owner;
    for my $case (@bad[0..2, 7, 8]) {
        my ($root) = prepare("owner-$case->[0]", $case->[1]);
        my $rc = run_capture("$tmp/owner-$case->[0].log", @namespace,
            $^X, $owner, '--repo-root', $root, '--target', $target, '--xcat-source', $root,
            '--output', "$tmp/owner-$case->[0]-output", '--skip-genesis', '--skip-tarball', '--gpg-sign',
            '--gpg-home', $homes{build}, '--gpg-key-name', $keys{build}, '--scrub-all-chroots');
        isnt($rc, 0, "$case->[0] fails the whole owner");
        like(read_binary("$tmp/owner-$case->[0].log"), $case->[2], "$case->[0] reports its graph error at the owner boundary");
        ok(!-f $ENV{NATIVE_CALLS}, "$case->[0] precedes even mock scrub");
    }
    for my $scenario ('success', 'failed-child', 'empty-child', 'patch-path') {
        my ($root, $data) = prepare("owner-$scenario");
        if ($scenario eq 'patch-path') {
            write_binary("$root/native.patch", "--- a/native-leaf.spec\n+++ b/native-leaf.spec\n@@ -4 +4 @@\n-Summary: Native input contract fixture\n+Summary: Patched native input contract fixture\n");
            $data->{inputs}[0]{patches} = [{path => 'native.patch', sha256 => digest_file("$root/native.patch")}];
            $data->{inputs}[0]{defines} = ['llvmjit 0', 'runselftest 1'];
            write_binary("$root/openeuler/24.03-ppc64le.inputs.json", $json->encode($data));
        }
        my $out = "$tmp/owner-$scenario-output";
        my $dest = "$out/xcat-dep/openeuler24.03/ppc64le";
        make_path($dest, "$root/etc-mock");
        copy("$root/mock-configs/$target.cfg", "$root/etc-mock/$target.cfg") or die $!;
        write_binary("$dest/sentinel", 'old repository');
        local $ENV{NATIVE_FAIL} = $scenario eq 'failed-child' ? 'native-child' : '';
        local $ENV{NATIVE_EMPTY} = $scenario eq 'empty-child' ? 'native-child' : '';
        local $ENV{MOCKBUILD_ALL_MOUNTNS} = 1;
        my @cmd = ($^X, $owner, '--repo-root', $root, '--target', $target, '--xcat-source', $root,
            '--output', $out, '--run-id', 'contract', '--skip-genesis', '--skip-tarball', '--gpg-sign',
            '--gpg-home', $homes{build}, '--gpg-key-name', $keys{build}, '--max-parallel', 1);
        my $rc = run_capture("$tmp/owner-$scenario.log", @namespace,
            'sh', '-c', 'mount --bind "$1" /etc/mock && shift && exec "$@"', 'native-test', "$root/etc-mock", @cmd);
        my @calls = -f $ENV{NATIVE_CALLS} ? map { JSON::PP->new->decode($_) } split /\n/, read_binary($ENV{NATIVE_CALLS}) : ();
        my @built = map { $_->{name} } grep { exists $_->{name} } @calls;
        is_deeply(\@built, ['native-leaf', 'native-child'], "$scenario executes the prerequisite then its dependent through the owner");
        is_deeply([map { $_->{config_rc} } grep { exists $_->{config_rc} } @calls],
            [map { 0 } 1 .. ($scenario eq 'patch-path' ? 3 : 2)],
            "$scenario loads generated configurations through the installed native Mock");
        my $publisher = "$dest/publisher-package-1-1.oe2403.noarch.rpm";
        if ($scenario eq 'success' || $scenario eq 'patch-path') {
            is($rc, 0, 'whole owner signs and collects the completed native chain') or diag(read_binary("$tmp/owner-$scenario.log"));
            is(-f $publisher ? digest_file($publisher) : '', digest_file($signed{'publisher-package'}), 'final publisher package remains byte-identical');
            ok(-f "$dest/native-child-1-1.oe2403.noarch.rpm", 'dependent native output reaches the repository');
            ok(!-f "$dest/native-leaf-1-1.oe2403.noarch.rpm", 'build-only native prerequisite stays private');
            if ($scenario eq 'success' && $rc == 0) {
                my @verify = ($^X, $owner, '--repo-root', $root, '--target', $target,
                    '--verify-repo', $dest, '--gpg-home', $homes{build}, '--gpg-key-name', $keys{build});
                is(run_capture("$tmp/final-verify.log", @verify), 0, 'standalone gate accepts the declared publisher and build signers');
                copy($publisher, "$tmp/publisher-preserved.rpm") or die $!;
                {
                    local $ENV{GNUPGHOME} = $homes{build};
                    is(run_capture("$tmp/publisher-resign.log", 'rpmsign', '--define', "_gpg_name $keys{build}",
                        '--define', '__gpg /usr/bin/gpg', '--resign', $publisher), 0, 'negative control re-signs a publisher copy with the build key');
                }
                isnt(run_capture("$tmp/final-resigned-publisher.log", @verify), 0, 'collector rejects a re-signed publisher input even with an otherwise allowed key');
                like(read_binary("$tmp/final-resigned-publisher.log"), qr/SHA256 mismatch/, 'the publisher failure identifies lost byte identity');
                copy("$tmp/publisher-preserved.rpm", $publisher) or die $!;
                is(digest_file($publisher), digest_file($signed{'publisher-package'}), 'restore the original publisher bytes after the negative control');
                my $generated = "$dest/native-child-1-1.oe2403.noarch.rpm";
                copy($generated, "$tmp/generated-preserved.rpm") or die $!;
                {
                    local $ENV{GNUPGHOME} = $homes{publisher};
                    is(run_capture("$tmp/generated-resign.log", 'rpmsign', '--define', "_gpg_name $keys{publisher}",
                        '--define', '__gpg /usr/bin/gpg', '--resign', $generated), 0, 'negative control signs generated output with the publisher key');
                }
                isnt(run_capture("$tmp/final-wrong-generated-key.log", @verify), 0, 'collector rejects the publisher key for generated outputs');
                like(read_binary("$tmp/final-wrong-generated-key.log"), qr/NOKEY|WRONGKEY|checksig/i, 'the generated output failure reports its signer mismatch');
                copy("$tmp/generated-preserved.rpm", $generated) or die $!;
            }
            if ($scenario eq 'patch-path') {
                my @prepared = grep { exists $_->{spec} } @calls;
                is(scalar @prepared, 1, 'tracked patch uses the existing native buildsrpm path once');
                like($prepared[0]{spec} // '', qr/^Summary: Patched native input contract fixture$/m,
                    'the real patch modifies the extracted source spec');
                my @args = @{$prepared[0]{mock} // []};
                ok(grep($_ eq 'llvmjit 0', @args), 'vendor disable option remains one quoted argument');
                ok(grep($_ eq 'runselftest 1', @args), 'vendor test option remains enabled');
                my $original = "$out/mockbuild-all/$target-contract/native-inputs/native-leaf/native-leaf-1-1.oe2403.src.rpm";
                is(digest_file($original), digest_file($signed{'native-leaf-src'}), 'patch preparation preserves the original signed source');
            }
        } else {
            isnt($rc, 0, "$scenario fails collection");
            is(read_binary("$dest/sentinel"), 'old repository', "$scenario preserves the old repository");
            ok(!-f $publisher, "$scenario does not publish partial publisher inputs");
            ok(!-f "$dest/native-child-1-1.oe2403.noarch.rpm", "$scenario does not publish partial native outputs");
        }
    }
}

done_testing();
