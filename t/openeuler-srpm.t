use strict;
use warnings;

use Cwd qw(abs_path cwd);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use JSON::PP qw(decode_json);
use Test::More;

use lib "$RealBin/../lib", "$RealBin/lib";
use XCAT::BuildUtils qw(capture_command command_exists digest_file read_binary write_binary);
use XCAT::GenesisReleaseTest qw(run_capture);

plan skip_all => 'Linux RPM tools and user namespaces required'
    unless $^O eq 'linux' && !grep { !command_exists($_) } qw(rpm rpmkeys rpmbuild createrepo_c unshare python3 gpg gpgconf);
my $tmp = tempdir(CLEANUP => 1);
my @namespace = $> == 0 ? () : ('unshare', '--user', '--map-root-user');
plan skip_all => 'User namespace unavailable for the collector root check'
    if @namespace && run_capture("$tmp/namespace.log", @namespace, 'true') != 0;
my $collector = $ENV{XCAT_TEST_COLLECTOR} // abs_path("$RealBin/../mockbuild-all.pl");
my $source = abs_path("$RealBin/../python-scp/python-scp-0.14.5-1.oe2403.src.rpm");
my $hash = '3461d2a3fe0122cac2893d8465ad1271ae21e5570a31d4402e3f887ef545a0e8';
my $arch = capture_command('uname', '-m');
plan skip_all => 'Source package closure is selected only for x86_64' if $arch ne 'x86_64';
is(digest_file($source), $hash, 'the official source RPM is pinned');
my $epoch = 1788718796;
my $target = 'openeuler-20.03sp4-x86_64';
my $key_home = "$tmp/gnupg";
my $key_name = 'source-contract@example.invalid';
make_path("$tmp/bin", "$tmp/fixture/SPECS", $key_home);
chmod 0700, $key_home;
if ($ENV{XCAT_TEST_GENESIS_SIGNING_ONLY}) {
    test_genesis_signing();
    done_testing();
    exit;
}
is(run_capture("$tmp/key.log", 'gpg', '--homedir', $key_home, '--batch', '--pinentry-mode', 'loopback',
    '--passphrase', '', '--quick-generate-key', $key_name, 'rsa2048', 'sign', '0'), 0,
    'create a private ephemeral signing identity for the repository gate')
    or BAIL_OUT(read_binary("$tmp/key.log"));
END {
    run_capture("$tmp/key-cleanup.log", 'gpgconf', '--homedir', $key_home, '--kill', 'gpg-agent')
        if defined($key_home) && -d $key_home;
}
write_binary("$tmp/fixture/SPECS/python3-scp.spec", <<'SPEC');
Name: python3-scp
Version: 0.14.5
Release: 1
Summary: Collector contract fixture
License: MIT
BuildArch: noarch
%description
Collector contract fixture.
%install
mkdir -p %{buildroot}/usr/share/scp-contract
printf 'fixture\n' > %{buildroot}/usr/share/scp-contract/payload
%files
/usr/share/scp-contract
SPEC
is(run_capture("$tmp/fixture.log", 'rpmbuild', '--quiet', '-ba', '--define', "_topdir $tmp/fixture",
    "$tmp/fixture/SPECS/python3-scp.spec"), 0, 'build real RPM fixtures for the command boundary')
    or BAIL_OUT(read_binary("$tmp/fixture.log"));
write_binary("$tmp/bin/mock", <<'PYTHON');
#!/usr/bin/python3
import hashlib, json, os, pathlib, shutil, sys
args = sys.argv[1:]
entry = {'argv': args}
def option(name):
    return args[args.index(name) + 1]
if '-r' in args and pathlib.Path(option('-r')).is_file():
    entry['config'] = pathlib.Path(option('-r')).read_text()
if '--spec' in args:
    entry['spec'] = pathlib.Path(option('--spec')).read_text()
if '--rebuild' in args:
    src = pathlib.Path(option('--rebuild'))
    entry['source'] = str(src)
    entry['sha256'] = hashlib.sha256(src.read_bytes()).hexdigest()
with open(os.environ['SCP_CALLS'], 'a') as stream:
    stream.write(json.dumps(entry) + '\n')
if any(x.startswith('--scrub=') for x in args):
    sys.exit(0)
if '--buildsrpm' in args:
    dest = pathlib.Path(option('--resultdir')); dest.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(os.environ['SCP_FIXTURE_SOURCE'], dest / 'python3-scp-0.14.5-1.src.rpm')
    sys.exit(0)
if os.environ.get('SCP_MUTATE_SOURCE'):
    with open(os.environ['SCP_MUTATE_SOURCE'], 'ab') as stream:
        stream.write(b'changed after staging')
if os.environ.get('SCP_BUILD_STATUS', '43') != '0':
    sys.exit(43)
if os.environ.get('SCP_EMPTY_OUTPUT') != '1':
    dest = pathlib.Path(option('--resultdir')); dest.mkdir(parents=True, exist_ok=True)
    for key in ('SCP_FIXTURE_BINARY', 'SCP_FIXTURE_SOURCE'):
        source = pathlib.Path(os.environ[key]); shutil.copyfile(source, dest / source.name)
PYTHON
chmod 0755, "$tmp/bin/mock";

sub scenario {
    my ($name, %opt) = @_;
    my $root = "$tmp/$name source";
    my $out = "$tmp/$name output";
    my $repo = "$tmp/$name-repo";
    my $selected = $opt{target} // $target;
    my $manifest = $opt{packages} // 'python3-scp=0.14.5';
    make_path("$root/python-scp", "$root/grub2-xcat", "$repo/openeuler20.03sp4/x86_64");
    write_binary("$root/packages-manifest.conf", "[$selected]\n$manifest\n");
    write_binary("$root/Gitinfo", ('a' x 40) . "-dirty-snapshot-" . ('b' x 64) . "\n");
    write_binary("$root/Gitepoch", "$epoch\n");
    write_binary("$root/buildrpms.pl", "die 'Genesis dry-run must not execute its child';\n");
    write_binary("$root/grub2-xcat/grub2-xcat.spec", "Name: grub2-xcat\nRelease: 1\n");
    write_binary("$root/grub2-xcat/mockbuild.pl", <<'PERL');
use strict;
use warnings;
use JSON::PP qw(encode_json);
open my $fh, '>>', $ENV{SCP_CALLS} or die $!;
print {$fh} encode_json({script => 'grub2-xcat', argv => \@ARGV}) . "\n";
close $fh or die $!;
exit 41;
PERL
    my $input = "$root/python-scp/" . (split m{/}, $source)[-1];
    copy($source, $input) or die $! unless $opt{missing};
    write_binary($input, 'corrupt') if $opt{corrupt};
    write_binary("$repo/openeuler20.03sp4/x86_64/sentinel", 'previous repository');
    local $ENV{PATH} = "$tmp/bin:$ENV{PATH}";
    local $ENV{MOCKBUILD_ALL_MOUNTNS} = 1;
    local $ENV{SCP_CALLS} = "$tmp/$name calls.jsonl";
    local $ENV{SCP_BUILD_STATUS} = $opt{success} ? '0' : '43';
    local $ENV{SCP_EMPTY_OUTPUT} = $opt{empty} // '';
    local $ENV{SCP_MUTATE_SOURCE} = $opt{mutate} ? $input : '';
    local $ENV{SCP_FIXTURE_BINARY} = "$tmp/fixture/RPMS/noarch/python3-scp-0.14.5-1.noarch.rpm";
    local $ENV{SCP_FIXTURE_SOURCE} = "$tmp/fixture/SRPMS/python3-scp-0.14.5-1.src.rpm";
    local $ENV{HOME} = $root;
    local $ENV{GNUPGHOME} = $opt{env_home} // '';
    my @options = @{$opt{options} // []};
    unshift @options, '--gpg-sign', '--gpg-key-name', $key_name,
        ($opt{default_home} ? () : ('--gpg-home', $opt{key_home} // $key_home))
        if !$opt{unsigned} && $selected =~ /^openeuler-/;
    my $rc = run_capture("$tmp/$name.log", @namespace, $^X, $collector,
        '--repo-root', $root, '--xcat-source', $root, '--target', $selected,
        '--output', $out, '--repo-dep', $repo, '--run-id', 'source-contract',
        '--build-timestamp', $epoch, '--max-parallel', 1, '--parallel-builds', 1,
        '--skip-genesis', '--skip-perl', '--skip-tarball', @options);
    my @calls = -f $ENV{SCP_CALLS}
        ? map { decode_json($_) } split /\n/, read_binary($ENV{SCP_CALLS}) : ();
    return {rc => $rc, calls => \@calls, log => read_binary("$tmp/$name.log"), input => $input,
        repo => $repo, out => $out, root => $root};
}

my $selected = scenario('selected');
isnt($selected->{rc}, 0, 'a failed native source rebuild fails the full owner');
my @builds = grep { grep { $_ eq '--rebuild' } @{$_->{argv}} } @{$selected->{calls}};
is(scalar @builds, 1, 'the exact native manifest selects one source rebuild');
if (@builds) {
    my $call = $builds[0];
    like($call->{config}, qr/\Ainclude\('\/etc\/mock\/\Q$target\E\.cfg'\)\n/,
        'the source rebuild includes the exact native target');
    like($call->{config}, qr/\Qconfig_opts['environment']['SOURCE_DATE_EPOCH'] = '$epoch'\E/,
        'the epoch enters the mock build environment');
    unlike($call->{config}, qr/epel|forcearch|bootstrap_image/, 'the overlay introduces no foreign target policy');
    isnt($call->{source}, $selected->{input}, 'mock consumes a private staged source');
    is($call->{sha256}, $hash, 'the staged source retains the official digest');
    my %args;
    for my $i (0 .. $#{$call->{argv}} - 1) { $args{$call->{argv}[$i]} = $call->{argv}[$i + 1]; }
    like($args{'--uniqueext'}, qr/^mba-01-openeuler-20\.03-[0-9a-f]{8}-python3-scp$/,
        'mock uses the existing bounded target, run digest and package suffix');
    like($args{'--resultdir'}, qr/\Q$target\E-source-contract\/build-results\/python3-scp\z/,
        'result collection remains target and package specific');
    for my $macro ('use_source_date_epoch_as_buildtime 1', 'clamp_mtime_to_source_date_epoch 1', '_buildhost xcat-build') {
        ok(grep($_ eq $macro, @{$call->{argv}}), "mock retains deterministic macro $macro");
    }
}
like($selected->{log}, qr/required build step|every build step failed/, 'mock failure reaches the owner failure gate');
is(read_binary("$selected->{repo}/openeuler20.03sp4/x86_64/sentinel"), 'previous repository',
    'failed source build preserves the previous repository');

for my $case (['corrupt', 'SHA256 mismatch'], ['missing', 'Missing source RPM']) {
    my $result = scenario($case->[0], $case->[0] => 1, options => ['--scrub-all-chroots']);
    isnt($result->{rc}, 0, "$case->[0] selected source fails");
    like($result->{log}, qr/\Q$case->[1]\E/, "$case->[0] source identifies the input failure");
    is_deeply($result->{calls}, [], "$case->[0] source fails before any mock action, including scrub");
}
my $staged = scenario('immutable-stage', mutate => 1);
isnt(digest_file($staged->{input}), $hash, 'the command double changes the original after staging');
my @staged_builds = grep { exists $_->{sha256} } @{$staged->{calls}};
is(scalar @staged_builds, 1, 'the staged source reaches mock once');
is($staged_builds[0]{sha256}, $hash, 'changing the original does not change the build input') if @staged_builds;

for my $other ('openeuler-24.03sp3-x86_64', 'openeuler-24.03sp4-x86_64', 'alma+epel-9-x86_64') {
    my $result = scenario("unselected-$other", target => $other, packages => 'grub2-xcat=1.0', missing => 1);
    isnt($result->{rc}, 0, "$other propagates the existing script failure");
    my @script = grep { ($_->{script} // '') eq 'grub2-xcat' } @{$result->{calls}};
    is(scalar @script, 1, "$other keeps the existing script builder");
    is(scalar(grep { exists $_->{source} } @{$result->{calls}}), 0, "$other does not select the source RPM");
    unlike($result->{log}, qr/Missing source RPM|SHA256 mismatch/, "$other does not require the unselected source input");
    if (@script) {
        my %args = @{$script[0]{argv}};
        is($args{'--mock-cfg'}, $other, "$other preserves the script target argument");
        is($args{'--build-timestamp'}, "$epoch", "$other preserves the script epoch argument");
    }
}
my $absent = scenario('native-manifest-absence', packages => 'grub2-xcat=1.0', missing => 1);
is(scalar(grep { exists $_->{source} } @{$absent->{calls}}), 0, '20 SP4 also requires explicit manifest selection');
unlike($absent->{log}, qr/Missing source RPM/, 'an absent native manifest entry needs no source input');
my $cross = scenario('cross', target => 'openeuler-24.03-ppc64le');
isnt($cross->{rc}, 0, 'native cross-architecture source build is rejected');
like($cross->{log}, qr/requires a ppc64le build host/, 'cross rejection names the native host requirement');
is_deeply($cross->{calls}, [], 'cross rejection precedes every build command');

my $dry = scenario('dry', unsigned => 1, options => ['--dry-run']);
is($dry->{rc}, 0, 'the selected source has a successful dry-run plan');
like($dry->{log}, qr/--rebuild.*python-scp-0\.14\.5-1\.oe2403\.src\.rpm/, 'dry run reports the source rebuild');
is_deeply($dry->{calls}, [], 'dry run executes no mock action');
ok(!-d "$dry->{out}/mockbuild-all/$target-source-contract/source-rpms", 'dry run stages no source or mock overlay');
my $restamp = scenario('restamp', options => ['--build-number', 7]);
isnt($restamp->{rc}, 0, 'restamped rebuild failure remains fatal');
my @sources = grep { exists $_->{spec} } @{$restamp->{calls}};
is(scalar @sources, 1, 'a build number first creates one native source RPM');
like($sources[0]{spec}, qr/^Release:\s+1\.snap202609061819\.7\s*$/m,
    'source spec reuses the existing release suffix policy') if @sources;
my @restamped = grep { exists $_->{source} } @{$restamp->{calls}};
is(scalar @restamped, 1, 'the generated source RPM is rebuilt once');
like($restamped[0]{source}, qr/restamp-srpm\/python3-scp-0\.14\.5-1\.src\.rpm\z/,
    'binary build consumes the new source RPM') if @restamped;
is(digest_file($restamp->{input}), $hash, 'Release restamping preserves the official input bytes');

my $empty = scenario('empty', success => 1, empty => 1);
isnt($empty->{rc}, 0, 'mock success without an RPM cannot close the owner build');
like($empty->{log}, qr/No binary RPMs were collected/, 'empty results reach the existing collection gate');
for my $skip (0, 1) {
    my $unsigned = scenario("unsigned-$skip", unsigned => 1, success => 1,
        options => ['--no-verify-repo', ($skip ? ('--skip-build', '--collect-dir', "$tmp/fixture/RPMS/noarch") : ())]);
    isnt($unsigned->{rc}, 0, 'unsigned native publication is rejected even when verification is disabled');
    like($unsigned->{log}, qr/openEuler repository publication requires --gpg-sign/, 'the owner reports the signing requirement');
    is_deeply($unsigned->{calls}, [], 'unsigned publication fails before every mock action');
    my $sentinel = "$unsigned->{repo}/openeuler20.03sp4/x86_64/sentinel";
    is(-f $sentinel ? read_binary($sentinel) : '', 'previous repository', 'rejection preserves the previous repository');
    my $metadata = "$unsigned->{repo}/openeuler20.03sp4/x86_64/xcat-dep.repo";
    is(-f $metadata ? read_binary($metadata) : '', '', 'rejection emits no misleading native repository configuration');
}
my $collected = scenario('collection', success => 1, options => ['--no-verify-repo']);
is($collected->{rc}, 0, 'the debug collection path accepts successful RPM-producing command output')
    or diag($collected->{log});
my $published = "$collected->{repo}/openeuler20.03sp4/x86_64/python3-scp-0.14.5-1.noarch.rpm";
ok(-f $published, 'native binary reaches the exact repository subdirectory');
is(capture_command('rpm', '-qp', '--qf', '%{SIGMD5}', $published),
    capture_command('rpm', '-qp', '--qf', '%{SIGMD5}', "$tmp/fixture/RPMS/noarch/python3-scp-0.14.5-1.noarch.rpm"),
    'signing preserves the collected RPM header and payload digest') if -f $published;
ok(-s "$collected->{repo}/openeuler20.03sp4/x86_64/repodata/repomd.xml.key",
    'signed native publication exports its configured repository key');
ok(-f "$collected->{out}/mockbuild-all/$target-source-contract/repo-src/python3-scp-0.14.5-1.src.rpm",
    'the existing collector also retains the generated source RPM');

my $skipped = scenario('skip-dep', missing => 1, options => ['--skip-xcat-dep', '--dry-run']);
is($skipped->{rc}, 0, 'skipping dependency builds does not require the source RPM');
is_deeply($skipped->{calls}, [], 'skip-dep executes no source action');
my $replay = scenario('replay', missing => 1, options => ['--skip-build', '--no-verify-repo',
    '--collect-dir', "$tmp/fixture/RPMS/noarch"]);
is($replay->{rc}, 0, 'build-free artifact collection does not require the original source RPM');
is_deeply($replay->{calls}, [], 'build-free collection executes no source action');
my $incomplete = scenario('incomplete', success => 1, packages => "python3-scp=0.14.5\nclosure-gap=1");
isnt($incomplete->{rc}, 0, 'a successful source rebuild does not bypass the manifest gate');
like($incomplete->{log}, qr/MISSING closure-gap\b/, 'the manifest gate identifies the missing required package');

test_genesis_signing();
done_testing();

sub test_genesis_signing {
    for my $home ('explicit', 'default', 'environment', 'relative-explicit', 'relative-environment', 'relative-missing') {
        my $relative = File::Spec->abs2rel($key_home, cwd());
        $relative .= '/not-created' if $home eq 'relative-missing';
        my $environment = $home =~ /environment/ ? ($home eq 'environment' ? $key_home : $relative) : '';
        my $result = scenario("genesis-$home", packages => 'xCAT-genesis-base=2.19.0',
            missing => 1, default_home => ($home eq 'default' || $home =~ /environment/ ? 1 : 0), env_home => $environment,
            key_home => $home =~ /^relative-/ ? $relative : $key_home,
            options => ['--dry-run', '--no-skip-genesis', '--skip-xcat-dep']);
        is($result->{rc}, 0, "$home keyring native Genesis planning completes") or diag($result->{log});
        my ($command) = grep { /^\+ .*buildrpms\.pl/ } split /\n/, $result->{log};
        my $home_path = $home eq 'default' ? "$result->{root}/.gnupg" : $key_home;
        $home_path = File::Spec->rel2abs($relative, cwd()) if $home =~ /^relative-/;
        like($command // '', qr/--gpg-sign --gpg-key-name '\Q$key_name\E' --gpg-home '\Q$home_path\E'/,
            "$home parent signing identity reaches the Genesis child despite its private HOME");
        is_deeply($result->{calls}, [], "$home Genesis planning runs no mock command");
        isnt($result->{root}, cwd(), "$home child source directory differs from the parent signing directory");
        like($result->{log}, qr/\(cwd: \Q$result->{root}\E\)/, "$home child command runs in its source directory");
    }
    my $legacy_genesis = scenario('genesis-legacy', target => 'alma+epel-9-x86_64', packages => 'xCAT-genesis-base=2.19.0',
        missing => 1,
        options => ['--dry-run', '--no-skip-genesis', '--skip-xcat-dep', '--gpg-sign', '--gpg-home', $key_home, '--gpg-key-name', $key_name]);
    is($legacy_genesis->{rc}, 0, 'legacy signed owner still plans Genesis');
    my ($legacy_command) = grep { /^\+ .*buildrpms\.pl/ } split /\n/, $legacy_genesis->{log};
    like($legacy_command // '', qr/--package xCAT-genesis-base/, 'legacy plan contains the production child command');
    unlike($legacy_command // '', qr/--gpg-(?:sign|home|key-name)/, 'legacy Genesis child invocation remains unchanged');
}
