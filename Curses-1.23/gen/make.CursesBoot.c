#!/usr/local/bin/perl
##
##  make.CursesBoot.c  -- make CursesBoot.c
##
##  Copyright (c) 2000  William Setzer
##
##  You may distribute under the terms of either the Artistic License
##  or the GNU General Public License, as specified in the README file.

use lib 'gen';
use Gen;


open OUT, "> CursesBoot.c"  or die "Can't open CursesBoot.c: $!\n";

process_DATA_chunk  \&print_line;
process_functions   \&print_function;
process_DATA_chunk  \&print_line;
process_variables   \&print_variable;
process_DATA_chunk  \&print_line;
process_constants   \&print_constant;
process_DATA_chunk  \&print_line;

close OUT;


###
##  Helpers
#
sub print_line { print OUT @_ }

sub print_function {
    my $fun = shift;

    if (not $fun->{DOIT}) {
	print OUT $fun->{LINE}  if $fun->{LINE} =~ /^#/;    # cpp directives
	return;
    }

    my $S = " " x (22 - length $fun->{NAME});

    print OUT qq{    C_NEWXS("Curses::$fun->{NAME}", } . $S .
	      qq{XS_Curses_$fun->{NAME});\n};
}

sub print_variable {
    my $var = shift;

    return unless $var->{DOIT};

    my $S = " " x (22 - length $var->{NAME});    

    print OUT qq{    C_NEWXS("Curses::$var->{NAME}", } . $S .
	      qq{XS_Curses_$var->{NAME});\n};
}

sub print_constant {
    my $con = shift;

    return unless $con->{DOIT};

    if ($con->{SPEC}{DEFER}) {
      my $S = " " x (22 - length $con->{NAME});

      print OUT qq{    C_NEWXS("Curses::$con->{NAME}", } . $S .
		qq{XS_Curses_$con->{NAME});\n};
    }
    else {
      my $S = " " x (30 - length $con->{NAME});

      print OUT "#ifdef $con->{NAME}\n";
      print OUT qq{    C_NEWCS("$con->{NAME}", } . $S .
		qq{$con->{NAME});\n};
      print OUT "#endif\n";
    }
}


__END__
/*  This file can be automatically generated; changes may be lost.
**
**
**  CursesBoot.c -- the bootstrap function
**
**  Copyright (c) 1994-2000  William Setzer
**
**  You may distribute under the terms of either the Artistic License
**  or the GNU General Public License, as specified in the README file.
*/

#define C_NEWXS(A,B)   newXS(A,B,file)
#define C_NEWCS(A,B)   newCONSTSUB(stash,A,newSViv(B))

XS(boot_Curses)
{
  int i;

    dXSARGS;
    char *file  = __FILE__;
    HV   *stash = gv_stashpv("Curses", TRUE);
    IV   tmp;
    SV  *t2;

    XS_VERSION_BOOTCHECK;

    /* Functions */

PAUSE

    /* Variables masquerading as functions */

PAUSE

    /* Variables masquerading as variables */ 

    C_NEWXS("Curses::Vars::DESTROY",          XS_Curses_Vars_DESTROY);
    C_NEWXS("Curses::Vars::FETCH",            XS_Curses_Vars_FETCH);
    C_NEWXS("Curses::Vars::STORE",            XS_Curses_Vars_STORE);
    C_NEWXS("Curses::Vars::TIESCALAR",        XS_Curses_Vars_TIESCALAR);

    /* Constants */

PAUSE

    /* traceon(); */
    ST(0) = &PL_sv_yes;
    XSRETURN(1);
}
