package Gen;

@ISA    = qw(Exporter);
@EXPORT = qw(lookup Q process_DATA_chunk
	     process_functions process_variables process_constants
	     process_typedefs);

my $list_fun = "gen/list.fun";
my $list_var = "gen/list.var";
my $list_con = "gen/list.con";
my $list_typ = "gen/list.typ";

###
##  Declaration entries
#
my $MAP = {
    'attr_t' => {
	'DECL_NOR' => '(attr_t)SvIV($A)',
	'RETN_NOR' => 'sv_setiv($A, (IV)$N)',
	'TEST_NOR' => '0',
	'DECL_OUT' => '0',
	'RETN_OUT' => 'sv_setiv($A, (IV)$N);',
	'TEST_OUT' => 'LINES',
	'RETN_NUL' => 'ERR',
    },

    'bool' => {
	'DECL_NOR' => '(int)SvIV($A)',
	'RETN_NOR' => 'sv_setiv($A, (IV)$N)',
	'TEST_NOR' => '0',
	'RETN_NUL' => 'ERR',
    },

    'char' => {
	'RETN_NOR' => 'sv_setpvn($A, (char *)&$N, 1)',
	'RETN_NUL' => 'ERR',
    },

    'char *' => {
	'DECL_NOR' => '(char *)SvPV($A,PL_na)',
	'RETN_NOR' => 'sv_setpv((SV*)$A, $N)',
	'TEST_NOR' => '0',
	'DECL_OUT' => '(char *)sv_grow($A, $B)',
	'RETN_OUT' => 'c_setchar($A, $N)',
	'TEST_OUT' => '0',
	'DECL_OPT' => '$A != &PL_sv_undef ? (char *)SvPV($A,PL_na) : NULL',
	'TEST_OPT' => '0',
	'RETN_NUL' => 'NULL',
    },

    'chtype' => {
	'DECL_NOR' => 'c_sv2chtype($A)',
	'RETN_NOR' => 'c_chtype2sv($A, $N)',
	'TEST_NOR' => '0',
	'RETN_NUL' => 'ERR',
    },

    'chtype *' => {
	'DECL_NOR' => '(chtype *)SvPV($A,PL_na)',
	'TEST_NOR' => '0',
	'DECL_OUT' => '(chtype *)sv_grow($A, ($B)*sizeof(chtype))',
	'RETN_OUT' => 'c_setchtype($A, $N)',
	'TEST_OUT' => '0',
    },

    'FIELD *' => {
	'DECL_NOR' => 'c_sv2field($A, $B)',
	'RETN_NOR' => 'c_field2sv($A, $N)',
	'TEST_NOR' => '0',
	'RETN_NUL' => 'NULL',
    },

    'FIELD **' => {
	'DECL_NOR' => '(FIELD **)SvPV($A,PL_na)',
	'RETN_NOR' => 'sv_setpv((SV*)$A, (char *)$N)',
	'TEST_NOR' => '0',
	'RETN_NUL' => '0',
    },

    'FILE *' => {
	'DECL_NOR' => 'IoIFP(sv_2io($A))',
	'TEST_NOR' => '0',
    },

    'FORM *' => {
	'DECL_NOR' => 'c_sv2form($A, $B)',
	'RETN_NOR' => 'c_form2sv($A, $N)',
	'TEST_NOR' => '0',
	'RETN_NUL' => 'NULL',
    },

    'int' => {
	'DECL_NOR' => '(int)SvIV($A)',
	'RETN_NOR' => 'sv_setiv($A, (IV)$N)',
	'TEST_NOR' => '0',
	'DECL_OUT' => '0',
	'RETN_OUT' => 'sv_setiv($A, (IV)$N);',
	'TEST_OUT' => 'LINES',
	'RETN_NUL' => 'ERR',
    },

    'ITEM *' => {
	'DECL_NOR' => 'c_sv2item($A, $B)',
	'RETN_NOR' => 'c_item2sv($A, $N)',
	'TEST_NOR' => '0',
	'RETN_NUL' => 'NULL',
    },

    'ITEM **' => {
	'DECL_NOR' => '(ITEM **)SvPV($A,PL_na)',
	'RETN_NOR' => 'sv_setpv((SV*)$A, (char *)$N)',
	'TEST_NOR' => '0',
	'RETN_NUL' => '0',
    },

    'MENU *' => {
	'DECL_NOR' => 'c_sv2menu($A, $B)',
	'RETN_NOR' => 'c_menu2sv($A, $N)',
	'TEST_NOR' => '0',
	'RETN_NUL' => 'NULL',
    },

    'MEVENT *' => {
	'DECL_NOR' => '(MEVENT *)SvPV($A,PL_na)',
	'TEST_NOR' => '0',
	'DECL_OUT' => '(MEVENT *)sv_grow($A, 2 * sizeof(MEVENT))',
	'RETN_OUT' => 'c_setmevent($A, $N)',
	'TEST_OUT' => '0',
    },

    'mmask_t' => {
	'DECL_NOR' => '(mmask_t)SvIV($A)',
	'RETN_NOR' => 'sv_setiv($A, (IV)$N)',
	'TEST_NOR' => '0',
	'DECL_OUT' => '0',
	'RETN_OUT' => 'sv_setiv($A, (IV)$N);',
	'TEST_OUT' => 'LINES',
	'RETN_NUL' => 'ERR',
    },

    'PANEL *' => {
	'DECL_NOR' => 'c_sv2panel($A, $B)',
	'RETN_NOR' => 'c_panel2sv($A, $N)',
	'TEST_NOR' => '0',
	'DECL_OPT' => '$A != &PL_sv_undef ? c_sv2panel($A, $B) : NULL',
        'TEST_OPT' => '0',
	'RETN_NUL' => 'NULL',
    },

    'SCREEN *' => {
	'DECL_NOR' => 'c_sv2screen($A, $B)',
	'RETN_NOR' => 'c_screen2sv($A, $N)',
	'TEST_NOR' => '0',
	'RETN_NUL' => 'NULL',
    },

    'short' => {
	'DECL_NOR' => '(short)SvIV($A)',
	'TEST_NOR' => '0',
	'DECL_OUT' => '0',
	'RETN_OUT' => 'sv_setiv($A, (IV)$N);',
	'TEST_OUT' => 'LINES',
    },

    'void' => {
	'RETN_NOR' => 'not gonna happen',
	'RETN_NUL' => 'not gonna happen',
    },

    'void *' => {
	'DECL_NOR' => '0',
	'TEST_NOR' => '0',
    },

    'WINDOW *' => {
	'DECL_NOR' => 'c_sv2window($A, $B)',
	'RETN_NOR' => 'c_window2sv($A, $N)',
	'TEST_NOR' => 'stdscr',
	'RETN_NUL' => 'NULL',
    }
};

##  Allow us to put some quoting around here documents to make them stand out
#
sub Q {
    my $text = shift;

    $text =~ s/^#{16}\n//mg;
    $text =~ s/^#\t?//mg;
    $text;
}

##  Print a chunk of data, 'til we hit PAUSE
#
sub process_DATA_chunk {
    my  $proc = shift;
    my ($pkg) = (caller)[0];

    *DATA = *{"${pkg}::DATA"};

    while (<DATA>) {
	last if /^PAUSE$/;

	&{$proc}($_);
    }
}

my $pattern = '^\s* (?:const \s+)? ( (?:[{<|] [^}>|]+ [}>|])* )' .
    '\s* (\S+ (?: \s+ \*+)?) \s* ( [{<|] \w+ [}>|] )* \s* (\w+)';


sub process_functions {
    my $proc = shift;
    my $numf = 1;

    open INF, $list_fun or die "Can't open $list_fun: $!\n";

    FCN:
    while (<INF>) {
	next if /^!/;

	while (s/\\\n//) {
	    $_ .= <INF>;
	    die "$list_fun: Unterminated backslash\n" if eof;
	}

	my $fun = {
	    LINE  => $_,
	    DOIT  => 0
	};

	if (/^> (.+) \( (.+) \) ; /x) {
	    my $lhs  = $1;
	    my $args = $2;

	    unless ($lhs =~ /$pattern/xo) {
		warn "$lhs($args): bad function prototype\n";
		next FCN;
	    }

	    $fun->{SPEC} = $1;
	    $fun->{DECL} = $2;
	    $fun->{UNI}  = $3;
	    $fun->{NAME} = $4;
	    $fun->{DOIT} = 1;
	    $fun->{NUM}  = $numf++;
	    $fun->{ARGV} = [ ];

	    $fun->{SPEC} = { map { uc($_) => 1 } $fun->{SPEC} =~ /{(.+?)}/g };
	    $fun->{W}    = $fun->{UNI} && $fun->{UNI} =~ /[{|]/ ? 'w' : '';
	    my $argc = 0;
	    foreach my $entry (split /\s*,\s*/, $args) {
		next if $entry eq 'void';

		unless ($entry =~ /$pattern/xo) {
		    warn "$fun->{NAME}( $entry ): bad arg prototype\n";
		    next FCN;
		}

		my $arg = $fun->{ARGV}[$argc] = { };
		$arg->{SPEC} = $1;
		$arg->{DECL} = $2;
		$arg->{NAME} = $4;

		$arg->{SPEC} = { map { /=/ ? (uc($`) => $') : (uc($_) => 1) }
				  $arg->{SPEC} =~ /{(.+?(?:=.+?)?)}/g };

		$arg->{MAP}  = { };
		$arg->{NUM}  = $argc++;

		my $typ = 'NOR';
		if    ($arg->{SPEC}{OUT}) { $typ = 'OUT' }
		elsif ($arg->{SPEC}{OPT}) { $typ = 'OPT' }

		my $decl = $MAP->{$arg->{DECL}}{"DECL_$typ"};
		if (not defined $decl) {
		    warn "$fun->{NAME}( $arg->{DECL} $arg->{NAME} ): " .
			"no map rewrite for DECL_$typ\n";
		    next FCN;
		}
		$arg->{M_DECL} = $decl;

		if ($typ eq 'OUT') {
		    my $retn = $MAP->{$arg->{DECL}}{"RETN_$typ"};
		    if (not defined $retn) {
			warn "$fun->{NAME}( $arg->{DECL} $arg->{NAME} ): " .
			    "no map rewrite for RETN_$typ\n";
			next FCN;
		    }
		    $arg->{M_RETN} = $retn;
		}

		my $test = $MAP->{$arg->{DECL}}{"TEST_$typ"};
		if (not defined $test) {
		    warn "$fun->{NAME}( $arg->{DECL} $arg->{NAME} ): " .
			"no map rewrite for TEST_$typ\n";
		    next FCN;
		}
		$arg->{M_TEST} = $test;
	    }

	    my $retn = $MAP->{$fun->{DECL}}{RETN_NOR};
	    if (not defined $retn) {
		warn "$fun->{DECL} $fun->{NAME}( ): " .
		    "no map rewrite for RETN_NOR\n";
		next FCN;
	    }

	    my $null = $MAP->{$fun->{DECL}}{RETN_NUL};
	    if (not defined $null) {
		warn "$fun->{DECL} $fun->{NAME}( ): " .
		    "no map rewrite for RETN_NUL\n";
		next FCN;
	    }

	    $fun->{M_RETN} = $retn;
	    $fun->{M_NULL} = $null;
	    $fun->{ARGC}   = $argc;
	}
	&{$proc}($fun);
    }

    close INF;
}

sub process_variables {
    my $proc = shift;
    my $numv = 1;

    open INV, $list_var or die "Can't open $list_var: $!\n";

    while (<INV>) {
	next if /^!/;

	while (s/\\\n//) {
	    $_ .= <INV>;
	    die "$list_var: Unterminated backslash\n" if eof;
	}

	my $var = {
	    LINE  => $_,
	    DOIT  => 0
	};

	if (/^> (.+) ; /x) {
	    my $lhs  = $1;

	    unless ($lhs =~ /$pattern/xo) {
		warn "$lhs: bad variable prototype\n";
		next;
	    }

	    $var->{SPEC} = $1;
	    $var->{DECL} = $2;
	    $var->{NAME} = $4;
	    $var->{DOIT} = 1;
	    $var->{NUM}  = $numv++;

	    $var->{SPEC} = { map { uc($_) => 1 } $var->{SPEC} =~ /{(.+?)}/g };

	    my $decl = $MAP->{$var->{DECL}}{DECL_NOR};
	    if (not defined $decl) {
		warn "$var->{DECL} $var->{NAME}: " .
		    "no map rewrite for DECL_$typ\n";
		next;
	    }

	    my $retn = $MAP->{$var->{DECL}}{RETN_NOR};
	    if (not defined $retn) {
		warn "$var->{DECL} $var->{NAME}: " .
		    "no map rewrite for RETN_NOR\n";
		next;
	    }

	    $var->{M_DECL} = $decl;
	    $var->{M_RETN} = $retn;
	}
	&{$proc}($var);
    }

    close INV;
}

sub process_constants {
    my $proc = shift;
    my $numc = 1;

    open INC, $list_con or die "Can't open $list_con: $!\n";

    while (<INC>) {
	next if /^!/;

	while (s/\\\n//) {
	    $_ .= <INC>;
	    die "$list_con: Unterminated backslash\n" if eof;
	}

	my $con = {
	    LINE  => $_,
	    DOIT  => 0
	};

	if (/^> (.+) ; /x) {
	    my $lhs  = $1;

	    unless ($lhs =~ /$pattern/xo) {
		warn "$lhs: bad variable prototype\n";
		next;
	    }

	    $con->{SPEC} = $1;
	    $con->{DECL} = $2;
	    $con->{NAME} = $4;
	    $con->{DOIT} = 1;
	    $con->{NUM}  = $numc++;

	    $con->{SPEC} = { map { uc($_) => 1 } $con->{SPEC} =~ /{(.+?)}/g };

	}
	&{$proc}($con);
    }

    close INC;
}

sub process_typedefs {
    my $proc = shift;
    my $numt = 1;

    open INT, $list_typ  or die "Can't open $list_typ: $!\n";

    while (<INT>) {
	next if /^!/;

	while (s/\\\n//) {
	    $_ .= <INT>;
	    die "$list_typ: Unterminated backslash\n" if eof;
	}

	my $typ = {
	    LINE  => $_,
	    DOIT  => 0
	};

	if (/^> \s+ (.+) /x) {
	    my $lhs  = $1;

	    unless ($lhs =~ /$pattern/xo) {
		warn "$lhs: bad typedef prototype\n";
		next;
	    }

	    $typ->{SPEC} = $1;
	    $typ->{DECL} = $2;
	    $typ->{NAME} = $4;
	    $typ->{DOIT} = 1;
	    $typ->{NUM}  = $numt++;

	    $typ->{SPEC} = { map { uc($_) => 1 } $typ->{SPEC} =~ /{(.+?)}/g };

	}
	&{$proc}($typ);
    }

    close INT;
}

1;
