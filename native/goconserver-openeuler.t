#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($RealBin);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Digest::SHA qw(sha256_hex);
use JSON::PP qw(decode_json);
use Test::More;

plan skip_all => 'Linux user namespaces are required for the unchanged root-only CLI' unless $^O eq 'linux';
my @namespace = $> ? ('unshare', '--user', '--map-root-user', '--') : ();
if (@namespace) {
    my $pid = fork();
    die $! unless defined $pid;
    if (!$pid) {
        open(STDOUT, '>', '/dev/null') or die $!;
        open(STDERR, '>&', \*STDOUT) or die $!;
        exec(@namespace, $^X, '-e', 'exit($> != 0)') or die $!;
    }
    waitpid($pid, 0);
    plan skip_all => 'Unprivileged user namespaces are unavailable' if $?;
}

my $root = "$RealBin/..";
my $builder = $ENV{XCAT_TEST_GO_BUILDER} || "$root/goconserver/mockbuild.pl";
my $tmp = tempdir(CLEANUP => 1);
my $commit = '0123456789abcdef0123456789abcdef01234567';
my $payload = "private compiler download fixture\n";
my $hash = sha256_hex($payload);
my $sequence = 0;

sub write_file {
    my ($path, $text) = @_;
    make_path(dirname($path));
    open(my $fh, '>', $path) or die "$path: $!";
    print {$fh} $text;
    close($fh) or die "$path: $!";
}

sub read_file {
    my ($path) = @_;
    return '' unless -f $path;
    open(my $fh, '<', $path) or die "$path: $!";
    my $text = do { local $/; <$fh> };
    close($fh) or die "$path: $!";
    return $text // '';
}

my $double = <<'DOUBLE';
#!/usr/bin/perl
use strict;
use warnings;
use File::Basename qw(basename dirname);
use File::Path qw(make_path);
use JSON::PP qw(encode_json);
my $command = basename($0);
open(my $log, '>>', $ENV{FIXTURE_LOG}) or die $!;
print {$log} encode_json({command => $command, args => [@ARGV], goarch => $ENV{GOARCH} // ''}), "\n";
close($log) or die $!;
sub put {
    my ($path, $text) = @_;
    make_path(dirname($path));
    open(my $fh, '>', $path) or die $!;
    print {$fh} $text;
    close($fh) or die $!;
}
sub option {
    my ($name) = @_;
    for my $i (0 .. $#ARGV - 1) { return $ARGV[$i + 1] if $ARGV[$i] eq $name; }
    die "Missing option $name";
}
if ($command eq 'uname') {
    die 'Unexpected uname arguments' unless "@ARGV" eq '-m';
    print "$ENV{FIXTURE_ARCH}\n";
} elsif ($command eq 'bash') {
    die 'Unexpected bash invocation' unless @ARGV == 2 && $ARGV[0] eq '-lc';
    if ($ARGV[1] eq 'source /etc/os-release; echo $ID') {
        print "$ENV{FIXTURE_OS}\n";
    } elsif ($ARGV[1] eq 'source /etc/os-release; echo "$VERSION"') {
        print "$ENV{FIXTURE_VERSION}\n";
    } else { die "Unexpected OS query: $ARGV[1]"; }
} elsif ($command eq 'git') {
    if ($ARGV[0] eq 'init') {
        my $path = $ARGV[-1];
        make_path("$path/.git");
        put("$path/goconserver.go", "package main\n");
        put("$path/cmd/congo.go", "package main\n");
        put("$path/storage/etcd.go", "package storage\n");
    } elsif ($ARGV[0] eq '-C' && $ARGV[2] eq 'rev-parse') {
        die 'Commit queried after .git removal' unless -d "$ARGV[1]/.git";
        die 'Unexpected commit query' unless "@ARGV[3 .. $#ARGV]" eq '--verify HEAD^{commit}';
        print "$ENV{FIXTURE_COMMIT}\n";
        exit($ENV{FIXTURE_COMMIT_RC} || 0);
    } elsif ($ARGV[0] eq '-C' && $ARGV[2] eq 'log') {
        print "1600000000\n";
    } elsif ($ARGV[0] eq '-C' && $ARGV[2] =~ /\A(?:remote|fetch|checkout)\z/) {
        exit 0;
    } else { die "Unexpected git arguments: @ARGV"; }
} elsif ($command eq 'wget') {
    put(option('-O'), $ENV{FIXTURE_DOWNLOAD});
} elsif ($command eq 'mock') {
    if (grep { $_ eq '--buildsrpm' } @ARGV) {
        put(option('--resultdir') . '/goconserver-0.3.3-4.src.rpm', "fixture source RPM\n");
    } elsif (grep { $_ eq '--rebuild' } @ARGV) {
        put(option('--resultdir') . "/goconserver-0.3.3-4.$ENV{FIXTURE_TARGET}.rpm", "fixture binary RPM\n");
    } elsif (grep { $_ eq '--print-root-path' || /^--scrub=/ } @ARGV) {
        print "/private/mock/root\n";
    } else { die "Unexpected mock arguments: @ARGV"; }
} elsif ($command eq 'go') {
    die 'Unexpected go invocation' unless $ARGV[0] eq 'build';
    my $output = option('-o');
    put($output, "#!/bin/sh\nexit 0\n");
    chmod 0755, $output;
} elsif ($command eq 'rpmbuild') {
    my ($top) = map { /^_topdir (.+)$/ ? $1 : () } @ARGV;
    die 'Missing rpmbuild topdir' unless defined $top;
    my $arch = option('--target');
    put("$top/RPMS/$arch/goconserver-0.3.3-4.$arch.rpm", "fixture binary RPM\n");
    put("$top/SRPMS/goconserver-0.3.3-4.src.rpm", "fixture source RPM\n");
} elsif ($command eq 'cpio') {
    for my $name (qw(goconserver congo)) {
        put("usr/bin/$name", "#!/bin/sh\nexit 0\n");
        chmod 0755, "usr/bin/$name";
    }
} elsif ($command ne 'rpm' && $command ne 'rpm2cpio') {
    die "Unexpected command $command";
}
DOUBLE

sub run_case {
    my (%options) = @_;
    my $directory = "$tmp/" . ++$sequence;
    my $checkout = "$directory/source";
    my $bin = "$directory/bin";
    make_path($checkout, $bin);
    for my $relative ('MockBuildUtils.pm', 'lib/XCAT/BuildUtils.pm', 'goconserver/gomod/go.mod', 'goconserver/gomod/go.sum') {
        make_path(dirname("$checkout/$relative"));
        copy("$root/$relative", "$checkout/$relative") or die $!;
    }
    copy($builder, "$checkout/goconserver/mockbuild.pl") or die $!;
    write_file("$checkout/goconserver/toolchains/go1.25.12.sha256",
        join('', map { "$hash  go1.25.12.linux-$_.tar.gz\n" } qw(amd64 ppc64le)));
    write_file("$bin/double", $double);
    chmod 0755, "$bin/double";
    symlink('double', "$bin/$_") or die $! for qw(uname bash git wget mock rpm go rpmbuild rpm2cpio cpio);
    my @arguments = ('--work-dir', "$directory/work", '--result-dir', "$directory/results",
        '--log-dir', "$directory/logs", '--mock-uniqueext', 'contract', '--go-ref', 'refs/tags/fixture');
    push @arguments, ('--build-timestamp', $options{epoch} // 1700000000) unless $options{omit_epoch};
    push @arguments, ('--mock-cfg', $options{config}) if defined $options{config};
    push @arguments, ('--target-arch', $options{target}) if defined $options{target};
    local $ENV{PATH} = "$bin:/usr/bin:/bin";
    local $ENV{TZ} = 'Pacific/Honolulu';
    local $ENV{SOURCE_DATE_EPOCH};
    delete $ENV{SOURCE_DATE_EPOCH};
    $ENV{SOURCE_DATE_EPOCH} = $options{environment_epoch} if exists $options{environment_epoch};
    local $ENV{FIXTURE_LOG} = "$directory/commands.jsonl";
    local $ENV{FIXTURE_ARCH} = $options{arch} || 'x86_64';
    local $ENV{FIXTURE_TARGET} = $options{target} || $ENV{FIXTURE_ARCH};
    local $ENV{FIXTURE_OS} = $options{os} || 'openEuler';
    local $ENV{FIXTURE_VERSION} = $options{os_version} || '24.03 (LTS-SP3)';
    local $ENV{FIXTURE_DOWNLOAD} = $options{corrupt} ? "corrupted payload\n" : $payload;
    local $ENV{FIXTURE_COMMIT} = exists($options{commit}) ? $options{commit} : $commit;
    local $ENV{FIXTURE_COMMIT_RC} = $options{commit_rc} || 0;
    my $pid = fork();
    die $! unless defined $pid;
    if (!$pid) {
        open(STDOUT, '>', "$directory/output") or die $!;
        open(STDERR, '>&', \*STDOUT) or die $!;
        exec(@namespace, $^X, "$checkout/goconserver/mockbuild.pl", @arguments) or die $!;
    }
    waitpid($pid, 0);
    my $status = $?;
    my @commands = map { decode_json($_) } grep { length } split /\n/, read_file("$directory/commands.jsonl");
    return { directory => $directory, status => $status, output => read_file("$directory/output"),
        spec => read_file("$directory/work/goconserver.spec"), commands => \@commands };
}

sub calls {
    my ($case, $command, $argument) = @_;
    return [grep { $_->{command} eq $command && (!defined($argument) || grep { $_ eq $argument } @{$_->{args}}) } @{$case->{commands}}];
}

sub build_metadata {
    my ($case, $time, $label) = @_;
    for my $binary (qw(goconserver congo)) {
        like($case->{spec}, qr/^go build [^\n]*-ldflags "-X main.Version=%\{version\} -X main.Commit=\Q$commit\E -X main.BuildTime=\Q$time\E" -o \Q$binary\E /m,
            "$label $binary records fetched commit and UTC build time");
    }
}

my @cells = (
    ['20.03sp4', '20.03 (LTS-SP4)', 'x86_64', 'amd64'],
    ['22.03sp4', '22.03 (LTS-SP4)', 'x86_64', 'amd64'],
    ['24.03sp1', '24.03 (LTS-SP1)', 'x86_64', 'amd64'],
    ['24.03sp3', '24.03 (LTS-SP3)', 'x86_64', 'amd64'],
    ['24.03sp4', '24.03 (LTS-SP4)', 'x86_64', 'amd64'],
    ['24.03', '24.03 (LTS)', 'ppc64le', 'ppc64le'],
);
for my $cell (@cells) {
    my ($version, $os_version, $arch, $goarch) = @$cell;
    my $config = "openeuler-$version-$arch";
    my $case = run_case(os_version => $os_version, arch => $arch);
    is($case->{status}, 0, "$config full CLI succeeds with external build doubles") or diag($case->{output});
    like(read_file("$case->{directory}/work/mock-deterministic.cfg"), qr/^include\('\/etc\/mock\/\Q$config\E\.cfg'\)/m,
        "$config builds inside its exact native config");
    like($case->{spec}, qr/^Release:\s+4$/m, "$config retains the native empty dist macro");
    like($case->{spec}, qr/^BuildArch:\s+\Q$arch\E$/m, "$config retains its native architecture");
    like($case->{spec}, qr/^Source3:\s+https:\/\/go\.dev\/dl\/go1\.25\.12\.linux-\Q$goarch\E\.tar\.gz$/m,
        "$config stages the matching pinned compiler");
    like($case->{spec}, qr/^BuildRequires:\s+coreutils tar gzip ca-certificates$/m, "$config uses the private compiler prerequisites");
    like($case->{spec}, qr/^echo '\Q$hash\E  %\{SOURCE3\}' \| sha256sum -c -$/m, "$config verifies the compiler again in RPM prep");
    is(scalar @{calls($case, 'mock', '--buildsrpm')}, 1, "$config reaches SRPM construction after verification");
    is(scalar @{calls($case, 'mock', '--rebuild')}, 1, "$config reaches native RPM reconstruction");
    is(read_file("$case->{directory}/results/goconserver-0.3.3-4.$arch.rpm"), "fixture binary RPM\n", "$config collects the build output");
    ok(!-d "$case->{directory}/work/goconserver-src/.git", "$config removes fetched Git metadata from the sources");
    build_metadata($case, '2023-11-14T22:13:20Z', $config);
}

{
    my $case = run_case(config => 'openeuler-22.03sp4-x86_64');
    is($case->{status}, 0, 'explicit native target overrides host release detection');
    is(scalar @{calls($case, 'bash')}, 0, 'explicit target requires no host release query');
    like(read_file("$case->{directory}/work/mock-deterministic.cfg"), qr/openeuler-22\.03sp4-x86_64\.cfg/, 'explicit service pack is retained');
}

for my $options (
    { config => 'openeuler-24.03sp3-x86_64', target => 'ppc64le' },
    { config => 'openeuler-24.03-ppc64le', arch => 'x86_64' },
    { config => 'openeuler-24.03-ppc64le', arch => 'ppc64le', target => 'x86_64' },
) {
    my $case = run_case(%$options);
    isnt($case->{status}, 0, 'native target rejects a foreign builder or cross target');
    like($case->{output}, qr/openEuler goconserver requires a native .* builder/, 'native mismatch reports its required builder');
    ok(!-d "$case->{directory}/work", 'native mismatch fails before staging sources');
    is(scalar @{calls($case, 'git')} + scalar @{calls($case, 'mock')} + scalar @{calls($case, 'wget')}, 0,
        'native mismatch starts no source fetch, toolchain fetch, or package build');
}

for my $arch (qw(x86_64 ppc64le)) {
    my $config = $arch eq 'x86_64' ? 'openeuler-24.03sp3-x86_64' : 'openeuler-24.03-ppc64le';
    my $case = run_case(arch => $arch, config => $config, corrupt => 1);
    isnt($case->{status}, 0, "$arch corrupt compiler fails");
    like($case->{output}, qr/Go toolchain checksum mismatch:/, "$arch reports compiler checksum mismatch");
    is(scalar @{calls($case, 'mock', '--buildsrpm')}, 0, "$arch corrupt compiler fails before SRPM construction");
    ok(!-f "$case->{directory}/work/goconserver.spec", "$arch corrupt compiler leaves no generated spec");
}

for my $options ({ commit => '' }, { commit => 'not-a-commit' }, { commit_rc => 1 }) {
    my $case = run_case(%$options);
    isnt($case->{status}, 0, 'unresolved fetched commit fails');
    like($case->{output}, qr/Cannot resolve fetched goconserver commit/, 'unresolved commit has a specific diagnostic');
    is(scalar @{calls($case, 'wget')} + scalar @{calls($case, 'mock')}, 0, 'unresolved commit fails before compiler or package work');
}

for my $row (
    [{ omit_epoch => 1, environment_epoch => 946684800 }, '2000-01-01T00:00:00Z', 'native environment epoch'],
    [{ environment_epoch => 946684800 }, '2023-11-14T22:13:20Z', 'explicit epoch precedence'],
    [{ epoch => 0 }, '1970-01-01T00:00:00Z', 'zero epoch'],
) {
    my ($options, $time, $label) = @$row;
    my $case = run_case(%$options);
    is($case->{status}, 0, "$label succeeds") or diag($case->{output});
    build_metadata($case, $time, $label);
}
for my $options ({ omit_epoch => 1, environment_epoch => 'invalid' }, { epoch => -1 }) {
    my $case = run_case(%$options);
    isnt($case->{status}, 0, 'invalid native epoch fails');
    like($case->{output}, qr/Invalid native build timestamp:/, 'invalid native epoch has a specific diagnostic');
    ok(!-d "$case->{directory}/work", 'invalid native epoch fails before source staging');
}

for my $row (
    [{ config => 'rocky+epel-9-x86_64' }, 'rocky+epel-10-x86_64', '9'],
    [{ os => 'rocky' }, 'rocky+epel-10-x86_64', '10'],
) {
    my ($options, $config, $release) = @$row;
    my $case = run_case(%$options);
    is($case->{status}, 0, "EL$release full CLI succeeds") or diag($case->{output});
    like(read_file("$case->{directory}/work/mock-deterministic.cfg"), qr/\Q$config\E\.cfg/, "EL$release retains the EL10 build peer");
    like($case->{spec}, qr/^Release:\s+4\.el\Q$release\E$/m, "EL$release retains its target dist suffix");
    like($case->{spec}, qr/^BuildRequires:\s+golang$/m, "EL$release retains the distro compiler");
    unlike($case->{spec}, qr/^Source3:/m, "EL$release has no native compiler source");
    is(scalar @{calls($case, 'wget')} + scalar @{calls($case, 'git', 'rev-parse')}, 0, "EL$release adds no native source or metadata fetch");
    for my $binary (qw(goconserver congo)) {
        like($case->{spec}, qr/^go build [^\n]*-ldflags "-X main.Version=%\{version\}" -o \Q$binary\E /m,
            "EL$release $binary preserves its existing linker flags");
    }
}

{
    my $case = run_case(config => 'rocky-10-riscv64-xcat', target => 'riscv64');
    is($case->{status}, 0, 'existing EL cross packaging completes with external build doubles') or diag($case->{output});
    my $go = calls($case, 'go');
    is(scalar @$go, 2, 'EL cross path invokes both host compiler outputs');
    is_deeply([map { $_->{goarch} } @$go], ['riscv64', 'riscv64'], 'EL cross path selects the target GOARCH');
    is(scalar @{calls($case, 'rpmbuild', 'riscv64')}, 1, 'EL cross path packages for the requested target');
    is(scalar @{calls($case, 'mock')} + scalar @{calls($case, 'wget')}, 0, 'EL cross path does not invoke native mock or compiler staging');
    is(read_file("$case->{directory}/results/goconserver-0.3.3-4.riscv64.rpm"), "fixture binary RPM\n", 'EL cross path collects its package output');
}

done_testing();
