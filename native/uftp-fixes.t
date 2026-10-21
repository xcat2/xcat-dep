#!/usr/bin/env perl
# The uftp sender must reject a STATUS for a section that the file does not have, and an encrypted
# message from a client without encryption state. The receiver must reject a FILESEG for a block
# that the file does not have or a last block of the wrong length, a DONE for a section past the
# end of the file, an ANNOUNCE with a block size that the sender does not accept, a file name that
# leaves its directory, and a name of the destination directory itself. It must keep each block
# that it receives inside its disk cache, send the NAK list of a full section without reading past
# it, move any number of files at the end of a group, and leave a file alone at cleanup when
# another group replaced it or turned a directory of its path into a symbolic link. A restarted
# group must not delete its unused file, and a backup must not delete or replace a file, through a
# symbolic link. Both must refuse a file with more sections than the protocol holds, and the
# sender must seek to every block that the section count allows. The proxy must reject an ANNOUNCE
# with a block size that the sender does not accept, keep each client list that it builds inside
# its packet buffer, and forward the NAKs of a client STATUS, after its header extensions, with
# the whole NAK list of a full section. The test builds the programs from the committed archive
# and patches with AddressSanitizer, and calls the functions that handle those cases directly. The
# built programs must carry the xCAT build mark.
use strict;
use warnings;
use FindBin qw($RealBin);
use File::Basename qw(dirname);
use File::Temp qw(tempdir);
use Test::More;

use lib "$RealBin/../lib";
use XCAT::BuildUtils qw(command_exists read_binary read_lines);

my $root = "$RealBin/..";
my @spec = read_lines("$root/uftp/uftp.spec");
my ($version) = map { /^Version:\s*(\S+)/ ? $1 : () } @spec;
my @patches = map { /^Patch\d*:\s*(\S+)/ ? $1 : () } @spec;
my @missing = grep { !command_exists($_) } qw(cc make patch);
push @missing, 'the OpenSSL headers' unless -e '/usr/include/openssl/evp.h';
plan skip_all => "needs @missing" if @missing;

sub run_or_die {
    my ($cmd, $log) = @_;
    return if system("$cmd >>'$log' 2>&1") == 0;
    die "$cmd failed:\n" . read_binary($log);
}

my $flags = '-g -O1 -fsanitize=address -fno-omit-frame-pointer';
my %tree;

# Builds $program once from the archive and the patches of the spec, then links the harness $name
# in the place of its main.
sub harness {
    my ($program, $name) = @_;
    my ($src, $log) = @{ $tree{$program} //= build($program) };
    my %objects = (
        uftp       => [qw(server_announce server_transfer server_send server_phase server_common server_config server_init)],
        uftpd      => [qw(client_loop client_announce client_fileinfo client_transfer client_common client_config client_init heartbeat_send)],
        uftpproxyd => [qw(proxy_loop proxy_upstream proxy_downstream proxy_common proxy_config proxy_init heartbeat_send)],
    );
    run_or_die("cc $flags -I'$src' -c '$root/native/fixtures/uftp/$name.c' -o '$src/$name.o'", $log);
    my @objects = map { "'$src/$_.o'" } qw(uftp_common encrypt_openssl), @{ $objects{$program} }, 'main_lib', $name;
    run_or_die("cc -fsanitize=address -o '$src/$name' @objects -lcrypto -lm -lpthread", $log);
    return "$src/$name";
}

sub build {
    my ($program) = @_;
    my $dir = tempdir(CLEANUP => 1);
    my $src = "$dir/uftp-$version";
    my $log = "$dir/build.log";
    run_or_die("tar -xzf '$root/uftp/uftp-$version.tar.gz' -C '$dir'", $log);
    run_or_die("patch -s -p1 -d '$src' < '$root/uftp/$_'", $log) for @patches;
    run_or_die("make -C '$src' CFLAGS='$flags' LDFLAGS='-fsanitize=address' $program", $log);
    my %main = (uftp => 'server_main', uftpd => 'client_main', uftpproxyd => 'proxy_main');
    run_or_die("cc $flags -I'$src' -Dmain=uftp_program_main -c '$src/$main{$program}.c' -o '$src/main_lib.o'", $log);
    return [$src, $log];
}

ok(scalar(@patches), 'uftp.spec applies patches');
is_deeply([ grep { /\S/ } map { s/\s+\z//r } read_lines("$root/uftp/debian/patches/series") ], \@patches,
    'the deb applies the patches of the rpm in the same order');

my $bin = harness('uftp', 'status_section');
my %built = (uftp => dirname($bin) . '/uftp');
my $out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the sender survives a STATUS for a section past the end of the file') or diag($out);
like($out, qr/^section 0: 1$/m, 'a STATUS for a section of the file records its NAK');
like($out, qr/^section 1: 0$/m, 'a STATUS for a section past the end of the file records nothing');
unlike($out, qr/AddressSanitizer/, 'the sender stays inside its NAK list');

$bin = harness('uftp', 'encrypted_message');
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the sender survives an encrypted message from a client without encryption state') or diag($out);
like($out, qr/^$_ phase: survived$/m, "the $_ phase rejects that message") for qw(transfer completion);

$bin = harness('uftpd', 'fileseg_block');
$built{uftpd} = dirname($bin) . '/uftpd';
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the receiver survives a FILESEG for a block that the file does not have') or diag($out);
like($out, qr/^section 0 block 1: accepted$/m, 'a FILESEG for a block of the file is accepted');
like($out, qr/^section 0 block 2: rejected$/m, 'a FILESEG for a block past its section is rejected');
like($out, qr/^section 1 block 0: rejected$/m, 'a FILESEG for a section past the end of the file is rejected');

$bin = harness('uftpd', 'cache_boundary');
my %cache_case = (
    'short-tail'  => 'a short last block at the end of the default disk cache',
    'long-repeat' => 'a full-size copy of a short last block that is in the disk cache',
    'short-last'  => 'a last block shorter than the end of the file',
    'lost-blocks' => 'blocks after lost blocks in a small disk cache with large blocks',
);
for my $case (sort keys %cache_case) {
    $out = `ASAN_OPTIONS=detect_leaks=0 '$bin' $case 2>&1`;
    is($?, 0, "the receiver survives $cache_case{$case}") or diag($out);
    like($out, qr/^\Q$case\E: \d+ blocks, 0 missing, file matches$/m, "the file is complete after $cache_case{$case}");
}

$bin = harness('uftpd', 'done_section');
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the receiver survives a DONE for a section past the end of the file') or diag($out);
like($out, qr/^section 0 listed: sections 0-1, 2 NAKs$/m, 'a DONE for a section of the file schedules its NAKs');
like($out, qr/^section 1 $_: sections 0-0, 0 NAKs$/m, "a DONE $_ for this client for a section past the end of the file schedules nothing")
  for qw(listed unlisted);
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' empty 2>&1`;
is($?, 0, 'the receiver survives a DONE for a file without sections') or diag($out);
like($out, qr/^empty unlisted: sections 0-1, 0 NAKs$/m, 'a file without sections has no NAKs');

$bin = harness('uftpd', 'nak_list');
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the receiver survives a STATUS for a full section') or diag($out);
like($out, qr/^full section: 513 bytes, NAKs 4095$/m, 'the STATUS for a section of 4096 blocks of 512 bytes sends 513 bytes of NAKs');
like($out, qr/^short section: 2 bytes, NAKs 9$/m, 'the STATUS for a section of 10 blocks sends 2 bytes of NAKs');
unlike($out, qr/AddressSanitizer/, 'the receiver stays inside its NAK list');

$bin = harness('uftpd', 'announce_blocksize');
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the receiver reads an ANNOUNCE with each block size') or diag($out);
like($out, qr/^block size $_: accepted$/m, "an ANNOUNCE with a block size of $_ is accepted") for 512, 1300, 8800;
like($out, qr/^block size $_: rejected$/m, "an ANNOUNCE with a block size of $_ is rejected") for 0, 511, 8801, 65535;
like($out, qr/^fd 0: open$/m, 'a rejected ANNOUNCE leaves the file of another transfer open');

$bin = harness('uftpd', 'file_names');
for my $mode ('', 'temp') {
    my $where = $mode ? 'a temp directory' : 'the destination directory';
    $out = `ASAN_OPTIONS=detect_leaks=0 '$bin' $mode 2>&1`;
    is($?, 0, "the receiver handles the file names into $where") or diag($out);
    like($out, qr/^$_: present$/m, "the receiver creates $_ in $where") for 'a..b', 'ok/inside';
    like($out, qr/^escape-dotdot: absent$/m, "a name with .. after a component that contains .. stays out of $where");
    like($out, qr/^escape-link: absent$/m, "a name through a symbolic link below $where is rejected");
}
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
like($out, qr/^abs-inside: present$/m, 'an absolute name below the destination directory is accepted');
like($out, qr/^escape-prefix: absent$/m, 'an absolute name that only starts with the destination directory is rejected');

my $limit = 512 * 4096 * 65535;
$bin = harness('uftpd', 'file_size_client');
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the receiver survives a FILEINFO with more sections than the protocol holds') or diag($out);
like($out, qr/^size $limit: accepted, 65535 sections$/m, 'a file of 65535 sections is accepted');
like($out, qr/^size @{[ $limit + 1 ]}: rejected$/m, 'a file of one more section is rejected');
like($out, qr/^fd 0: open$/m, 'an abort after a rejected FILEINFO leaves the file of another transfer open');

$bin = harness('uftp', 'file_size_server');
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the sender survives a file with more sections than the protocol holds') or diag($out);
like($out, qr/^send_file returned ERR_PARAM$/m, 'the sender fails on that file');

$bin = harness('uftp', 'seek_block');
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the sender seeks to blocks past 2^31') or diag($out);
like($out, qr/^block 2147483647: offset 1099511627264$/m, 'the sender seeks to the last block below 2^31');
like($out, qr/^block 2147483648: offset 1099511627776$/m, 'the sender seeks to block 2^31');
like($out, qr/^block 4294901759: offset 2198989700608$/m, 'the sender seeks to the last block that the section count allows');

$bin = harness('uftpd', 'move_list');
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the receiver survives the end of a group with more than 10000 top level entries') or diag($out);
like($out, qr/^moved 10050 of 10050 entries$/m, 'the receiver moves every entry of that group');

$bin = harness('uftpd', 'cleanup_link');
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the receiver survives an abort after another group replaced a directory') or diag($out);
like($out, qr/^outside victim: present$/m, 'an aborted file is not deleted through a symbolic link that another group made');
like($out, qr/^aborted partial: absent$/m, 'an aborted file is still deleted when its path is unchanged');

$bin = harness('uftpd', 'cleanup_replaced');
for my $mode ('', 'complete') {
    my $end = $mode ? 'completes' : 'aborts';
    $out = `ASAN_OPTIONS=detect_leaks=0 '$bin' $mode 2>&1`;
    is($?, 0, "the receiver survives a group that $end after another group replaced its file") or diag($out);
    like($out, qr/^replaced file: second, time kept$/m, "a group that $end leaves alone the file that another group completed in its place");
}
like($out, qr/^completed file: third, time set$/m, 'a completed file still gets its time when no other group replaced it');
like($out, qr/^aborted file: absent$/m, 'an aborted file is still deleted when no other group replaced it');

$bin = harness('uftpd', 'cleanup_restart');
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the receiver survives an abort of a restarted group that replaced a directory') or diag($out);
like($out, qr/^outside victim: present$/m, 'a restarted group does not delete its unused file through a symbolic link that it made');
like($out, qr/^interrupted partial: present$/m, 'an interrupted file stays in the temp directory for a restart');
like($out, qr/^unused partial: absent$/m, 'a restarted group still deletes its unused file when its path is unchanged');

$bin = harness('uftpd', 'backup_link');
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the receiver survives a backup below a symbolic link in its backup directory') or diag($out);
like($out, qr/^outside victim: outside$/m, 'a backup does not delete or replace a file through a symbolic link in the backup directory');
like($out, qr/^received file: second$/m, 'the file whose backup went through that link is still received');
like($out, qr/^backup of plain: first$/m, 'an overwritten file is still backed up when no link is in the way');
like($out, qr/^plain: second$/m, 'the new file replaces the file that was backed up');
like($out, qr/^long backup path: 3\d\d bytes$/m, 'a backup path is longer than 300 bytes');
like($out, qr/^backup of long: second$/m, 'a file is backed up into existing directories along a backup path longer than 300 bytes');
like($out, qr/^long: third$/m, 'the new file with that long a backup path replaces the backed up one');

$bin = harness('uftpd', 'dest_root');
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the receiver survives names of its destination directory') or diag($out);
like($out, qr/^\Q$_\E: rejected, keep present, other present$/m, "a request for the name $_ is rejected and the destination keeps its files")
  for 'delete .', 'delete ./', 'delete ./.', 'delete dest/', 'delete dest/.', 'file .', 'file dest/./';
like($out, qr/^delete other: accepted, keep present, other absent$/m, 'a delete request for a file of the destination deletes only that file');
like($out, qr/^free space \.: accepted, keep present, other present$/m, 'a free space request for . is still accepted');

for my $program (sort keys %built) {
    like(read_binary($built{$program}), qr/UFTP version \Q$version\E \(xCAT build \d+\)/,
        "the built $program carries the xCAT build mark");
}

$bin = harness('uftpproxyd', 'proxy_announce');
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the proxy reads an ANNOUNCE with each block size') or diag($out);
like($out, qr/^block size $_: accepted$/m, "the proxy accepts an ANNOUNCE with a block size of $_") for 512, 1300, 8800;
like($out, qr/^block size $_: rejected$/m, "the proxy rejects an ANNOUNCE with a block size of $_") for 0, 511, 8801, 65535;

$bin = harness('uftpproxyd', 'proxy_lists');
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the proxy computes its list sizes') or diag($out);
like($out, qr/^$_: \d+ entries, fits$/m, "a $_ list of the proxy fits in its packet buffer") for qw(KEYINFO REGISTER FILEINFO_ACK COMPLETE);

$bin = harness('uftpproxyd', 'proxy_status');
$out = `ASAN_OPTIONS=detect_leaks=0 '$bin' 2>&1`;
is($?, 0, 'the proxy forwards the STATUS of a client') or diag($out);
like($out, qr/^full section: 513 bytes, NAKs 4095$/m, 'the proxy sends the 513 bytes of NAKs that the server requires for a section of 4096 blocks of 512 bytes');
like($out, qr/^tfmcc full section: 513 bytes, NAKs 4095$/m, 'the proxy reads the NAKs of a client STATUS after its TFMCC extension');
like($out, qr/^short section: 513 bytes, NAKs 9$/m, 'the proxy reads only the NAKs that a client STATUS holds');

done_testing();
