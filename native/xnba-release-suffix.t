use strict;
use warnings;

use Cwd qw(abs_path);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Glob qw(bsd_glob);
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use JSON::PP qw(encode_json);
use Test::More;
use Text::ParseWords qw(shellwords);

use lib "$RealBin/../lib", "$RealBin/../t/lib";
use XCAT::BuildUtils qw(capture_command command_exists digest_file read_binary write_binary);
use XCAT::GenesisReleaseTest qw(run_capture);

plan skip_all => 'Linux RPM packaging tools and namespaces are required'
    unless $^O eq 'linux' && !grep { !command_exists($_) } qw(rpm rpmbuild rpm2cpio cpio tar unshare);
my $tmp = tempdir(CLEANUP => !$ENV{XCAT_TEST_KEEP});
diag("xNBA release fixtures: $tmp");
my @namespace = $> == 0 ? () : ('unshare', '--user', '--map-root-user');
plan skip_all => 'User namespace is unavailable for the packaging owner root check'
    if @namespace && run_capture("$tmp/namespace.log", @namespace, 'true') != 0;
my $repo = abs_path("$RealBin/..");
my $owner = $ENV{XCAT_TEST_XNBA} // "$repo/xnba/mockbuild.pl";
my $collector = $ENV{XCAT_TEST_COLLECTOR} // "$repo/mockbuild-all.pl";
my $epoch = 1788718796;
my $suffix = '.snap202609061819.21';
my $default_release = capture_command('rpm', '--eval', '1%{?dist}');
my $source = "$tmp/source tree";
make_path("$source/xnba/binary");
copy($owner, "$source/xnba/mockbuild.pl") or die $!;
copy("$repo/MockBuildUtils.pm", "$source/MockBuildUtils.pm") or die $!;
copy("$repo/xnba/xnba-undi.spec", "$source/xnba/xnba-undi.spec") or die $!;
copy("$repo/xnba/binary/$_", "$source/xnba/binary/$_") or die $! for qw(xnba.kpxe xnba.efi);
my %specs;
for my $case (['default', []], ['suffix', ['--release-suffix', $suffix]]) {
    my ($name, $options) = @$case;
    my $work = "$tmp/$name-work";
    my $result = "$tmp/$name-result";
    my $rc = run_capture("$tmp/$name.log", @namespace, $^X, "$source/xnba/mockbuild.pl",
        '--mock-cfg', 'openeuler-24.03-ppc64le', '--work-dir', $work,
        '--result-dir', $result, '--log-dir', "$tmp/$name logs", '--build-timestamp', $epoch, @$options);
    is($rc, 0, "$name actual xNBA packaging owner succeeds") or diag(read_binary("$tmp/$name.log"));
    next if $rc;
    $specs{$name} = read_binary("$work/rpmbuild/SPECS/xnba-undi.spec");
    my @rpms = bsd_glob("$result/*.rpm");
    is(scalar @rpms, 2, "$name produces exactly a binary RPM and SRPM");
    my ($binary) = grep { /\.noarch\.rpm\z/ } @rpms;
    my ($srpm) = grep { /\.src\.rpm\z/ } @rpms;
    ok($binary && $srpm, "$name output includes both RPM kinds");
    next unless $binary && $srpm;
    my $release = $default_release . ($name eq 'suffix' ? $suffix : '');
    is(capture_command('rpm', '-qp', '--qf', '%{RELEASE}', $_), $release,
        "$name records the expected Release in $_") for ($binary, $srpm);
    is(capture_command('rpm', '-qp', '--qf', '%{SOURCEPACKAGE}', $srpm), '1', "$name source output is an SRPM");
    my $unpack = "$tmp/$name payload";
    make_path($unpack);
    is(run_capture("$tmp/$name.cpio", 'rpm2cpio', $binary), 0, "$name native RPM payload decodes");
    is(run_capture("$tmp/$name-extract.log", 'bash', '-c',
        'cd "$1" && cpio --quiet -idm --no-absolute-filenames < "$2"', 'extract', $unpack, "$tmp/$name.cpio"),
        0, "$name native cpio payload extracts");
    for my $file (qw(xnba.kpxe xnba.efi)) {
        is(digest_file("$unpack/tftpboot/xcat/$file"), digest_file("$repo/xnba/binary/$file"),
            "$name preserves committed $file bytes");
    }
    is(capture_command('rpm', '-qpl', $binary), "/tftpboot/xcat/xnba.efi\n/tftpboot/xcat/xnba.kpxe",
        "$name ships only the two boot payloads");
}
if (exists $specs{default} && exists $specs{suffix}) {
    (my $without_suffix = $specs{suffix}) =~ s/\Q$suffix\E//;
    is($without_suffix, $specs{default}, 'the suffix changes only the generated Release token');
}

my $arch = capture_command('uname', '-m');
my @targets = ("alma+epel-9-$arch");
push @targets, 'openeuler-24.03-ppc64le' if $arch eq 'ppc64le';
push @targets, 'openeuler-24.03sp3-x86_64' if $arch eq 'x86_64';
for my $target (@targets) {
    for my $number (undef, 21) {
        my $label = defined($number) ? 'suffix' : 'default';
        my $root = "$tmp/plan $target $label";
        make_path(map { "$root/$_" } qw(xnba goconserver grub2-xcat openeuler));
        write_binary("$root/packages-manifest.conf", "[$target]\nxnba-undi=1.*\ngoconserver=0.*\ngrub2-xcat=2.*\n");
        for my $dir (qw(xnba goconserver grub2-xcat)) {
            write_binary("$root/$dir/mockbuild.pl", "die qq{dry-run executed a builder\\n};\n");
        }
        if ($target eq 'openeuler-24.03-ppc64le') {
            my $key = 'openeuler/publisher.key';
            write_binary("$root/$key", 'dry-run key fixture');
            write_binary("$root/openeuler/24.03-ppc64le.inputs.json", encode_json({
                version => 1, target => $target,
                publisher_key => {path => $key, sha256 => digest_file("$root/$key"), fingerprint => ('A' x 40)},
                inputs => [map { {name => $_, type => 'owner', outputs => [$_],
                    build_uid => ($_ eq 'xnba-undi' ? 0 : 1000)} } qw(xnba-undi goconserver grub2-xcat)],
            }));
        }
        local $ENV{MOCKBUILD_ALL_MOUNTNS} = 1;
        my $log = "$tmp/plan-$target-$label.log";
        my $rc = run_capture($log, @namespace, $^X, $collector, '--repo-root', $root,
            '--xcat-source', $root, '--target', $target, '--output', "$root/output",
            '--build-timestamp', $epoch, '--run-id', 'release-contract', '--skip-genesis', '--gpg-sign',
            '--max-parallel', 1, '--parallel-builds', 1, '--dry-run',
            (defined($number) ? ('--build-number', $number) : ()));
        is($rc, 0, "$target $label whole collector dry-run succeeds") or diag(read_binary($log));
        my $text = read_binary($log);
        for my $dir (qw(xnba goconserver grub2-xcat)) {
            my ($command) = $text =~ /^\+ ([^\n]*\Q$root\/$dir\/mockbuild.pl\E[^\n]*)$/m;
            ok(defined($command), "$target $label plans the $dir owner");
            next unless defined $command;
            my @argv = shellwords($command);
            for (1 .. 3) {
                last if $argv[0] eq 'perl';
                @argv = shellwords($argv[-1]);
            }
            is($argv[0], 'perl', 'the planned command reaches the Perl owner');
            my %options;
            for my $i (0 .. $#argv - 1) { $options{$argv[$i]} = $argv[$i + 1]; }
            if (defined($number) && $dir ne 'grub2-xcat') {
                is($options{'--release-suffix'}, $suffix, "$dir receives the exact CD suffix");
            } else {
                ok(!exists($options{'--release-suffix'}), "$dir retains its existing suffix option behavior");
            }
            if ($dir eq 'goconserver') {
                like($options{'--go-ref'}, qr/\A[0-9a-f]{40}\z/, 'goconserver retains its immutable source pin');
            } else {
                ok(!exists($options{'--go-ref'}), "$dir receives no Go-specific option");
            }
        }
        ok(!-d "$root/output/mockbuild-all/$target-release-contract/build-results", 'the dry-run executes no package build');
    }
}
done_testing();
