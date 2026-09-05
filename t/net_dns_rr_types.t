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
# module text: it extracts the tarball, puts its lib on the child @INC, and constructs the
# records xCAT constructs.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/..";
use File::Temp qw(tempdir);
use Archive::Tar;
use MockBuildUtils qw(read_manifest version_matches);

# The records xCAT builds, and the class Net::DNS must return for each. The numbers are the
# algorithm codes of xCAT::DHCP::OmapiPolicy (157 hmac-md5, 163 hmac-sha256, 165 hmac-sha512).
my $SECRET  = 'c2VjcmV0';
my @RECORDS = (
    { rr => "xcat_key. IN KEY 512 3 157 $SECRET", type => 'KEY' },
    { rr => "xcat_key. IN KEY 512 3 163 $SECRET", type => 'KEY' },
    { rr => "xcat_key. IN KEY 512 3 165 $SECRET", type => 'KEY' },
);

my $root = "$RealBin/..";
my $spec = "$root/perl-Net-DNS/Net-DNS.spec";
BAIL_OUT("$spec is gone; this test covers nothing") unless -f $spec;

# The spec is the artifact here: it names the version built and the tarball it is built from.
my ($version, $source);
{
    open my $fh, '<', $spec or BAIL_OUT("Cannot read $spec: $!");
    while (my $line = <$fh>) {
        $version = $1 if !defined($version) && $line =~ /^version:\s*(\S+)/i;
        $source  = $1 if !defined($source)  && $line =~ /^source:\s*(\S+)/i;
    }
    close $fh;
}
BAIL_OUT("$spec declares no version") unless defined $version;
BAIL_OUT("$spec declares no source") unless defined $source;

# Net::DNS moved the DNSSEC records, KEY included, into the core distribution at release 1.01.
# Below that release the KEY record lives in the separate Net::DNS::SEC distribution, which
# xcat-dep does not build.
my $KEY_FLOOR = '1.01';

# Compare two dotted versions field by field, numerically. Net::DNS pads the minor field
# (0.80, 1.01, 1.47), so a numeric field compare orders the releases correctly.
sub version_ge {
    my ($got, $want) = @_;
    my @g = split /\./, $got;
    my @w = split /\./, $want;
    while (@g || @w) {
        my $a = @g ? shift(@g) : 0;
        my $b = @w ? shift(@w) : 0;
        return $a > $b ? 1 : 0 if $a != $b;
    }
    return 1;
}

ok(version_ge($version, $KEY_FLOOR),
    "the spec builds Net::DNS $KEY_FLOOR or newer ($version), so KEY is in the core distribution");

# Every target whose manifest section lists perl-Net-DNS builds it from this one spec, so the
# records must work for all of them. A target that takes Net::DNS from EPEL is not listed.
my %manifest = read_manifest("$root/packages-manifest.conf");
my @targets  = grep { exists $manifest{$_}{'perl-Net-DNS'} } sort keys %manifest;
BAIL_OUT('no manifest target builds perl-Net-DNS; this test covers nothing') unless @targets;

# The pin is the second place the version is written down, and mockbuild-all.pl fails the run
# when the built rpm does not match it. A pin below $KEY_FLOOR puts a Net::DNS without KEY back
# into the repositories a service node reads, which have no EPEL copy to outrank it. An operator
# pin (">= 0.80") accepts such a build too, so only an exact version is allowed here.
for my $target (@targets) {
    my $pin = $manifest{$target}{'perl-Net-DNS'};
    my $exact = $pin =~ /\A\d+(?:\.\d+)+\z/ ? 1 : 0;
    ok($exact, "[$target] the perl-Net-DNS pin ($pin) names one exact version");
    ok($exact && version_ge($pin, $KEY_FLOOR),
        "[$target] the perl-Net-DNS pin ($pin) is $KEY_FLOOR or newer");
    ok(version_matches($version, $pin),
        "[$target] the perl-Net-DNS pin ($pin) accepts the version the spec builds ($version)");
}

my $tarball = "$root/perl-Net-DNS/$source";
BAIL_OUT("$tarball is missing, so the spec cannot build") unless -f $tarball;

my $tmp = tempdir(CLEANUP => 1);
{
    my $tar = Archive::Tar->new;
    $tar->read($tarball) or BAIL_OUT("Cannot read $tarball: " . Archive::Tar->error);
    $tar->setcwd($tmp);
    $tar->extract or BAIL_OUT("Cannot extract $tarball: " . Archive::Tar->error);
}
my ($libdir) = grep { -d } glob("$tmp/*/lib");
BAIL_OUT("$tarball holds no lib/ directory") unless defined $libdir;

# The probe runs in its own perl so the extracted copy, and not a Net::DNS installed on the
# build host, answers the calls. It reports the file it loaded, which the test checks.
my $probe = "$tmp/probe.pl";
{
    open my $fh, '>', $probe or BAIL_OUT("Cannot write $probe: $!");
    print {$fh} <<'PROBE' or BAIL_OUT("Cannot write $probe: $!");
use strict;
use warnings;
use Net::DNS::RR;
print "LOADED\t$INC{'Net/DNS/RR.pm'}\n";
for my $record (@ARGV) {
    my $rr = eval { Net::DNS::RR->new($record) };
    if ($@) {
        my $err = $@;
        $err =~ s/\s+/ /g;
        print "DIED\t$record\t$err\n";
        next;
    }
    my $key = $rr->can('key') ? $rr->key : '';
    print "BUILT\t$record\t", $rr->type, "\t", ref($rr), "\t$key\n";
}
PROBE
    close $fh;
}

my @out;
{
    local $ENV{PERL5LIB} = '';
    open my $ph, '-|', $^X, "-I$libdir", $probe, map { $_->{rr} } @RECORDS
        or BAIL_OUT("Cannot run the probe: $!");
    @out = <$ph>;
    close $ph;
}
chomp @out;

my ($loaded) = map { (split /\t/, $_, 2)[1] } grep { /^LOADED\t/ } @out;
ok(defined($loaded) && index($loaded, $tmp) == 0,
    'the probe loaded the Net::DNS from the shipped tarball, not one installed on the host')
    or diag("loaded: " . (defined($loaded) ? $loaded : '(nothing)') . "\nprobe output:\n" . join("\n", @out));

my %built = map {
    my (undef, $record, $type, $class, $key) = split /\t/, $_;
    ($record => { type => $type, class => $class, key => $key });
} grep { /^BUILT\t/ } @out;

for my $want (@RECORDS) {
    my $got = $built{ $want->{rr} };
    my @died = grep { /^DIED\t\Q$want->{rr}\E\t/ } @out;
    ok($got, "Net::DNS builds '$want->{rr}'")
        or diag(@died ? "@died" : "no result for that record");
    next unless $got;
    is($got->{type},  $want->{type},                   "... as a $want->{type} record");
    is($got->{class}, "Net::DNS::RR::$want->{type}",   "... of class Net::DNS::RR::$want->{type}");
    is($got->{key},   $SECRET,                         '... carrying the key material given to it');
}

done_testing;
