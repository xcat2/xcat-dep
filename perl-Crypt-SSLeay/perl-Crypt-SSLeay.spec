# Disable network tests by default
%bcond_with perl_Crypt_SSLeay_enables_network_test

Name:           perl-Crypt-SSLeay
Summary:        OpenSSL glue that provides LWP with HTTPS support
Version:        0.72
Release:        24%{?dist}
License:        Artistic 2.0
Source0:        https://cpan.metacpan.org/authors/id/N/NA/NANIS/Crypt-SSLeay-%{version}.tar.gz
# Adapt to OpenSSL 1.1.0, bug #1383756, CPAN RT#118343
Patch0:         Crypt-SSLeay-0.72-Do-not-use-SSLv2_client_method-with-OpenSSL-1.1.0.patch
Patch1:         Crypt-SSLeay-0.72-Fix-building-on-Perl-without-dot-in-INC.patch
URL:            https://metacpan.org/release/Crypt-SSLeay
BuildRequires:  coreutils
BuildRequires:  findutils
BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  openssl-devel
BuildRequires:  zlib-devel
BuildRequires:  perl-interpreter
BuildRequires:  perl-devel
BuildRequires:  perl-generators
BuildRequires:  perl(ExtUtils::CBuilder) >= 0.280205
BuildRequires:  perl(ExtUtils::MakeMaker)
# ExtUtils::MakeMaker::Coverage is useless
BuildRequires:  perl(Getopt::Long)
BuildRequires:  perl(Path::Class)
BuildRequires:  perl(strict)
BuildRequires:  perl(warnings)
BuildRequires:  pkgconf-pkg-config
# Run-time:
BuildRequires:  /etc/pki/tls/certs/ca-bundle.crt
BuildRequires:  perl(Carp)
# DynaLoader not needed if XSLoader is available
BuildRequires:  perl(Exporter)
BuildRequires:  perl(IO::Socket)
BuildRequires:  perl(MIME::Base64)
BuildRequires:  perl(Socket)
BuildRequires:  perl(vars)
BuildRequires:  perl(XSLoader)
# Tests:
BuildRequires:  perl(Test::More) >= 0.88
BuildRequires:  perl(Try::Tiny) >= 0.19
# Optional tests:
BuildRequires:  perl(Test::Pod)
BuildRequires:  perl(Test::Pod::Coverage)
%if %{with perl_Crypt_SSLeay_enables_network_test}
# Network tests:
BuildRequires:  perl(constant)
BuildRequires:  perl(HTTP::Request)
BuildRequires:  perl(LWP::Protocol::https) >= 6.02
BuildRequires:  perl(LWP::UserAgent)
%endif
Requires:       perl(:MODULE_COMPAT_%(eval "`perl -V:version`"; echo $version))
Requires:       /etc/pki/tls/certs/ca-bundle.crt
Requires:       perl(XSLoader)

%global __provides_exclude %{?__provides_exclude:__provides_exclude|}^perl\\(DB\\)
%{?perl_default_filter}

%description
These Perl modules provide support for the HTTPS protocol under the World-Wide
Web library for Perl (LWP), so that a LWP::UserAgent can make HTTPS GET, HEAD,
and POST requests.

This package contains Net::SSL module which is automatically loaded by
LWP::Protocol::https on HTTPS requests, and provides the necessary SSL glue
for that module to work.

%prep
%setup -q -n Crypt-SSLeay-%{version} 
%patch0 -p1
%patch1 -p1
# OpenSSL 3 removed SSLv3 symbols; force TLS method for the old SSLv3 code path.
sed -i 's/SSLv3_client_method()/TLS_client_method()/g' SSLeay.xs

# Placate rpmlint
chmod -c -x lib/Net/SSL.pm

%build
if pkg-config openssl ; then
  export INC="$CFLAGS `pkg-config --cflags-only-I openssl`"
  export LDFLAGS="$LDFLAGS `pkg-config --libs-only-L openssl`"
fi

perl Makefile.PL --%{!?with_perl_Crypt_SSLeay_enables_network_test:no-}live-tests \
    INC="$INC" LDFLAGS="$LDFLAGS" INSTALLDIRS=vendor NO_PACKLIST=1 \
    OPTIMIZE="%{optflags}" </dev/null
make %{?_smp_mflags}

%install
make pure_install DESTDIR=%{buildroot}
find %{buildroot} -type f -name '*.bs' -a -size 0 -delete
%{_fixperms} %{buildroot}
chmod -R u+w %{buildroot}/*
chmod -R 644 eg/*
chmod -R 644 certs/*
rm certs/ca-bundle.crt
ln -s /etc/pki/tls/certs/ca-bundle.crt certs/ca-bundle.crt

%check
make test

%files
%doc Changes eg/* certs/*
%{perl_vendorarch}/auto/Crypt/
%{perl_vendorarch}/Crypt/
%{perl_vendorarch}/Net/
%{_mandir}/man3/Crypt::SSLeay.3pm*
%{_mandir}/man3/Crypt::SSLeay::Version.3pm*
%{_mandir}/man3/Net::SSL.3pm*

%changelog
* Fri Jul 13 2018 Fedora Release Engineering <releng@fedoraproject.org> - 0.72-20
- Rebuilt for https://fedoraproject.org/wiki/Fedora_29_Mass_Rebuild

* Thu Jun 28 2018 Jitka Plesnikova <jplesnik@redhat.com> - 0.72-19
- Perl 5.28 rebuild

* Thu Feb 08 2018 Fedora Release Engineering <releng@fedoraproject.org> - 0.72-18
- Rebuilt for https://fedoraproject.org/wiki/Fedora_28_Mass_Rebuild

* Thu Aug 03 2017 Fedora Release Engineering <releng@fedoraproject.org> - 0.72-17
- Rebuilt for https://fedoraproject.org/wiki/Fedora_27_Binutils_Mass_Rebuild

* Thu Jul 27 2017 Fedora Release Engineering <releng@fedoraproject.org> - 0.72-16
- Rebuilt for https://fedoraproject.org/wiki/Fedora_27_Mass_Rebuild

* Wed Jun 07 2017 Jitka Plesnikova <jplesnik@redhat.com> - 0.72-15
- Perl 5.26 re-rebuild of bootstrapped packages

* Mon Jun 05 2017 Petr Pisar <ppisar@redhat.com> - 0.72-14
- Modernize spec file

* Mon Jun 05 2017 Jitka Plesnikova <jplesnik@redhat.com> - 0.72-13
- Perl 5.26 rebuild

* Tue May 16 2017 Jitka Plesnikova <jplesnik@redhat.com> - 0.72-12
- Fix building on Perl without '.' in @INC

* Sat Feb 11 2017 Fedora Release Engineering <releng@fedoraproject.org> - 0.72-11
- Rebuilt for https://fedoraproject.org/wiki/Fedora_26_Mass_Rebuild

* Wed Oct 12 2016 Petr Pisar <ppisar@redhat.com> - 0.72-10
- Adapt to OpenSSL 1.1.0 (bug #1383756)

* Sun May 15 2016 Jitka Plesnikova <jplesnik@redhat.com> - 0.72-9
- Perl 5.24 rebuild

* Thu Feb 04 2016 Fedora Release Engineering <releng@fedoraproject.org> - 0.72-8
- Rebuilt for https://fedoraproject.org/wiki/Fedora_24_Mass_Rebuild

* Thu Jun 18 2015 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.72-7
- Rebuilt for https://fedoraproject.org/wiki/Fedora_23_Mass_Rebuild

* Sat Jun 06 2015 Jitka Plesnikova <jplesnik@redhat.com> - 0.72-6
- Perl 5.22 rebuild

* Fri Aug 29 2014 Jitka Plesnikova <jplesnik@redhat.com> - 0.72-5
- Perl 5.20 rebuild

* Sun Aug 17 2014 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.72-4
- Rebuilt for https://fedoraproject.org/wiki/Fedora_21_22_Mass_Rebuild

* Sat Jun 07 2014 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.72-3
- Rebuilt for https://fedoraproject.org/wiki/Fedora_21_Mass_Rebuild

* Mon Apr 28 2014 Jitka Plesnikova <jplesnik@redhat.com> - 0.72-2
- Correct License tag, which should be Artistic 2.0

* Mon Apr 28 2014 Jitka Plesnikova <jplesnik@redhat.com> - 0.72-1
- 0.72 bump

* Wed Apr 16 2014 Petr Pisar <ppisar@redhat.com> - 0.64-6
- Make build script non-interactive
- Update package description
- Specify all dependencies

* Sat Aug 03 2013 Petr Pisar <ppisar@redhat.com> - 0.64-5
- Perl 5.18 rebuild

* Thu Feb 14 2013 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.64-4
- Rebuilt for https://fedoraproject.org/wiki/Fedora_19_Mass_Rebuild

* Wed Aug  8 2012 Paul Howarth <paul@city-fan.org> - 0.64-3
- Remove circular BR: perl(Net::SSL) provided by this package
- Placate rpmlint regarding file permissions
- Don't need to remove empty directories from the buildroot

* Tue Aug 07 2012 Petr Šabata <contyk@redhat.com> - 0.64-1
- 0.64 bump

* Mon Jul 30 2012 Petr Šabata <contyk@redhat.com> - 0.60-1
- 0.60 bugfix bump
- Drop command macros and modernize the spec a bit

* Fri Jul 20 2012 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.58-11
- Rebuilt for https://fedoraproject.org/wiki/Fedora_18_Mass_Rebuild

* Fri Jul 20 2012 Marcela Mašláňová <mmaslano@redhat.com> - 0.58-10
- Conditionalize ExtUtils::MakeMaker::Coverage

* Mon Jun 25 2012 Petr Pisar <ppisar@redhat.com> - 0.58-9
- Perl 5.16 rebuild

* Fri Jan 13 2012 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.58-8
- Rebuilt for https://fedoraproject.org/wiki/Fedora_17_Mass_Rebuild

* Wed Sep 07 2011 Petr Sabata <contyk@redhat.com> - 0.58-7
- Link to the ca-certificates ca-bundle.crt instead of shipping our own,
  outdated copy (#734385)

* Fri Jul 22 2011 Petr Pisar <ppisar@redhat.com> - 0.58-6
- RPM 4.9 dependency filtering added

* Wed Jul 20 2011 Petr Sabata <contyk@redhat.com> - 0.58-5
- Perl mass rebuild

* Tue Apr 19 2011 Paul Howarth <paul@city-fan.org> - 0.58-4
- Remove buildroot specification and cleaning, not needed for modern rpmbuild
- Use %%{?perl_default_filter}
- Filter the perl(DB) provide in a way that works with rpm >= 4.9
- Use DESTDIR rather than PERL_INSTALL_ROOT
- Fix line endings on documentation
- Fix upstream source URL
- Fix argument order for find with -depth

* Tue Feb 08 2011 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.58-3
- Rebuilt for https://fedoraproject.org/wiki/Fedora_15_Mass_Rebuild

* Thu Dec 16 2010 Marcela Maslanova <mmaslano@redhat.com> - 0.58-2
- Rebuild to fix problems with vendorarch/lib (#661697)

* Wed Sep  1 2010 Petr Sabata <psabata@redhat.com> - 0.58-1
- New upstream release, v0.58
- removing perl-Crypt-SSLeay-0.57-live-tests.patch, fixed in upstream
- removing perl-Crypt-SSLeay-Makefile_ssl1.patch, fixed in upstream

* Fri Apr 30 2010 Marcela Maslanova <mmaslano@redhat.com> - 0.57-17
- Mass rebuild with perl-5.12.0

* Mon Dec  7 2009 Stepan Kasal <skasal@redhat.com> - 0.57-16
- rebuild against perl 5.10.1

* Wed Nov 25 2009 Marcela Mašláňová <mmaslano@redhat.com> - 0.57-14
- change Makefile for openssl 1.0, which couldn't be found properly before

* Fri Aug 21 2009 Tomas Mraz <tmraz@redhat.com> - 0.57-13
- rebuilt with new openssl

* Sat Jul 25 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.57-12
- Rebuilt for https://fedoraproject.org/wiki/Fedora_12_Mass_Rebuild

* Thu Feb 26 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.57-11
- Rebuilt for https://fedoraproject.org/wiki/Fedora_11_Mass_Rebuild

* Sat Jan 17 2009 Tomas Mraz <tmraz@redhat.com> - 0.57-10
- rebuild with new openssl

* Mon Oct  6 2008 Marcela Maslanova <mmaslano@redhat.com> - 0.57-9
- add examples into doc

* Wed Sep 24 2008 Marcela Maslanova <mmaslano@redhat.com> - 0.57-8
- fix patches for fuzz

* Wed Mar  5 2008 Tom "spot" Callaway <tcallawa@redhat.com> - 0.57-7
- rebuild for new perl

* Tue Feb 19 2008 Fedora Release Engineering <rel-eng@fedoraproject.org> - 0.57-6
- Autorebuild for GCC 4.3

* Wed Dec 05 2007 Release Engineering <rel-eng at fedoraproject dot org> - 0.57-5
- Rebuild for deps

* Wed Dec  5 2007 Robin Norwood <rnorwood@redhat.com> - 0.57-4
- Rebuild for new openssl

* Sat Oct 27 2007 Robin Norwood <rnorwood@redhat.com> - 0.57-3
- Remove unnecessary BR: pkgconfig

* Fri Oct 26 2007 Robin Norwood <rnorwood@redhat.com> - 0.57-2
- Fix buildroot per package review
- Resolves: bz#226248

* Thu Oct 25 2007 Robin Norwood <rnorwood@redhat.com> - 0.57-1
- Update to latest upstream version.
- Remove old patch (patch applied to upstream)
- Several fixes for package review:
- Fixed BuildRequires (added Test::Pod and LWP::UserAgent)
- Apply patch to avoid prompting for input when building Makefile
- Fix defattr line
- Resolves: bz#226248

* Mon Aug 27 2007 Robin Norwood <rnorwood@redhat.com> - 0.56-2
- perl(ExtUtils::MakeMaker::Coverage) is now available

* Mon Aug 13 2007 Robin Norwood <rnorwood@redhat.com> - 0.56-1
- 0.56 is the latest CPAN version, not 0.55

* Mon Aug 13 2007 Robin Norwood <rnorwood@redhat.com> - 0.55-2
- Update to latest version from CPAN: 0.55
- Remove two old patches, update lib64 patch for Makefile.PL changes.

* Tue Feb 13 2007 Robin Norwood <rnorwood@redhat.com> - 0.53-1
- New version: 0.53

* Mon Nov 27 2006 Robin Norwood <rnorwood@redhat.com> - 0.51-12
- Resolves: bug#217138
- fix a segfault on x86_64

* Tue Oct 17 2006 Robin Norwood <rnorwood@redhat.com> - 0.51-10
- Filter out Provides perl(DB)
- bug #205562

* Wed Jul 12 2006 Jesse Keating <jkeating@redhat.com> - 0.51-9.2.2.1
- rebuild

* Fri Feb 10 2006 Jesse Keating <jkeating@redhat.com> - 0.51-9.2.2
- bump again for double-long bug on ppc(64)

* Tue Feb 07 2006 Jesse Keating <jkeating@redhat.com> - 0.51-9.2.1
- rebuilt for new gcc4.1 snapshot and glibc changes

* Fri Feb 03 2006 Jason Vas Dias <jvdias@redhat.com> - 0.51-9.2
- rebuild for new perl-5.8.8 / gcc / glibc

* Fri Dec 16 2005 Jesse Keating <jkeating@redhat.com>
- rebuilt for new gcc

* Fri Dec 16 2005 Jesse Keating <jkeating@redhat.com>
- rebuilt for new gcj

* Thu Nov 10 2005 Tomas Mraz <tmraz@redhat.com> 0.51-9
- rebuilt against new openssl
- added missing SSL_library_init()

* Sat Sep 24 2005 Ville Skyttä <ville.skytta at iki.fi> 0.51-8
- Own more installed dirs (#73908).
- Enable rpmbuild's internal dependency generator, drop unneeded dependencies.
- Require perl(:MODULE_COMPAT_*).
- Run tests in the %%check section.
- Fix License, Source0, URL, and Group tags.

* Wed Mar 30 2005 Warren Togami <wtogami@redhat.com> 0.51-7
- remove brp-compress

* Tue Mar  8 2005 Joe Orton <jorton@redhat.com> 0.51-6
- rebuild

* Tue Aug 31 2004 Chip Turner <cturner@redhat.com> 0.51-5
- build for FC3

* Tue Aug 31 2004 Chip Turner <cturner@redhat.com> 0.51-4
- build for RHEL3 U4

* Tue Jun 15 2004 Elliot Lee <sopwith@redhat.com>
- rebuilt

* Tue Mar 02 2004 Elliot Lee <sopwith@redhat.com>
- rebuilt

* Fri Feb 13 2004 Chip Turner <cturner@redhat.com> 0.51-1
- update to upstream 0.51

* Thu Jun 05 2003 Elliot Lee <sopwith@redhat.com>
- rebuilt

* Tue Jan  7 2003 Nalin Dahyabhai <nalin@redhat.com>
- pass openssl includes to make as INC and ldflags in as LDFLAGS

* Thu Nov 21 2002 Chip Turner <cturner@redhat.com>
- patch to support /usr/lib64 before /usr/lib

* Wed Nov 20 2002 Chip Turner <cturner@redhat.com>
- rebuild

* Tue Aug  6 2002 Chip Turner <cturner@redhat.com>
- automated release bump and build

* Thu Jun 27 2002 Chip Turner <cturner@redhat.com>
- description update

* Tue Jun 25 2002 Chip Turner <cturner@redhat.com>
- move to 0.39

* Wed Jan 09 2002 Tim Powers <timp@redhat.com>
- automated rebuild

* Fri Dec 7 2001 root <root@redhat.com>
- Spec file was autogenerated. 
