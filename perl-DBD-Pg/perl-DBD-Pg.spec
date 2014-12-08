#
# spec file for package perl-DBD-Pg
#
# Copyright (c) 2014 SUSE LINUX Products GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#


Name:           perl-DBD-Pg
%define cpan_name DBD-Pg
Summary:        PostgreSQL database driver for the DBI module
License:        GPL-1.0+ or Artistic-1.0
Group:          Development/Libraries/Perl
Version:        3.4.1
Release:        3.1
Url:            http://search.cpan.org/dist/DBD-Pg/
Source:         http://www.cpan.org/authors/id/T/TU/TURNSTEP/DBD-Pg-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
BuildRequires:  openssl-devel
BuildRequires:  perl
BuildRequires:  perl-macros
BuildRequires:  postgresql-devel >= 7.4
# For the Testsuite
BuildRequires:  postgresql-server
BuildRequires:  perl(Test::More) >= 0.61
#BuildRequires:  perl(Cwd)
BuildRequires:  perl(DBI) >= 1.614
#BuildRequires:  perl(File::Comments)
#BuildRequires:  perl(File::Comments::Plugin::C)
#BuildRequires:  perl(File::Temp)
#BuildRequires:  perl(Module::Signature) >= 0.50
#BuildRequires:  perl(Perl::Critic)
#BuildRequires:  perl(Pod::Spell)
#BuildRequires:  perl(Test::Pod) >= 0.95
#BuildRequires:  perl(Test::Pod::Coverage)
#BuildRequires:  perl(Test::Warn) >= 0.08
#BuildRequires:  perl(Test::YAML::Meta) >= 0.03
#BuildRequires:  perl(Text::SpellChecker)
#
#Recommends:     perl(Cwd)
Requires:       perl(DBI) >= 1.614
#Recommends:     perl(File::Comments)
#Recommends:     perl(File::Comments::Plugin::C)
#Recommends:     perl(File::Temp)
#Suggests:       perl(Module::Signature) >= 0.50
#Suggests:       perl(Perl::Critic)
#Suggests:       perl(Pod::Spell)
#Suggests:       perl(Test::Pod) >= 0.95
#Suggests:       perl(Test::Pod::Coverage)
#Suggests:       perl(Test::Warn) >= 0.08
#Suggests:       perl(Test::YAML::Meta) >= 0.03
#Recommends:     perl(Text::SpellChecker)
%{perl_requires}

%description
DBD::Pg is a Perl module that works with the DBI module to provide access
to PostgreSQL databases.

%prep
%setup -q -n %{cpan_name}-%{version}

%build
export POSTGRES_INCLUDE=/usr/include/pgsql
export POSTGRES_LIB="%{_libdir} -lssl"
%{__perl} Makefile.PL INSTALLDIRS=vendor OPTIMIZE="%{optflags}"
%{__make} %{?_smp_mflags}

%check
%{__make} test

%install
%perl_make_install
# remove testme.tmp.pl
%{__rm} -f $RPM_BUILD_ROOT%perl_vendorarch/DBD/testme.tmp.pl
%perl_process_packlist
%perl_gen_filelist

%clean
%{__rm} -rf %{buildroot}

%files -f %{name}.files
%defattr(644,root,root,755)
%doc Changes README SIGNATURE TODO testme.tmp.pl

%changelog
* Thu Aug 21 2014 stephan.barth@suse.com
- Update to version 3.4.1 from 3.4.0
  Change from upstream:
  - Allow '%%' again for the type in table_info() and thus tables()
    It's not documented or tested in DBI, but it used to work until
    DBD::Pg 3.4.0, and the change broke DBIx::Class::Schema::Loader, which
    uses type='%%'.
* Mon Aug 18 2014 stephan.barth@suse.com
- update to version 3.4.0 from 3.3.0
  Upstream changes:
  - Cleanup and improve table_info()
    table_info() type searching now supports TABLE, VIEW, SYSTEM TABLE,
    SYSTEM VIEW, and LOCAL TEMPORARY
    table_info() object searching fully supports the above types.
    table_info() object searching no longer ignores invalid types - a filter
    of 'NOSUCH' will return no rows, and 'NOSUCH,LOCAL TEMPORARY' will
    return only temp objects.
    tableinfo() type filters are strictly matched now ... previously a
    search for SYSTEM TABLE would have fetched plain TABLE objects.
    table_info() now treats temporary tables and temporary views as LOCAL
    TEMPORARY
  - Make sure column_info() and table_info() can handle materialized views.
* Mon Jun  2 2014 stephan.barth@suse.com
- update to version 3.3.0 from 3.2.1
  Upstream changes:
  - Major cleanup of UTF-8 support
  - Rewrite foreign_key_info to be just one query
  - Remove ODBC support from foreign_key_info
  - Remove use of dTHX in functions in quote.c and types.c
* Thu May 29 2014 stephan.barth@suse.com
- update to version 3.2.1 from 3.2.0
  Changes from upstream:
  - Stricter testing for array slices: disallow number-colon-number from
    being parsed as a placeholder.
    [Greg Sabino Mullane] (CPAN bug #95713)
  - Fix for small leak with AutoInactiveDestroy
    [David Dick] (CPAN bug #95505)
  - Adjust test regex to fix failing t/01_connect.t on some platforms
    [Greg Sabino Mullane]
  - Further tweaks to get PGINITDB working for test suite.
    [Nicholas Clark]
* Fri May 16 2014 stephan.barth@suse.com
- update to version 3.2.0 from 3.1.1
  Changes from upstream:
  - Add new attribute pg_placeholder_nocolons to turn off all parsing of
    colons into placeholders.
    [Graham Ollis] (CPAN bug #95173)
  - Fix incorrect skip count for HandleSetErr
    [Greg Sabino Mullane] (CPAN bug #94841)
  - Don't attempt to use the POSIX signalling stuff if the OS is Win
    [Greg Sabino Mullane] (CPAN bug ##94841)
  - Fix missing check for PGINITDB in the test suite.
    [Nicholas Clark]
* Tue Apr  8 2014 stephan.barth@suse.com
- update to version 3.1.1 from 3.0.0
  Changes from upstream:
  Version 3.1.1  Released April 6, 2014
  - Minor adjustments so tests pass in varying locales.
  Version 3.1.0  Released April 4, 2014
  - Make sure UTF-8 enabled notifications are handled correctly
    [Greg Sabino Mullane]
  - Allow "WITH" and "VALUES" as valid words starting a DML statement
    [Greg Sabino Mullane] (CPAN bug #92724)
* Wed Mar 26 2014 stephan.barth@suse.com
- update from version 2.19.3 to 3.0.0
  These are the most important changes from upstream:
  - Major change in UTF-8 handling
  - Better handling of libpq errors to return SQLSTATE 08000
  - Add support for AutoInactiveDestroy
  and many bugfixes. See the Changes file for a full list of changes.
* Tue Jan 21 2014 kpetsch@suse.com
-Added BuildRequires postgresql-server to provide initdb for the
  testsuite.
* Fri May  3 2013 darin@darins.net
- update to 2.19.3
  - Fix bug in pg_st_split_statement causing segfaults
    (CPAN bug #79035)
  - See Changes for 2.19.0 - 2.19.2 changes
* Tue Nov 29 2011 coolo@suse.com
- update to 2.18.1
  - Fix LANG testing issue [GSM] (CPAN bug #56705)
  - Fix bug when async commands issued immediately after a COPY.
    [GSM] (CPAN bug #68041)
* Fri Apr  8 2011 chris@computersalat.de
- fix deps
  o add openssl-devel
- fix build
  o build with -lssl
- bzip source
- add testme.tmp.pl to doc
* Thu Mar 31 2011 coolo@novell.com
- update to 2.18.0
  - Thanks to 123people.com for sponsoring work on this release [GSM]
  - Fix memory leak when binding arrays [GSM] (CPAN bug #65734)
  - Fix memory leak with ParamValues. [Martin J. Evans] (CPAN bug #60863)
  - New cancel() method per DBI spec. [Eric Simon] (CPAN bug #63516)
  - Fix memory leak in handle_old_async (missing PQclear)
  [Rainer Weikusat] (CPAN bug #63408)
  - Fix memory leak in pg_db_cancel (missing PQclear)
  [Rainer Weikusat] (CPAN bug #63441)
  - Mark pg_getcopydata strings as UTF8 as needed (CPAN bug #66006)
  - Function dequote_bytea returning void should not try to return something
  [Dagobert Michelsen] (CPAN bug #63497)
  - Fix the number of tests to skip in t/01connect.t when the $DBI_DSN
  environment variable lacks a database specification. [David E. Wheeler]
  - Fix algorithm for skipping tests in t/06bytea.t when running on a version
  of PostgreSQL lower than 9.0. [David E. Wheeler]
  - Small tweaks to get tests working when compiled against Postgres 7.4
  (CPAN bug #61713) [GSM]
  - Fix failing test when run as non-superuser [GSM] (CPAN bug #61534)
* Thu Dec  2 2010 chris@computersalat.de
- update to 2.17.2
  - Support dequoting of hex bytea format for 9.0.
    [Dagfinn Ilmari MannsÃ¥ker] (CPAN bug #60200).
  - Don't PQclear on execute() if there is an active async query
    [rweikusat at mssgmbh.com] (CPAN bug #58376)
  - Allow data_sources() to accept any case-variant of 'dbi:Pg' (CPAN bug #61574)
  - Fix failing test in t/04misc.t on Perl 5.12. [Eric Simon]
  - Fix for some 7.4 failing tests [Dagfinn Ilmari MannsÃ¥ker]
  - Return bare instead of undef in test connections (CPAN bug #61574)
- recreated by cpanspec 1.78
- removed Authors
* Wed Dec  1 2010 coolo@novell.com
- switch to perl_requires macro
* Wed Apr 21 2010 chris@computersalat.de
- update to 2.17.1
  - Only use lo_import_with_oid if Postgres libraries are 8.4 or better
    [GSM] (CPAN bug #56363)
- added Buildi-/Req perl(version)
- fix deps for postgresql-devel >= 7.4
* Wed Apr  7 2010 chris@computersalat.de
- update to 2.17.0
  - Do not automatically ROLLBACK on a failed pg_cancel [GSM]
    (CPAN bug #55188)
  - Added support for new lo_import_with_oid function.
    [GSM] (CPAN bug #53835)
  - Don't limit stored user name to \w in tests [GSM]
    (CPAN bug #54372)
  - Allow tests to support versions back to Postgres 7.4 [GSM]
- TestSuite broken for postgresql < 8.4
  o undefined symbol: lo_import_with_oid
  o BUG opened
    https://rt.cpan.org/Public/Bug/Display.html?id=56363
* Tue Apr  6 2010 chris@computersalat.de
- update to 2.16.1
  - Output error messages in UTF-8 as needed. Reported biy
    Michael Hofmann. [GSM] (CPAN bug #53854)
- 2.16.0 Released December 17, 2009
  - Put in a test for high-bit characters in bytea handling.
  [Bryce Nesbitt] (see also CPAN bug #39390)
  - Better SQLSTATE code on connection failure (CPAN bug #52863)
  [Chris Travers with help from Andrew Gierth]
  - Fixed POD escapes (CPAN bug #51856) [FWIE@cpan.org]
- cleanup spec
  o sort TAGS
  o upated Summary
  o macros
  o fixed deps
- added perl-macros
* Sun Jan 10 2010 jengelh@medozas.de
- enable parallel build
* Wed Aug 12 2009 max@suse.de
- New version: 2.15.1.
- http://cpansearch.perl.org/src/TURNSTEP/DBD-Pg-2.15.1/Changes
* Thu Sep 11 2008 max@suse.de
- New version: 2.10.3:
  * Add the 'DBD' trace setting to output only non-DBI trace
    messages, and allow 'dbd_verbose' as a connection attribute
    for the same effect.
  * Allow multi-statement do() calls with parameters to work if
    pg_server_prepare is set to 0
  * Add support for database handle attribute "ReadOnly".
  * Added in payload strings for LISTEN/NOTIFY in 8.4.
  * Plus more bug fixes and improvements to the test suite and
    documentation.
* Tue Apr 22 2008 max@suse.de
- Fixed file list.
* Thu Apr 17 2008 max@suse.de
- New version: 2.6.0. Changes include:
  * Various performance improvements.
  * Add Bundle::DBD::Pg
  * Fix memory leaks in dbdimp.c
  * Fix strlen problems in dbdimp.c
  * Overhaul COPY functions
  * Add support for arrays
  * Add support for asynchronous queries
- See /usr/share/doc/packages/perl-DBD-Pg/Changes for details.
* Fri May 19 2006 max@suse.de
- New version: 1.49:
  * Added support for geometric types.
  * Various bugfixes.
* Wed Jan 25 2006 mls@suse.de
- converted neededforbuild to BuildRequires
* Tue Jan 17 2006 max@suse.de
- New version: 1.42 (bug #128183).
* Sat Feb 28 2004 ro@suse.de
- fix requirement for /usr/local
- fix "control reaches end of non-void function"
* Sat Jan 10 2004 adrian@suse.de
- build as user
* Fri Aug 22 2003 mjancar@suse.cz
- require the perl version we build with
* Mon Jul 21 2003 max@suse.de
- new version: 1.22
- Fix build for perl-5.8.1.
* Mon Jun 30 2003 ro@suse.de
- remove traces of buildroot from installed files
* Sun Jun 22 2003 coolo@suse.de
- package directories
* Wed Feb  5 2003 ro@suse.de
- updated neededforbuild
* Wed Jul  3 2002 max@suse.de
- New package perl-DBD-Pg version 1.13.
- A database driver for perl-DBI and PostgreSQL.
