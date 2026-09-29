#!/usr/bin/perl
# The xCAT ddns plugin signs a DDNS update with a key record that it builds itself:
#   Net::DNS::RR->new("<keyname>. IN KEY 512 3 <algorithm> <secret>")
# Net::DNS 0.80 leaves the DNSSEC records, KEY included, to the separate Net::DNS::SEC
# distribution, so that call dies with "zone file representation not defined for KEY" and
# makedns returns non-zero. The x86_64 and ppc64le repositories take Net::DNS from EPEL and
# never showed the gap; riscv64 has no EPEL and builds this one, so only that architecture
# shipped a Net::DNS without KEY.
#
# The test drives the Net::DNS that the shipped source tarball contains. It does not read the
# module text: it extracts the tarball, puts its lib first on @INC, loads Net::DNS::RR from
# there, and constructs the records xCAT constructs.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/..", "$RealBin/../lib";
use File::Temp qw(tempdir);
use Archive::Tar;
use version;
use MockBuildUtils qw(read_manifest version_matches);
use XCAT::BuildUtils qw(read_lines);

# The records xCAT builds, and the class Net::DNS must return for each. The numbers are the
# algorithm codes of xCAT::DHCP::OmapiPolicy (157 hmac-md5, 163 hmac-sha256, 165 hmac-sha512).
my $SECRET  = 'c2VjcmV0';
my @RECORDS = (
    { rr => "xcat_key. IN KEY 512 3 157 $SECRET", type => 'KEY' },
    { rr => "xcat_key. IN KEY 512 3 163 $SECRET", type => 'KEY' },
    { rr => "xcat_key. IN KEY 512 3 165 $SECRET", type => 'KEY' },
);

my $root = "$RealBin/..";

# The spec is the artifact here: it names the version built and the tarball it is built from.
# read_lines dies when the spec is gone.
my @spec = read_lines("$root/perl-Net-DNS/Net-DNS.spec");
my ($version) = map { /^version:\s*(\S+)/i ? $1 : () } @spec;
my ($source)  = map { /^source:\s*(\S+)/i  ? $1 : () } @spec;
die "the Net::DNS spec declares no version and source; this test covers nothing\n"
    unless $version && $source;

# Net::DNS moved the DNSSEC records, KEY included, into the core distribution at release 1.01.
# Below that release the KEY record lives in the separate Net::DNS::SEC distribution, which
# xcat-dep does not build.
my $KEY_FLOOR = '1.01';

# Net::DNS pads the minor field (0.80, 1.01, 1.47), so the decimal form of version.pm orders
# the releases correctly.
sub at_least_floor { return version->parse($_[0]) >= version->parse($KEY_FLOOR) ? 1 : 0 }

ok(at_least_floor($version),
    "the spec builds Net::DNS $KEY_FLOOR or newer ($version), so KEY is in the core distribution");

# Every target whose manifest section lists perl-Net-DNS builds it from this one spec, so the
# records must work for all of them. A target that takes Net::DNS from EPEL is not listed.
my %manifest = read_manifest("$root/packages-manifest.conf");
my @targets  = grep { exists $manifest{$_}{'perl-Net-DNS'} } sort keys %manifest;
die 'no manifest target builds perl-Net-DNS; this test covers nothing' unless @targets;

# The pin is the second place the version is written down, and mockbuild-all.pl fails the run
# when the built rpm does not match it. A pin below $KEY_FLOOR puts a Net::DNS without KEY back
# into the repositories a service node reads, which have no EPEL copy to outrank it. An operator
# pin (">= 0.80") accepts such a build too, so only an exact version is allowed here.
for my $target (@targets) {
    my $pin = $manifest{$target}{'perl-Net-DNS'};
    my $exact = $pin =~ /\A\d+(?:\.\d+)+\z/ ? 1 : 0;
    ok($exact, "[$target] the perl-Net-DNS pin ($pin) names one exact version");
    ok($exact && at_least_floor($pin),
        "[$target] the perl-Net-DNS pin ($pin) is $KEY_FLOOR or newer");
    ok(version_matches($version, $pin),
        "[$target] the perl-Net-DNS pin ($pin) accepts the version the spec builds ($version)");
}

my $tarball = "$root/perl-Net-DNS/$source";
die "$tarball is missing, so the spec cannot build" unless -f $tarball;

# The tarball, the spec and the Buildnote name one release. A second tarball beside the spec is a
# release that nothing builds, and a Buildnote that names it sends a manual build to the wrong one.
my @tarballs = map { s{.*/}{}r } glob("$root/perl-Net-DNS/Net-DNS-*.tar.gz");
is_deeply(\@tarballs, [$source], "perl-Net-DNS/ holds only the tarball the spec builds ($source)");
my @buildnote = read_lines("$root/perl-Net-DNS/Buildnote");
my @named = map { /(Net-DNS-[\d.]+\.tar\.gz)/ ? $1 : () } @buildnote;
is_deeply(\@named, [$source], "the Buildnote names the tarball the spec builds ($source)");

my $tmp = tempdir(CLEANUP => 1);
{
    my $tar = Archive::Tar->new;
    $tar->read($tarball) or die "Cannot read $tarball: " . Archive::Tar->error;
    $tar->setcwd($tmp);
    $tar->extract or die "Cannot extract $tarball: " . Archive::Tar->error;
}
my ($libdir) = grep { -d } glob("$tmp/*/lib");
die "$tarball holds no lib/ directory" unless defined $libdir;

# The extracted copy goes first on @INC, so it, and not a Net::DNS installed on the build host,
# answers the calls. The test checks which file each module came from.
unshift @INC, $libdir;
require Net::DNS::RR;

my $loaded = $INC{'Net/DNS/RR.pm'} // '(nothing)';
is(index($loaded, $tmp), 0, 'Net::DNS::RR is loaded from the shipped tarball, not from the host')
    or diag("loaded: $loaded");

for my $want (@RECORDS) {
    my $rr = eval { Net::DNS::RR->new($want->{rr}) };
    ok($rr, "Net::DNS builds '$want->{rr}'") or diag($@);
    next unless $rr;
    is($rr->type, $want->{type},                   "... as a $want->{type} record");
    is(ref($rr),  "Net::DNS::RR::$want->{type}",   "... of class Net::DNS::RR::$want->{type}");
    is($rr->key,  $SECRET,                         '... carrying the key material given to it');
}

my $key_module = $INC{'Net/DNS/RR/KEY.pm'} // '(nothing)';
is(index($key_module, $tmp), 0, 'the KEY record class also comes from the shipped tarball')
    or diag("loaded: $key_module");

# CVE-2026-64194: a reply whose owner name is a long chain of compression pointers makes the
# decoder recurse once per pointer. Net::DNS 1.56 stops the chain; 1.47 decodes all of it.
# The reply below holds a NULL record whose rdata is 200 pointers, each to the one before it,
# and an A record whose owner name points at the last one.
{
    my $reply = pack('n6', 1, 0x8100, 1, 2, 0, 0) . "\x01a\x00" . pack('nn', 1, 1);
    my $rdata_at = length($reply) + 12;
    my ($chain, $prev) = ('', 12);
    for (1 .. 200) {
        my $here = $rdata_at + length $chain;
        $chain .= pack 'n', 0xC000 | $prev;
        $prev = $here;
    }
    $reply .= pack('nnnNn', 0xC00C, 10, 1, 0, length $chain) . $chain;
    $reply .= pack('nnnNn', 0xC000 | $prev, 1, 1, 0, 4) . "\x7f\0\0\1";

    require Net::DNS::Packet;
    local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /^Deep recursion/ };
    # Packet->new reports a decode error in $@ and returns, as the resolver expects.
    Net::DNS::Packet->new(\$reply);
    like($@, qr/deep compression recursion/,
        'Net::DNS rejects a reply that chains 200 compression pointers (CVE-2026-64194)');
}

# rt.cpan.org #181125, fixed in Net::DNS 1.57: a reply with a TSIG record in the answer section,
# followed by another record, makes the re-encode of that reply recurse without bound. 1.56 and
# 1.47 recurse. The wrapper stops the recursion at 20 levels and records that it did: Net::DNS
# catches the die inside the TSIG encoder, so the re-encode itself still returns.
{
    my $reply = pack('n6', 1, 0x8100, 1, 2, 0, 0) . "\x07example\x00" . pack('nn', 1, 1);
    my $rdata = "\x0bhmac-sha256\x00" . pack('nNn nnnn', 0, 0, 300, 0, 1, 0, 0);
    $reply .= "\x03key\x00" . pack('nnNn', 250, 255, 0, length $rdata) . $rdata;
    $reply .= "\x00" . pack('nnNn', 1, 1, 0, 4) . "\x7f\0\0\1";

    my $encode = \&Net::DNS::Packet::encode;
    my ($depth, $stopped) = (0, 0);
    no warnings 'redefine';
    local *Net::DNS::Packet::encode = sub {
        if (++$depth > 20) {
            $stopped = 1;
            die "Net::DNS::Packet::encode recursed more than 20 levels deep\n";
        }
        my $wire  = eval { $encode->(@_) };
        my $error = $@;
        $depth--;
        die $error if $error;
        return $wire;
    };
    local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /misplaced or corrupt TSIG/ };
    my $packet = Net::DNS::Packet->new(\$reply);
    ok($packet, 'Net::DNS decodes a reply with a misplaced TSIG record') or diag($@);
    my $data = $packet && eval { $packet->data };
    ok(defined $data, 'Net::DNS re-encodes that reply') or diag($@);
    ok(!$stopped, 'the re-encode does not recurse without bound (rt.cpan.org #181125)');
}

done_testing;
