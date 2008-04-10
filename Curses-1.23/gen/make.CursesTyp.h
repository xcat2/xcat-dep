#!/usr/local/bin/perl
##
##  make.CursesTyp.h  -- make CursesTyp.h
##
##  Copyright (c) 2001  William Setzer
##
##  You may distribute under the terms of either the Artistic License
##  or the GNU General Public License, as specified in the README file.

use lib 'gen';
use Gen;


open OUT, "> CursesTyp.h"  or die "Can't open CursesTyp.h: $!\n";

process_DATA_chunk  \&print_line;
process_typedefs    \&print_typedef;

close OUT;


###
##  Helpers
#
sub print_line { print OUT @_ }

sub print_typedef {
    my $typ = shift;

    return unless $typ->{DOIT};

    print OUT Q<<AAA;
################
#	#ifndef \UC_TYP$typ->{DECL}\E
#	#define $typ->{DECL} int
#	#endif
#
################
AAA
}

__END__
/*  This file can be automatically generated; changes may be lost.
**
**
**  CursesTyp.c -- typedef handlers
**
**  Copyright (c) 1994-2001  William Setzer
**
**  You may distribute under the terms of either the Artistic License
**  or the GNU General Public License, as specified in the README file.
*/

PAUSE
