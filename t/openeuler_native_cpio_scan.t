#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use XCAT::NativeInputs qw(scan_cpio_for_elf);

sub member {
    my ($name, $data) = @_;
    my $n = length($name) + 1;
    my $rec = '070701'
            . join('', map { sprintf '%08X', $_ }
                   (1, 0100644, 0, 0, 1, 0, length($data), 0, 0, 0, 0, $n, 0))
            . "$name\0";
    $rec .= "\0" x ((4 - (110 + $n) % 4) % 4);
    $rec .= $data;
    $rec .= "\0" x ((4 - length($data) % 4) % 4);
    return $rec;
}
sub trailer {
    my $n = length('TRAILER!!!') + 1;
    my $rec = '070701' . join('', map { sprintf '%08X', $_ } (0) x 13);
    substr($rec, 6 + 11 * 8, 8) = sprintf '%08X', $n;
    $rec .= "TRAILER!!!\0";
    $rec .= "\0" x ((4 - (110 + $n) % 4) % 4);
    return $rec;
}
sub scan {
    my ($bytes) = @_;
    open my $fh, '<', \$bytes or die "in-memory open: $!";
    binmode $fh;
    my $r = eval { scan_cpio_for_elf($fh) };
    return $@ unless defined $r;
    return $r ? 'OK' : "FALSY VERDICT: '$r'";
}

is(scan(member('./usr/share/perl5/CGI.pm', "package CGI;\n1;\n") . trailer()), 'OK',
   'a noarch payload of plain files is accepted');

like(scan(member('./usr/bin/thing', "\x7fELF\x02\x01\x01\x00") . trailer()),
     qr/ELF payload in publisher noarch RPM: \.\/usr\/bin\/thing/,
     'an ELF member is refused, and the message names the file');

like(scan(substr(member('./usr/share/doc/README', 'x' x 4096) . trailer(), 0, 200)),
     qr/Truncated RPM payload/, 'a stream that ends before its trailer is refused');

like(scan(member('./a', 'x') . trailer() . 'trailing junk'),
     qr/Unexpected data after RPM cpio trailer/, 'data after the trailer is refused');

like(scan('N' x 200), qr/Invalid RPM cpio header/, 'a stream that is not cpio is refused');

done_testing();
