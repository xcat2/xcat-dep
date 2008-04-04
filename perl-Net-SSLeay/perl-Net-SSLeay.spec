#
# Rebuild switch:
#  --with testsuite          enable test suite
#

Name:           perl-Net-SSLeay
Version:        1.30
Release:        4%{?dist}
Summary:        Perl extension for using OpenSSL

Group:          Development/Libraries
License:        BSDish
URL:            http://search.cpan.org/dist/Net_SSLeay.pm/
Source0:        http://www.cpan.org/authors/id/F/FL/FLORA/Net_SSLeay.pm-%{version}.tar.gz
Patch0:         %{name}-test14.patch
Patch1:         perl-Net-SSLeay-1.2.5-CVE-2005-0106.patch
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

BuildRequires:  perl
BuildRequires:  openssl-devel
Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))

%description
This module offers some high level convinience functions for accessing
web pages on SSL servers (for symmetry, same API is offered for
accessing http servers, too), a sslcat() function for writing your own
clients, and finally access to the SSL api of SSLeay/OpenSSL package
so you can write servers or clients for more complicated applications.


%prep
%setup -q -n Net_SSLeay.pm-%{version}
%patch0 -p0
%patch1 -p1
cp -p Net-SSLeay-Handle-*/Changes Changes.Net-SSLeay-Handle
chmod -c 644 examples/*
%{__perl} -pi -e 's|/usr/local/bin/perl|%{__perl}|' examples/*.pl
iconv -f iso-8859-1 -t utf-8 SSLeay.pm > SSLeay.pm.utf8
mv SSLeay.pm.utf8 SSLeay.pm


%build
%{__perl} Makefile.PL -- INSTALLDIRS=vendor OPTIMIZE="$RPM_OPT_FLAGS"
make %{?_smp_mflags}


%install
rm -rf $RPM_BUILD_ROOT
make pure_install PERL_INSTALL_ROOT=$RPM_BUILD_ROOT
find $RPM_BUILD_ROOT -type f -name .packlist -exec rm -f {} ';'
find $RPM_BUILD_ROOT -type f -name '*.bs' -a -size 0 -exec rm -f {} ';'
rm -f $RPM_BUILD_ROOT%{perl_vendorarch}/Net/ptrtstrun.pl
find $RPM_BUILD_ROOT -type d -depth -exec rmdir {} 2>/dev/null ';'
chmod -R u+w $RPM_BUILD_ROOT/*


%check
# spawns servers, contacts external sites...
%{?_with_testsuite:make test}


%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%doc Changes* Credits QuickRef README examples/
%{perl_vendorarch}/auto/Net/
%{perl_vendorarch}/Net/
%{_mandir}/man3/Net::SSLeay*.3*


%changelog
* Fri Jul 14 2006 Warren Togami <wtogami@redhat.com> - 1.30-4
- import into FC6

* Tue Feb 28 2006 Jose Pedro Oliveira <jpo at di.uminho.pt> - 1.30-3
- Rebuild for FC5 (perl 5.8.8).

* Fri Jan 27 2006 Jose Pedro Oliveira <jpo at di.uminho.pt> - 1.30-2
- CVE-2005-0106: patch from Mandriva
  http://wwwnew.mandriva.com/security/advisories?name=MDKSA-2006:023

* Sun Jan 15 2006 Ville Skyttä <ville.skytta at iki.fi> - 1.30-1
- 1.30.
- Optionally run the test suite during build with "--with tests".

* Wed Nov  9 2005 Ville Skyttä <ville.skytta at iki.fi> - 1.26-3
- Rebuild for new OpenSSL.
- Cosmetic cleanups.

* Fri Apr  7 2005 Michael Schwendt <mschwendt[AT]users.sf.net> - 1.26-2
- rebuilt

* Mon Dec 20 2004 Ville Skyttä <ville.skytta at iki.fi> - 0:1.26-1
- Drop fedora.us release prefix and suffix.

* Mon Oct 25 2004 Ville Skyttä <ville.skytta at iki.fi> - 0:1.26-0.fdr.2
- Convert manual page to UTF-8.

* Tue Oct 12 2004 Ville Skyttä <ville.skytta at iki.fi> - 0:1.26-0.fdr.1
- Update to unofficial 1.26 from Peter Behroozi, adds get1_session(),
  enables session caching with IO::Socket::SSL (bug 1859, bug 1860).
- Bring outdated test14 up to date (bug 1859, test suite still not enabled).

* Sun Jul 11 2004 Ville Skyttä <ville.skytta at iki.fi> - 0:1.25-0.fdr.4
- Rename to perl-Net-SSLeay, provide perl-Net_SSLeay for compatibility
  with the rest of the world.

* Wed Jul  7 2004 Ville Skyttä <ville.skytta at iki.fi> - 0:1.25-0.fdr.3
- Bring up to date with current fedora.us Perl spec template.
- Include examples in docs.

* Sun Feb  8 2004 Ville Skyttä <ville.skytta at iki.fi> - 0:1.25-0.fdr.2
- Reduce directory ownership bloat.

* Fri Oct 17 2003 Ville Skyttä <ville.skytta at iki.fi> - 0:1.25-0.fdr.1
- First build.
