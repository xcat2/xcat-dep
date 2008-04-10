#!/usr/local/bin/perl
##
##  make.Curses.pm  -- make Curses.pm
##
##  Copyright (c) 2000  William Setzer
##
##  You may distribute under the terms of either the Artistic License
##  or the GNU General Public License, as specified in the README file.

require 5.005;
use lib 'gen';
use Gen;

my $roff = 0;

open OUT, "> Curses.pm"    or die "Can't open Curses.pm: $!\n";

process_DATA_chunk  \&print_line;
process_variables   \&print_variable1;
process_DATA_chunk  \&print_line;
process_variables   \&print_variable2;  print OUT "\n";  $roff = 0;
process_DATA_chunk  \&print_line;
process_functions   \&print_function1;  print OUT "\n";  $roff = 0;
process_DATA_chunk  \&print_line;
process_constants   \&print_constant1;  print OUT "\n";  $roff = 0;
process_DATA_chunk  \&print_line;
process_functions   \&print_function2;  print OUT "\n";  $roff = 0;
process_DATA_chunk  \&print_line;
process_functions   \&print_function3;
process_DATA_chunk  \&print_line;
process_variables   \&print_variable3;  print OUT "\n";  $roff = 0;
process_DATA_chunk  \&print_line;
process_constants   \&print_constant2;  print OUT "\n";  $roff = 0;
process_DATA_chunk  \&print_line;

close OUT;

###
##  Helpers
#
sub print_line { print OUT @_ }

sub print_function1 {
    my $fun = shift;

    return unless $fun->{DOIT};
    return if     $fun->{SPEC}{DUP};

    my $L = 1 + length $fun->{NAME};

    if ($roff < 4)       { print OUT "   ";    $roff = 4 }
    if ($roff + $L > 76) { print OUT "\n   ";  $roff = 4 }
    print OUT ' ', $fun->{NAME};

    $roff += $L;
}

sub print_function2 {
    my $fun = shift;

    return unless $fun->{DOIT};
    return if     $fun->{SPEC}{DUP};
    return unless $fun->{W};

    my $L = 2 + length $fun->{NAME};

    if ($roff < 8)       { print OUT "       ";    $roff = 8 }
    if ($roff + $L > 76) { print OUT "\n       ";  $roff = 8 }
    print OUT ' w', $fun->{NAME};

    $roff += $L;

    if ($fun->{UNI} =~ /mv/) {
	$L += 2;

	if ($roff < 8)       { print OUT "       ";    $roff = 8 }
	if ($roff + $L > 76) { print OUT "\n       ";  $roff = 8 }
	print OUT ' mv', $fun->{NAME};

	$roff += $L;
	$L ++;

	if ($roff < 8)       { print OUT "       ";    $roff = 8 }
	if ($roff + $L > 76) { print OUT "\n       ";  $roff = 8 }
	print OUT ' mvw', $fun->{NAME};

	$roff += $L;
    }
}

sub print_function3 {
    my $fun = shift;

    return unless $fun->{DOIT};
    return if     $fun->{SPEC}{DUP};

    my $S = " " x (23 - length $fun->{NAME});

    print OUT "    ", $fun->{NAME}, $S, $fun->{UNI} ? "Yes" : " No";

    if ($fun->{W}) {
	print OUT "        w$fun->{NAME}";

	if ($fun->{UNI} =~ /mv/) {
	    print OUT " mv$fun->{NAME} mvw$fun->{NAME}";
	}
    }
    print OUT "\n";
}


sub print_variable1 {
    my $var = shift;

    return unless $var->{DOIT};

    my $S = " " x (12 - length $var->{NAME});

    print OUT qq{tie \$$var->{NAME},}, $S, qq{Curses::Vars, $var->{NUM};\n};
}

sub print_variable2 {
    my $var = shift;

    return unless $var->{DOIT};

    my $L = 1 + length $var->{NAME};

    if ($roff < 4)       { print OUT "   ";    $roff = 4 }
    if ($roff + $L > 76) { print OUT "\n   ";  $roff = 4 }
    print OUT ' ', $var->{NAME};
 
    $roff += $L;
    $L++;

    if ($roff < 4)       { print OUT "   ";    $roff = 4 }
    if ($roff + $L > 76) { print OUT "\n   ";  $roff = 4 }
    print OUT ' $', $var->{NAME};

    $roff += $L;
}

sub print_variable3 {
    my $var = shift;

    return unless $var->{DOIT};

    my $L = length $var->{NAME};
    my $M = 24 - $L % 24;

    if ($roff < 4)       { print OUT "    ";    $roff = 4 }
    if ($roff > 52)      { print OUT "\n    ";  $roff = 4 }
    print OUT $var->{NAME};

    $roff += $L;

    if ($M < 2)           { $M += 24           }
    if ($roff + $M <= 52) { print OUT " " x $M }
    $roff += $M;
}

sub print_constant1 {
    my $con = shift;

    return unless $con->{DOIT};

    my $L = 1 + length $con->{NAME};

    if ($roff < 4)       { print OUT "   ";    $roff = 4 }
    if ($roff + $L > 76) { print OUT "\n   ";  $roff = 4 }
    print OUT ' ', $con->{NAME};
 
    $roff += $L;
}

sub print_constant2 {
    my $con = shift;

    return unless $con->{DOIT};

    my $L = length $con->{NAME};
    my $M = 24 - $L % 24;

    if ($roff < 4)       { print OUT "    ";    $roff = 4 }
    if ($roff > 52)      { print OUT "\n    ";  $roff = 4 }
    print OUT $con->{NAME};

    $roff += $L;

    if ($M < 2)           { $M += 24           }
    if ($roff + $M <= 52) { print OUT " " x $M }
    $roff += $M;
}

__END__
##  This file can be automatically generated; changes may be lost.
##
##
##  CursesFun.c -- the functions
##
##  Copyright (c) 1994-2000  William Setzer
##
##  You may distribute under the terms of either the Artistic License
##  or the GNU General Public License, as specified in the README file.

###
##  For the brave object-using person
#
package Curses::Window;

@ISA = qw(Curses);

package Curses::Screen;

@ISA = qw(Curses);
sub new     { newterm(@_) }
sub DESTROY { }

package Curses::Panel;

@ISA = qw(Curses);
sub new     { new_panel(@_) }
sub DESTROY { }

package Curses::Menu;

@ISA = qw(Curses);
sub new     { new_menu(@_) }
sub DESTROY { }

package Curses::Item;

@ISA = qw(Curses);
sub new     { new_item(@_) }
sub DESTROY { }

package Curses::Form;

@ISA = qw(Curses);
sub new     { new_form(@_) }
sub DESTROY { }

package Curses::Field;

@ISA = qw(Curses);
sub new     { new_field(@_) }
sub DESTROY { }


package Curses;

$VERSION = 1.06;

use Carp;
require Exporter;
require DynaLoader;
@ISA = qw(Exporter DynaLoader);

bootstrap Curses;

sub new      {
    my $pkg = shift;
    my ($nl, $nc, $by, $bx) = (@_,0,0,0,0);

    unless ($_initscr++) { initscr() }
    return newwin($nl, $nc, $by, $bx);
}

sub DESTROY  { }

sub AUTOLOAD {
    my $N = $AUTOLOAD;
       $N =~ s/^.*:://;

    croak "Curses constant '$N' is not defined by your vendor";
}

sub printw   { addstr(sprintf shift, @_) }

PAUSE

@EXPORT = qw(
    printw

PAUSE

PAUSE

PAUSE
);

if ($OldCurses)
{
    @_OLD = qw(
        wprintw mvprintw wmvprintw

PAUSE
    );

    push (@EXPORT, @_OLD);
    for (@_OLD)
    {
	/^(?:mv)?(?:w)?(.*)/;
	eval "sub $_ { $1(\@_); }";
    }

    eval <<EOS;
    sub wprintw   { addstr(shift,               sprintf shift, @_) }
    sub mvprintw  { addstr(shift, shift,        sprintf shift, @_) }
    sub mvwprintw { addstr(shift, shift, shift, sprintf shift, @_) }
EOS
}

1;

__END__

=head1 NAME

Curses - terminal screen handling and optimization

=head1 SYNOPSIS

    use Curses;

    initscr;
    ...
    endwin;


   Curses::supports_function($function);
   Curses::supports_contsant($constant);

=head1 DESCRIPTION

C<Curses> is the interface between Perl and your system's curses(3)
library.  For descriptions on the usage of a given function, variable,
or constant, consult your system's documentation, as such information
invariably varies (:-) between different curses(3) libraries and
operating systems.  This document describes the interface itself, and
assumes that you already know how your system's curses(3) library
works.

=head2 Unified Functions

Many curses(3) functions have variants starting with the prefixes
I<w->, I<mv->, and/or I<wmv->.  These variants differ only in the
explicit addition of a window, or by the addition of two coordinates
that are used to move the cursor first.  For example, C<addch()> has
three other variants: C<waddch()>, C<mvaddch()>, and C<mvwaddch()>.
The variants aren't very interesting; in fact, we could roll all of
the variants into original function by allowing a variable number
of arguments and analyzing the argument list for which variant the
user wanted to call.

Unfortunately, curses(3) predates varargs(3), so in C we were stuck
with all the variants.  However, C<Curses> is a Perl interface, so we
are free to "unify" these variants into one function.  The section
L<"Supported Functions"> below lists all curses(3) function supported
by C<Curses>, along with a column listing if it is I<unified>.  If
so, it takes a varying number of arguments as follows:

=over 4

C<function( [win], [y, x], args );>

I<win> is an optional window argument, defaulting to C<stdscr> if not
specified.

I<y, x> is an optional coordinate pair used to move the cursor,
defaulting to no move if not specified.

I<args> are the required arguments of the function.  These are the
arguments you would specify if you were just calling the base function
and not any of the variants.

=back

This makes the variants obsolete, since their functionality has been
merged into a single function, so C<Curses> does not define them by
default.  You can still get them if you want, by setting the
variable C<$Curses::OldCurses> to a non-zero value before using the
C<Curses> package.  See L<"Perl 4.X C<cursperl> Compatibility">
for an example of this.

=head2 Objects

Objects are supported.  Example:

    $win = new Curses;
    $win->addstr(10, 10, 'foo');
    $win->refresh;
    ...

Any function that has been marked as I<unified> (see
L<"Supported Functions"> below and L<"Unified Functions"> above)
can be called as a method for a Curses object.

Do not use C<initscr()> if using objects, as the first call to get
a C<new Curses> will do it for you.

=head2 Security Concerns

It has always been the case with the curses functions, but please note
that the following functions:

    getstr()   (and optional wgetstr(), mvgetstr(), and mvwgetstr())
    inchstr()  (and optional winchstr(), mvinchstr(), and mvwinchstr())
    instr()    (and optional winstr(), mvinstr(), and mvwinstr())

are subject to buffer overflow attack.  This is because you pass in
the buffer to be filled in, which has to be of finite length, but
there is no way to stop a bad guy from typing.

In order to avoid this problem, use the alternate functions:

   getnstr()
   inchnstr()
   innstr()

which take an extra "size of buffer" argument.

=head1 COMPATIBILITY

=head2 Perl 4.X C<cursperl> Compatibility

C<Curses> has been written to take advantage of the new features of
Perl.  I felt it better to provide an improved curses programming
environment rather than to be 100% compatible.  However, many old
C<curseperl> applications will probably still work by starting the
script with:

    BEGIN { $Curses::OldCurses = 1; }
    use Curses;

Any old application that still does not work should print an
understandable error message explaining the problem.

Some functions and variables are not supported by C<Curses>, even with
the C<BEGIN> line.  They are listed under
L<"curses(3) items not supported by Curses">.

The variables C<$stdscr> and C<$curscr> are also available as
functions C<stdscr> and C<curscr>.  This is because of a Perl bug.
See the L<BUGS> section for details.

=head2 Incompatibilities with previous versions of C<Curses>

In previous versions of this software, some Perl functions took a
different set of parameters than their C counterparts.  This is no
longer true.  You should now use C<getstr($str)> and C<getyx($y, $x)>
instead of C<$str = getstr()> and C<($y, $x) = getyx()>.

=head2 Incompatibilities with other Perl programs

    menu.pl, v3.0 and v3.1
	There were various interaction problems between these two
	releases and Curses.  Please upgrade to the latest version
	(v3.3 as of 3/16/96).

=head1 DIAGNOSTICS

=over 4

=item * Curses function '%s' called with too %s arguments at ...

You have called a C<Curses> function with a wrong number of
arguments.

=item * argument %d to Curses function '%s' is not a Curses %s at ...
=item * argument is not a Curses %s at ...

The argument you gave to the function wasn't what it wanted.

This probably means that you didn't give the right arguments to a
I<unified> function.  See the DESCRIPTION section on L<Unified
Functions> for more information.

=item * Curses function '%s' is not defined by your vendor at ...

You have a C<Curses> function in your code that your system's curses(3)
library doesn't define.

=item * Curses variable '%s' is not defined by your vendor at ...

You have a C<Curses> variable in your code that your system's curses(3)
library doesn't define.

=item * Curses constant '%s' is not defined by your vendor at ...

You have a C<Curses> constant in your code that your system's curses(3)
library doesn't define.

=item * Curses::Vars::FETCH called with bad index at ...
=item * Curses::Vars::STORE called with bad index at ...

You've been playing with the C<tie> interface to the C<Curses>
variables.  Don't do that.  :-)

=item * Anything else

Check out the F<perldiag> man page to see if the error is in there.

=back

=head1 BUGS

If you use the variables C<$stdscr> and C<$curscr> instead of their
functional counterparts (C<stdscr> and C<curscr>), you might run into
a bug in Perl where the "magic" isn't called early enough.  This is
manifested by the C<Curses> package telling you C<$stdscr> isn't a
window.  One workaround is to put a line like C<$stdscr = $stdscr>
near the front of your program.

Probably many more.

=head1 AUTHOR

William Setzer <William_Setzer@ncsu.edu>

=head1 SYNOPSIS OF PERL CURSES SUPPORT

=head2 Supported Functions

    Supported            Unified?     Supported via $OldCurses[*]
    ---------            --------     ------------------------
PAUSE

[*] To use any functions in this column, the variable
C<$Curses::OldCurses> must be set to a non-zero value before using the
C<Curses> package.  See L<"Perl 4.X cursperl Compatibility"> for an
example of this.

=head2 Supported Variables

PAUSE

=head2 Supported Constants

PAUSE

=head2 curses(3) functions not supported by C<Curses>

    tstp _putchar fullname scanw wscanw mvscanw mvwscanw ripoffline
    setupterm setterm set_curterm del_curterm restartterm tparm tputs
    putp vidputs vidattr mvcur tigetflag tigetnum tigetstr tgetent
    tgetflag tgetnum tgetstr tgoto tputs

=head2 menu(3) functions not supported by C<Curses>

    set_item_init item_init set_item_term item_term set_menu_init
    menu_init set_menu_term menu_term

=head2 form(3) functions not supported by C<Curses>

    new_fieldtype free_fieldtype set_fieldtype_arg
    set_fieldtype_choice link_fieldtype set_form_init form_init
    set_form_term form_term set_field_init field_init set_field_term
    field_term set_field_type field_type
