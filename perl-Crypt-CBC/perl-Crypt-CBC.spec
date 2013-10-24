#
# spec file for package perl-Crypt-CBC
#
# Copyright (c) 2013 SUSE LINUX Products GmbH, Nuernberg, Germany.
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


Name:           perl-Crypt-CBC
Version:        2.33
Release:        3.7
%define cpan_name Crypt-CBC
Summary:        Encrypt Data with Cipher Block Chaining Mode
License:        GPL-1.0+ or Artistic-1.0
Group:          Development/Libraries/Perl
Url:            http://search.cpan.org/dist/Crypt-CBC/
Source:         http://www.cpan.org/authors/id/L/LD/LDS/%{cpan_name}-%{version}.tar.gz
BuildArch:      noarch
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
BuildRequires:  perl
BuildRequires:  perl-macros
#BuildRequires: perl(Crypt::CBC)
#BuildRequires: perl(Crypt::IDEA)
%{perl_requires}

%description
This module is a Perl-only implementation of the cryptographic cipher block
chaining mode (CBC). In combination with a block cipher such as DES or
IDEA, you can encrypt and decrypt messages of arbitrarily long length. The
encrypted messages are compatible with the encryption format used by the
*OpenSSL* package.

To use this module, you will first create a Crypt::CBC cipher object with
new(). At the time of cipher creation, you specify an encryption key to use
and, optionally, a block encryption algorithm. You will then call the
start() method to initialize the encryption or decryption process, crypt()
to encrypt or decrypt one or more blocks of data, and lastly finish(), to
pad and encrypt the final block. For your convenience, you can call the
encrypt() and decrypt() methods to operate on a whole data value at once.

%prep
%setup -q -n %{cpan_name}-%{version}

%build
%{__perl} Makefile.PL INSTALLDIRS=vendor
%{__make} %{?_smp_mflags}

%check
%{__make} test

%install
%perl_make_install
%perl_process_packlist
%perl_gen_filelist

%files -f %{name}.files
%defattr(-,root,root,755)
%doc Changes Crypt-CBC-2.16-vulnerability.txt README

%changelog
* Tue Aug  6 2013 coolo@suse.com
- updated to 2.33
  - Fix minor RT bugs 83175 and 86455.
* Mon Jun  3 2013 coolo@suse.com
- updated to 2.32
  - Fixes "Taint checks are turned on and your key is tainted" error when autogenerating salt and IV.
  - Fixes to regular expressions to avoid rare failures to
    correctly strip padding in decoded messages.
  - Add padding type = "none".
  - Both fixes contributed by Bas van Sisseren.
* Fri Nov 18 2011 coolo@suse.com
- use original .tar.gz
* Fri Aug 26 2011 chris@computersalat.de
- remove Author from desc
- added bcond_with opt
  o test optional pkgs via local build (osc build --with opt)
- fix deps for CentOS
- some spec cleanup
* Wed Dec  8 2010 coolo@novell.com
- avoid even more requires to avoid even more cycles
* Tue Nov 30 2010 coolo@novell.com
- remove extra requires to avoid cycle
* Wed Nov 24 2010 chris@computersalat.de
- recreated by cpanspec 1.78
  o fix deps
- noarch pkg
* Sun Jan 10 2010 jengelh@medozas.de
- enable parallel build
* Fri Feb 27 2009 anicka@suse.cz
- update to 2.30
  * setting $cipher correctly
* Thu Jun 19 2008 anicka@suse.cz
- update to 2.29
  * Fixed errors that occurred when encrypting/decrypting utf8
  strings in Perl's more recent than 5.8.8.
* Wed Apr  2 2008 anicka@suse.cz
- update to 2.28
  - Fixed bug in onesandzeroes test that causes it to fail
  with Rijndael module is not installed.
  - When taint mode is turned on and user is using a tainted key,
  explicitly check tainting of key in order to avoid "cryptic"
  failure messages from some crypt modules.
  - Fixed onezeropadding test, which was not reporting
  its test count properly.
  - Fixed failure of oneandzeroes padding when plaintext size is
  an even multiple of blocksize.
  - Added new "rijndael_compat" padding method, which is compatible
  with the oneandzeroes padding method used by Crypt::Rijndael in
  CBC mode.
* Mon Oct  8 2007 anicka@suse.cz
- update to 2.24
  * Fixed failure to run under taint checks with Crypt::Rijndael
    or Crypt::OpenSSL::AES (and maybe other Crypt modules).
  * Added checks for other implementations of CBC which add no
    standard padding at all when cipher text is an even multiple
    of the block size.
* Tue Dec 12 2006 anicka@suse.cz
- update to 2.22
  * Fixed bug in which plaintext encrypted with the
  - literal_key option could not be decrypted using a new
  object created with the same -literal_key.
  * Added documentation confirming that -literal_key must be
  accompanied by a -header of 'none' and a manually specificied IV.
* Thu Oct 19 2006 anicka@suse.cz
- update to 2.21
  * Fixed bug in which new() failed to work when first option is
  - literal_key.
  * Added ability to pass a preinitialized Crypt::* block cipher
  object instead of the class name.
* Thu Sep 14 2006 anicka@suse.cz
- update to 2.19
  * Renamed Crypt::CBC-2.16-vulnerability.txt so that
    package installs correctly under Cygwin
* Fri Jul 14 2006 anicka@suse.cz
- update to 2.18
  * added lots of documentation
  * fixed using 8 byte IVs when generating the old-style RandomIV
    style header for the Rijndael algorithm.
  * versions 2.17 and higher will not decrypt messages
    encrypted with versions 2.16 and lower unless you pass
    an optional value 'randomiv' to the new() call
* Wed Apr  5 2006 schubi@suse.de
- Bug 153627 - VUL-0: perl-Crypt-CBC: ciphertext weakness when using certain block algorithms
* Wed Jan 25 2006 mls@suse.de
- converted neededforbuild to BuildRequires
* Mon Jul 11 2005 schubi@suse.de
- update to 2.14
* Fri Apr 15 2005 schubi@suse.de
- update to 2.12
* Sun Jan 11 2004 adrian@suse.de
- build as user
* Fri Aug 22 2003 mjancar@suse.cz
- require the perl version we build with
* Fri Jul 18 2003 choeger@suse.de
- use install_vendor and new %%perl_process_packlist macro
* Tue Jun 17 2003 choeger@suse.de
- updated filelist
- update to version 2.08
* Mon May 19 2003 choeger#@suse.de
- remove installed (but unpackaged) file perllocal.pod
* Wed Aug 14 2002 choeger@suse.de
- new package, version 2.07
