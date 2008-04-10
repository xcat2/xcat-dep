#!/usr/local/bin/perl
##
##  make.CursesFun.c  -- make CursesFun.c
##
##  Copyright (c) 2000  William Setzer
##
##  You may distribute under the terms of either the Artistic License
##  or the GNU General Public License, as specified in the README file.


use lib 'gen';
use Gen;
use Data::Dumper;

open OUT, "> CursesCon.c"  or die "Can't open CursesCon.c: $!\n";

process_DATA_chunk  \&print_line;
process_constants   \&print_constant;

close OUT;


###
##  The helpers
#
sub print_line { print OUT @_ }

sub print_constant {
    my $con = shift;

    return unless $con->{DOIT};
    return unless $con->{SPEC}{DEFER};

    print OUT Q<<AAA;
################
#	XS(XS_Curses_$con->{NAME})
#	{
#	    dXSARGS;
#	#ifdef $con->{NAME}
#	    {
#		int	ret = $con->{NAME};
#
#		ST(0) = sv_newmortal();
#		sv_setiv(ST(0), (IV)ret);
#	    }
#	    XSRETURN(1);
#	#else
#	    c_con_not_there("$con->{NAME}");
#	    XSRETURN(0);
#	#endif
#	}
#
################
AAA
}

__END__
/*  This file can be automatically generated; changes may be lost.
**
**
**  CursesCon.c -- non-trivial constants
**
**  Copyright (c) 1994-2000  William Setzer
**
**  You may distribute under the terms of either the Artistic License
**  or the GNU General Public License, as specified in the README file.
*/

PAUSE
