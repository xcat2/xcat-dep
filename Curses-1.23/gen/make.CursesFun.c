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

open OUT, "> CursesFun.c"  or die "Can't open CursesFun.c: $!\n";

process_DATA_chunk  \&print_line;
process_functions   \&print_function;

close OUT;


###
##  The helpers
#
sub print_line { print OUT @_ }

sub print_function {
    my $fun = shift;

    unless ($fun->{DOIT}) {
	print OUT $fun->{LINE};
	return;
    }

    my @decl;
    my @retn;
    my @argv;

    if ($fun->{UNI}) {
	push @decl, "WINDOW *win\t= c_win ? c_sv2window(ST(0), 0) : stdscr;";
	push @decl, "int\tc_mret\t= c_x ? c_domove(win, ST(c_x-1), ST(c_x)) : OK;";

	push @argv, "win";
    }

    foreach my $arg (@{$fun->{ARGV}}) {
	my $pos = $fun->{UNI} ? $arg->{NUM} ? "c_arg+$arg->{NUM}" : "c_arg"
	                      : $arg->{NUM};

	my $A = "ST($pos)";
	my $B = $arg->{SPEC}{B} || $pos;
	my $N = $arg->{NAME};
	my $T = length($arg->{DECL}) < 8 ? "\t" : "";
	my $D = eval qq("$arg->{DECL}$T$arg->{NAME}\t= $arg->{M_DECL};");

	if ($arg->{SPEC}{SHIFT}) {
	    splice @decl, $arg->{SPEC}{SHIFT}, 0, $D;
	}
	else {
	    push @decl, $D;
	}

	if ($arg->{M_RETN}) {
	  push @retn, eval qq("$arg->{M_RETN};");
	}

	push @argv, $arg->{SPEC}{AMP} ? "&" . $arg->{NAME} : $arg->{NAME};
    }

    my $pref = $fun->{SPEC}{CAST} ? "($fun->{DECL})" . $fun->{W} : $fun->{W};
    my $call = $pref . $fun->{NAME} . "(" . join(", ", @argv) . ");";

    if ($fun->{UNI}) {
	if ($fun->{DECL} eq 'void') {
	    $call = "if (c_mret == OK) { $call }";
	}
	else {
	    $call = eval qq("c_mret == ERR ? $fun->{M_NULL} : $call");
	}
    }

    if ($fun->{DECL} eq 'void')   {
	unshift @retn, $call;
    }
    else {
	my $A = "ST(0)";
	my $N = "ret";

	push @decl, "$fun->{DECL}\tret\t= $call";
	push @retn, "ST(0) = sv_newmortal();";
	push @retn,  eval qq("$fun->{M_RETN};");
    }

    push @decl, '' if @decl;

    my $count = $fun->{UNI} ? "count" : "exact";
    my $body  = join "\n\t", @decl, @retn;
    my $xsret = $fun->{DECL} ne 'void' ? 1 : 0;

    print OUT Q<<AAA;
################
#	XS(XS_Curses_$fun->{NAME})
#	{
#	    dXSARGS;
#	#ifdef C_\U$fun->{NAME}\E
#	    c_${count}args("$fun->{NAME}", items, $fun->{ARGC});
#	    {
#		$body
#	    }
#	    XSRETURN($xsret);
#	#else
#	    c_fun_not_there("$fun->{NAME}");
#	    XSRETURN(0);
#	#endif
#	}
#
################
AAA
}

sub print_function2 {
    my $fun = shift;

    return unless $fun->{DOIT};
    return if     $fun->{SPEC}{DUP};

    my $S     = " " x (3 - length $fun->{NUM});

    print OUT Q<<AAA;
################
#	#ifdef C_\U$fun->{NAME}\E
#		case $S$fun->{NUM}:  ret = 1;  break;
#	#endif
################
AAA
}

__END__
/*  This file can be automatically generated; changes may be lost.
**
**
**  CursesFun.c -- the functions
**
**  Copyright (c) 1994-2000  William Setzer
**
**  You may distribute under the terms of either the Artistic License
**  or the GNU General Public License, as specified in the README file.
*/

PAUSE
