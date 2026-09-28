#!/usr/bin/env perl
# The Genesis image carries the kernel of the release that built it, so xcat-core builds one deb
# per Ubuntu codename and stamps the codename into the version. Staging all of them into every
# suite publishes three images per suite and lets apt pick the newest, which is the image of
# another release.
#
# sbuild-all.pl also kept an rpm->deb fallback, the EL image converted with rpm2cpio, which gave
# an Ubuntu node an image built from an EL kernel. It is removed.
use strict;
use warnings;

use File::Basename qw(basename);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib $FindBin::Bin . '/..';
use Test::More;

require BuildUtils;

my $root = File::Spec->rel2abs("$FindBin::Bin/..");

ok(BuildUtils->can('genesis_debs_for_codename'),
    'BuildUtils selects the Genesis deb of one codename');

unless (BuildUtils->can('genesis_debs_for_codename')) {
    diag('sbuild-all.pl stages every Genesis deb into every suite');
    done_testing();
    exit;
}

my @built = map { "/staging/$_" } qw(
    xcat-genesis-base-amd64_2.19.0-snap202609121200~jammy_all.deb
    xcat-genesis-base-amd64_2.19.0-snap202609121200~noble_all.deb
    xcat-genesis-base-amd64_2.19.0-snap202609121200~resolute_all.deb
);

is_deeply([ BuildUtils::genesis_debs_for_codename(\@built, 'noble') ],
    [ '/staging/xcat-genesis-base-amd64_2.19.0-snap202609121200~noble_all.deb' ],
    'noble takes the image built on noble');
is_deeply([ BuildUtils::genesis_debs_for_codename(\@built, 'jammy') ],
    [ '/staging/xcat-genesis-base-amd64_2.19.0-snap202609121200~jammy_all.deb' ],
    'jammy takes the image built on jammy');
is_deeply([ BuildUtils::genesis_debs_for_codename(\@built, 'focal') ], [],
    'a release with no image of its own takes none');

my @unmarked = ('/staging/xcat-genesis-base-amd64_2.19.0-snap202609121200_all.deb');
is_deeply([ BuildUtils::genesis_debs_for_codename(\@unmarked, 'noble') ], \@unmarked,
    'a deb built for no particular release serves every release');
is_deeply([ BuildUtils::genesis_debs_for_codename(\@built, undef) ], \@built,
    'with no codename every deb is taken');
is_deeply([ BuildUtils::genesis_debs_for_codename([], 'noble') ], [],
    'no deb is no deb');

# cross_copy_genesis_deb stages into one suite, so it must take the codename too.
my $tmp = tempdir(CLEANUP => 1);
my ($from, $to) = ("$tmp/from", "$tmp/to");
make_path($from, $to);
for my $deb (@built) {
    open my $fh, '>', "$from/" . basename($deb) or die $!;
    print {$fh} basename($deb);
    close $fh;
}
BuildUtils::cross_copy_genesis_deb($from, $to, 'amd64', undef, 'noble');
my @staged = map { basename($_) } glob("$to/*.deb");
is_deeply(\@staged, [ 'xcat-genesis-base-amd64_2.19.0-snap202609121200~noble_all.deb' ],
    'only the codename its own image is staged into a suite');

# The rpm fallback is gone: the option it hangs on is not accepted any more.
for my $option (qw(--genesis-rpm --genesis-rpm-ppc --require-ppc-genesis)) {
    my $out = qx{cd '$root' && perl ./sbuild-all.pl $option x --dry-run 2>&1};
    isnt($? >> 8, 0, "sbuild-all.pl rejects $option");
    like($out, qr/Unknown option/i, "$option is not an option any more");
}

done_testing();
