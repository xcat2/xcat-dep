#!/usr/local/bin/perl
##
##  make.CursesVar.c  -- make CursesVar.c
##
##  Copyright (c) 2000  William Setzer
##
##  You may distribute under the terms of either the Artistic License
##  or the GNU General Public License, as specified in the README file.

use lib 'gen';
use Gen;

open OUT, "> CursesVar.c"   or die "Can't open CursesVar.c: $!\n";

process_DATA_chunk  \&print_line;
process_variables   \&print_function;
process_DATA_chunk  \&print_line;
process_variables   \&print_fetch;
process_DATA_chunk  \&print_line;
process_variables   \&print_store;
process_DATA_chunk  \&print_line;

close OUT;


###
##  Helpers
#
sub print_line { print OUT @_ }

sub print_function {
    my $var = shift;

    return unless $var->{DOIT};

    my $A    = "ST(0)";
    my $N    = $var->{NAME};
    my $body = eval qq("$var->{M_RETN}");

    print OUT Q<<AAA;
################
#	XS(XS_Curses_$var->{NAME})
#	{
#	    dXSARGS;
#	#ifdef \UC_$var->{NAME}\E
#	    c_exactargs("$var->{NAME}", items, 0);
#	    {
#		ST(0) = sv_newmortal();
#		$body;
#	    }
#	    XSRETURN(1);
#	#else
#	    c_var_not_there("$var->{NAME}");
#	    XSRETURN(0);
#	#endif
#	}
#
################
AAA
}

sub print_fetch {
    my $var = shift;

    return unless $var->{DOIT};

    my $A    = "ST(0)";
    my $N    = $var->{NAME};
    my $body = eval qq("$var->{M_RETN}");

    print OUT Q<<AAA;
################
#		case $var->{NUM}:
#	#ifdef \UC_$var->{NAME}\E
#		    $body;
#	#else
#		    c_var_not_there("$var->{NAME}");
#	#endif
#		    break;
################
AAA
}

sub print_store {
    my $var = shift;

    return unless $var->{DOIT};

    my $A    = "ST(1)";
    my $B    = -1;
    my $N    = $var->{NAME};
    my $body = eval qq("$var->{M_DECL}");

    print OUT Q<<AAA;
################
#		case $var->{NUM}:
#	#ifdef \UC_$var->{NAME}\E
#		    $var->{NAME} = $body;
#	#else
#		    c_var_not_there("$var->{NAME}");
#	#endif
#		    break;
################
AAA

}

###  
##  Templates
#
__END__
/*  This file can be automatically generated; changes may be lost.
**
**
**  CursesVar.c -- the variables
**
**  Copyright (c) 1994-2000  William Setzer
**
**  You may distribute under the terms of either the Artistic License
**  or the GNU General Public License, as specified in the README file.
*/

PAUSE

XS(XS_Curses_Vars_TIESCALAR)
{
    dXSARGS;
    c_exactargs("TIESCALAR", items, 2);
    {
	char *	pack = (char *)SvPV(ST(0),PL_na);
	int	n    = (int)SvIV(ST(1));

	ST(0) = sv_newmortal();
	sv_setref_iv(ST(0), pack, n);
    }
    XSRETURN(1);
}

XS(XS_Curses_Vars_FETCH)
{
    dXSARGS;
    {
	int	num = (int)SvIV(SvRV((SV*)ST(0)));

	ST(0) = sv_newmortal();
	switch (num) {
PAUSE
	default:
	    croak("Curses::Vars::FETCH called with bad index");
	    /* NOTREACHED */
	}
    }
    XSRETURN(1);
}

XS(XS_Curses_Vars_STORE)
{
    dXSARGS;
    {
	int	num = (int)SvIV((SV*)SvRV(ST(0)));

	switch (num) {
PAUSE
	default:
	    croak("Curses::Vars::STORE called with bad index");
	    /* NOTREACHED */
	}
	ST(0) = &PL_sv_yes;
    }
    XSRETURN(1);
}

XS(XS_Curses_Vars_DESTROY)
{
    dXSARGS;
    {
	SV *	rv = ST(0);

	ST(0) = &PL_sv_yes;
    }
    XSRETURN(1);
}
