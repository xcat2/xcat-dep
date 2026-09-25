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

done_testing;
