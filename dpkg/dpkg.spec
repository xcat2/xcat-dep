Name:           dpkg
Version:        1.15.5.6
Release:        6%{?dist}
Summary:        Package maintenance system for Debian Linux
Group:          System Environment/Base
# The entire source code is GPLv2+ with exception of the following
# lib/dpkg/md5.c, lib/dpkg/md5.h - Public domain
# lib/dpkg/showpkg.c, dselect/methods/multicd, lib/dpkg/utils.c, lib/dpkg/showpkg.c - GPLv2
# dselect/methods/ftp - GPL no version info
# scripts/Dpkg/Gettext.pm - BSD
# lib/compat/obstack.h, lib/compat/gettext.h,lib/compat/obstack.c - LGPLv2+
License:        GPLv2 and GPLv2+ and LGPLv2+ and Public Domain and BSD
URL:            http://packages.debian.org/unstable/admin/dpkg
Source0:        http://ftp.debian.org/debian/pool/main/d/dpkg/%{name}_%{version}.tar.bz2
# obtained from dpkg-source -x dpkg_1.15.5.6.dsc
Source1:        dpkg.archtable
# Fedora specific patch to store files under /usr/share/dpkg, not these are not binary
# libs. and set user search path to /usr/local/share/dpkg
Patch1:         dpkg-change-libdir-path.patch
# Fixes CVE-2010-0396 bugzilla #572522
Patch2:		fedora-fix-CVE-2010-0396-00.patch
Patch3:		fedora-fix-CVE-2010-0396-01.patch
Patch4:     fedora-bug642160-empty-argv.patch
Patch5:		fedora-fix-CVE-2010-1679_CVE-2011-0402.patch
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildRequires:  zlib-devel, bzip2-devel, libselinux-devel, gettext, ncurses-devel

%description 

This package contains the tools (including dpkg-source) required 
to unpack, build and upload Debian source packages.

This package also contains the programs dpkg which used to handle the 
installation and removal of packages on a Debian system.

This package also contains dselect, an interface for managing the 
installation and removal of packages on the system.

dpkg and dselect will certainly be non-functional on a rpm-based system
because packages dependencies will likely be unmet.

%package devel
Summary:  Debian package development tools
Group:    Development/System
Requires: %{name} = %{version}-%{release}
Requires: perl, patch, make, binutils, bzip2, lzma
BuildArch: noarch

%description devel
This package provides the development tools (including dpkg-source).
Required to unpack, build and upload Debian source packages


%package -n dselect
Summary:  Debian package management front-end
Group:    System Environment/Base
Requires: %{name} = %{version}-%{release}

%description -n dselect
dselect is a high-level interface for the installation/removal of debs . 

%prep
%setup -q

%patch1 -p1
%patch2 -p1
%patch3 -p1
%patch4 -p1
%patch5 -p1

# Filter unwanted Requires:
cat << \EOF > %{name}-req
#!/bin/sh
%{__perl_requires} $* |\
  sed -e '/perl(Dselect::Ftp)/d' -e '/perl(extra)/d' -e '/perl(file)/d' -e '/perl(dpkg-gettext.pl)/d' -e '/perl(controllib.pl)/d' -e '/perl(in)/d'
EOF

%define __perl_requires %{_builddir}/%{name}-%{version}/%{name}-req
chmod +x %{__perl_requires}

%build
%configure --without-start-stop-daemon \
        --disable-linker-optimisations \
        --with-admindir=%{_localstatedir}/lib/dpkg \
        --libdir=%{_datadir} \
        --with-selinux \
        --with-zlib \
        --with-bz2 \
        --disable-silent-rules

make %{?_smp_mflags}


%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT
install -pm0644 %SOURCE1 $RPM_BUILD_ROOT/%{_datadir}/dpkg/archtable

%find_lang dpkg
%find_lang dpkg-dev
%find_lang dselect

# fedora has its own implementation
rm -rf $RPM_BUILD_ROOT%{_bindir}/update-alternatives
rm -rf $RPM_BUILD_ROOT%{_sysconfdir}/alternatives/

%clean
rm -rf $RPM_BUILD_ROOT


%files   -f dpkg.lang
%defattr(-,root,root,-)
%doc debian/changelog README AUTHORS COPYING THANKS TODO
%dir %{_sysconfdir}/dpkg
%{_bindir}/dpkg
%{_bindir}/dpkg-deb
%{_bindir}/dpkg-query
%{_bindir}/dpkg-split
%{_bindir}/dpkg-trigger
%{_bindir}/dpkg-divert
%{_bindir}/dpkg-statoverride
%{_sbindir}/*
%dir %{_datadir}/dpkg
%{_datadir}/dpkg/mksplit
%{_datadir}/dpkg/archtable
%{_datadir}/dpkg/cputable
%{_datadir}/dpkg/ostable
%{_datadir}/dpkg/triplettable
%{perl_vendorlib}/Dpkg.pm
%dir %{perl_vendorlib}/Dpkg
%{perl_vendorlib}/Dpkg/Gettext.pm
%{_mandir}/man1/dpkg-deb.1.gz
%{_mandir}/man1/dpkg-query.1.gz
%{_mandir}/man1/dpkg-split.1.gz
%{_mandir}/man1/dpkg-trigger.1.gz
%{_mandir}/man1/dpkg.1.gz
%{_mandir}/man5/dpkg.cfg.5.gz
%{_mandir}/man8/dpkg-divert.8.gz
%{_mandir}/man8/dpkg-statoverride.8.gz
#fedora has own implemenation
%exclude %{_sbindir}/install-info
#fedora has own implemenation
%exclude %{_mandir}/man8/update-alternatives.8.gz

%files  devel -f dpkg-dev.lang
%defattr(-,root,root,-)
%doc doc/README.api
%{_bindir}/dpkg-architecture
%{_bindir}/dpkg-buildpackage
%{_bindir}/dpkg-checkbuilddeps
%{_bindir}/dpkg-distaddfile
%{_bindir}/dpkg-genchanges
%{_bindir}/dpkg-gencontrol
%{_bindir}/dpkg-gensymbols
%{_bindir}/dpkg-name
%{_bindir}/dpkg-parsechangelog
%{_bindir}/dpkg-scanpackages
%{_bindir}/dpkg-scansources
%{_bindir}/dpkg-shlibdeps
%{_bindir}/dpkg-source
%{_bindir}/dpkg-vendor
%dir %{_datadir}/dpkg/parsechangelog
%{_datadir}/dpkg/parsechangelog/*
%exclude %{perl_vendorlib}/Dpkg/Gettext.pm
%{perl_vendorlib}/Dpkg/*.pm
%{perl_vendorlib}/Dpkg/Changelog
%{perl_vendorlib}/Dpkg/Shlibs
%{perl_vendorlib}/Dpkg/Source
%{perl_vendorlib}/Dpkg/Vendor
%{perl_vendorlib}/Dpkg/Control
%{_mandir}/man1/dpkg-architecture.1.gz
%{_mandir}/man1/dpkg-buildpackage.1.gz
%{_mandir}/man1/dpkg-checkbuilddeps.1.gz
%{_mandir}/man1/dpkg-distaddfile.1.gz
%{_mandir}/man1/dpkg-genchanges.1.gz
%{_mandir}/man1/dpkg-gencontrol.1.gz
%{_mandir}/man1/dpkg-gensymbols.1.gz
%{_mandir}/man1/dpkg-name.1.gz
%{_mandir}/man1/dpkg-parsechangelog.1.gz
%{_mandir}/man1/dpkg-scanpackages.1.gz
%{_mandir}/man1/dpkg-scansources.1.gz
%{_mandir}/man1/dpkg-shlibdeps.1.gz
%{_mandir}/man1/dpkg-source.1.gz
%{_mandir}/man1/dpkg-vendor.1.gz
%{_mandir}/man5/deb-control.5.gz
%{_mandir}/man5/deb-old.5.gz
%{_mandir}/man5/deb-override.5.gz
%{_mandir}/man5/deb-extra-override.5.gz
%{_mandir}/man5/deb-shlibs.5.gz
%{_mandir}/man5/deb-substvars.5.gz
%{_mandir}/man5/deb-symbols.5.gz
%{_mandir}/man5/deb-triggers.5.gz
%{_mandir}/man5/deb-version.5.gz
%{_mandir}/man5/deb.5.gz


%files -n dselect -f dselect.lang
%defattr(-,root,root,-)
%doc dselect/methods/multicd/README.multicd dselect/methods/ftp/README.mirrors.txt
%{_bindir}/dselect
%{perl_vendorlib}/Debian
%{_datadir}/dpkg/methods
%{_mandir}/man*/dselect*.gz



%changelog
* Wed Jan 12 2011 Andrew Colin Kissa <andrew@topdog.za.net> - 1.15.5.6-6
- Fix CVE-2010-1679
- Fix CVE-2011-0402

* Sun Oct 17 2010 Jeroen van Meeuwen <kanarip@kanarip.com> - 1.15.5.6-5
- Apply minimal fix for rhbz #642160

* Thu Mar 11 2010 Andrew Colin Kissa <andrew@topdog.za.net> - 1.15.5.6-4
- Fix CVE-2010-0396

* Mon Feb 15 2010 Andrew Colin Kissa <andrew@topdog.za.net> - 1.15.5.6-3
- review changes

* Sun Feb 14 2010 Andrew Colin Kissa <andrew@topdog.za.net> - 1.15.5.6-2
- review changes

* Sat Feb 13 2010 Andrew Colin Kissa <andrew@topdog.za.net> - 1.15.5.6-1
- Upgrade to latest upstream
- review changes

* Tue Nov 10 2009 Andrew Colin Kissa <andrew@topdog.za.net> - 1.15.4.1-1
- Upgrade to latest upstream
- review changes

* Tue Dec 30 2008 Leigh Scott <leigh123linux@googlemail.com> - 1.14.23-3
- more review changes               

* Mon Dec 15 2008 Leigh Scott <leigh123linux@googlemail.com> - 1.14.23-1
- bump version and make some of the review changes

* Tue Aug 19 2008 Leigh Scott <leigh123linux@googlemail.com> - 1.14.20-5
- made changes for review 

* Thu Jul 31 2008 Leigh Scott <leigh123linux@googlemail.com> - 1.14.20-4
- Change release to -4 as server refused -3

* Thu Jul 31 2008 Leigh Scott <leigh123linux@googlemail.com> - 1.14.20-3
- split the package into dkpg, dpkg-dev & dselect

* Tue Jul 29 2008 Leigh Scott <leigh123linux@googlemail.com> - 1.14.20-2
- recode man files to UTF8

* Tue Jul 29 2008 Leigh Scott <leigh123linux@googlemail.com> - 1.14.20-1
- Rebuild ans add build requires ncurses-devel

* Thu Jul 19 2007 Patrice Dumas <pertusus@free.fr> - 1.14.5-1
- initial packaging
