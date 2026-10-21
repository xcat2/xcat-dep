#!/usr/bin/env perl
# mockbuild-all.pl --dry-run must plan the uftp builder for an openEuler target whose manifest
# section lists uftp, with the mock config of that target, and must not plan it otherwise.
use strict;
use warnings;

use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use JSON::PP qw(encode_json);
use Test::More;
use Text::ParseWords qw(shellwords);

use lib "$RealBin/../lib", "$RealBin/../t/lib";
use XCAT::BuildUtils qw(capture_command command_exists digest_file read_binary write_binary);
use XCAT::GenesisReleaseTest qw(run_capture);

plan skip_all => 'Linux RPM tools and user namespaces are required'
    unless $^O eq 'linux' && !grep { !command_exists($_) } qw(rpm unshare);
my $tmp = tempdir(CLEANUP => !$ENV{XCAT_TEST_KEEP});
my @namespace = $> == 0 ? () : ('unshare', '--user', '--map-root-user');
plan skip_all => 'User namespace is unavailable for the root check of mockbuild-all.pl'
    if @namespace && run_capture("$tmp/namespace.log", @namespace, 'true') != 0;
my $collector = $ENV{XCAT_TEST_COLLECTOR} // abs_path("$RealBin/../mockbuild-all.pl");
my $arch = capture_command('uname', '-m');

# Runs the dry-run on a tree whose builders die when executed, and returns the planned uftp
# builder command line, or undef when the plan has none.
sub planned_uftp {
    my ($target, $with_uftp) = @_;
    my $root = "$tmp/$target " . ($with_uftp ? 'with' : 'without') . ' uftp';
    make_path(map { "$root/$_" } qw(uftp goconserver openeuler));
    write_binary("$root/packages-manifest.conf",
        "[$target]\ngoconserver=0.*\n" . ($with_uftp ? "uftp=5.0.4\n" : ''));
    write_binary("$root/$_/mockbuild.pl", "die qq{dry-run executed a builder\\n};\n") for qw(uftp goconserver);
    if ($target eq 'openeuler-24.03-ppc64le') {
        my $key = 'openeuler/publisher.key';
        write_binary("$root/$key", 'dry-run key fixture');
        write_binary("$root/openeuler/24.03-ppc64le.inputs.json", encode_json({
            version => 1, target => $target,
            publisher_key => {path => $key, sha256 => digest_file("$root/$key"), fingerprint => ('A' x 40)},
            inputs => [map { {name => $_, type => 'owner', outputs => [$_], build_uid => 1000} }
                qw(goconserver uftp)],
        }));
    }
    local $ENV{MOCKBUILD_ALL_MOUNTNS} = 1;
    my $log = "$root.log";
    my $rc = run_capture($log, @namespace, $^X, $collector, '--repo-root', $root,
        '--xcat-source', $root, '--target', $target, '--output', "$root/output",
        '--build-timestamp', 1788718796, '--run-id', 'uftp-plan', '--skip-genesis', '--gpg-sign',
        '--max-parallel', 1, '--parallel-builds', 1, '--dry-run');
    is($rc, 0, "$target dry-run succeeds " . ($with_uftp ? 'with' : 'without') . ' uftp')
        or diag(read_binary($log));
    my ($command) = read_binary($log) =~ /^\+ ([^\n]*\Q$root\/uftp\/mockbuild.pl\E[^\n]*)$/m;
    return unless defined $command;
    # A native owner wraps the builder in its own shell commands.
    my @argv = shellwords($command);
    for (1 .. 3) {
        last if $argv[0] eq 'perl';
        @argv = shellwords($argv[-1]);
    }
    return \@argv;
}

my @targets = ("alma+epel-9-$arch");
push @targets, 'openeuler-24.03sp3-x86_64', 'openeuler-20.03sp4-x86_64' if $arch eq 'x86_64';
push @targets, 'openeuler-24.03-ppc64le' if $arch eq 'ppc64le';
for my $target (@targets) {
    my $argv = planned_uftp($target, 1);
    ok($argv, "$target plans the uftp builder");
    if ($argv) {
        is($argv->[0], 'perl', "$target runs the uftp builder with perl");
        my %options;
        for my $i (0 .. $#$argv - 1) { $options{$argv->[$i]} = $argv->[$i + 1]; }
        is($options{'--mock-cfg'}, $target, "$target builds uftp in its own mock config");
        ok(!exists $options{'--target-arch'}, "$target builds uftp natively");
    }
    ok(!planned_uftp($target, 0), "$target does not plan uftp when its manifest section lacks it");
}
done_testing();
