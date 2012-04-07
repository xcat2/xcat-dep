Name:           debootstrap
Version:        1.0.19
Release:        2%{?dist}
Summary:        Debian GNU/Linux bootstrapper

Group:          System Environment/Base
License:        MIT
URL:            http://code.erisian.com.au/Wiki/debootstrap
Source0:        http://ftp.debian.org/debian/pool/main/d/debootstrap/debootstrap_%{version}.tar.gz
Patch0:         debootstrap-1.0.19-devices.patch
Patch1:         debootstrap-1.0.19-perms.patch
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch

BuildRequires:  fakeroot, MAKEDEV
Requires:       gettext, wget, tar, gzip, binutils


%description
debootstrap is used to create a Debian base system from scratch, without
requiring the availability of dpkg or apt.  It does this by downloading
.deb files from a mirror site, and carefully unpacking them into a
directory which can eventually be chrooted into.

This might be often useful coupled with virtualization techniques to run
Debian GNU/Linux guest system.


%prep
%setup -q -n %{name}
%patch0 -p1 -b .devices
%patch1 -p1 -b .perms


%build
# in Makefile, path is hardcoded, modify it to take rpm macros into account
sed -i -e 's;/usr/sbin;%{_sbindir};' Makefile

# _smp_mflags would make no sense at all
fakeroot make


%install
rm -rf $RPM_BUILD_ROOT
install -d $RPM_BUILD_ROOT%{_datadir}/debootstrap/scripts/
install -d $RPM_BUILD_ROOT%{_sbindir}
install -d $RPM_BUILD_ROOT%{_mandir}/man8
install -p -m 0644 debootstrap.8 $RPM_BUILD_ROOT%{_mandir}/man8
make install DESTDIR=$RPM_BUILD_ROOT \
       VERSION="%{version}-%{release}" \
       DSDIR=$RPM_BUILD_ROOT%{_datadir}/debootstrap
# substitute the rpm macro path
sed -i -e 's;/usr/share;%{_datadir};' $RPM_BUILD_ROOT%{_sbindir}/debootstrap
# correct the debootstrap script timestamp
touch -r debootstrap  $RPM_BUILD_ROOT%{_sbindir}/debootstrap


%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%{_datadir}/debootstrap
%{_sbindir}/debootstrap
%{_mandir}/man8/debootstrap.8*
%doc debian/changelog debian/copyright debian/README.Debian


%changelog
* Wed Sep 30 2009 Adam Goode <adam@spicenitz.org> - 1.0.19-2
- Make sure to create /dev/console in devices.tar.gz

* Wed Sep 30 2009 Adam Goode <adam@spicenitz.org> - 1.0.19-1
- New upstream release
   + Many bugfixes
   + Support for new distributions
- Arch patch no longer needed
- Rebase other patches

* Fri Jul 24 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 1.0.10-3
- Rebuilt for https://fedoraproject.org/wiki/Fedora_12_Mass_Rebuild

* Tue Feb 24 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 1.0.10-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_11_Mass_Rebuild

* Tue Jul 15 2008 Lubomir Rintel <lkundrak@v3.sk> - 1.0.10-1
- New upstream version

* Sun Jun 15 2008 Adam Goode <adam@spicenitz.org> - 1.0.9-1
- 1.0.9

* Fri Feb 22 2008 Lubomir Kundrak <lkundrak@redhat.com> - 1.0.8-1
- 1.0.8

* Sun Nov 18 2007 Patrice Dumas <pertusus@free.fr> 1.0.7-2
- keep timestamps
- use rpm macros instead of hardcoded paths

* Sat Nov 17 2007 Lubomir Kundrak <lkundrak@redhat.com> 1.0.7-1
- Version bump

* Thu Nov 15 2007 Lubomir Kundrak <lkundrak@redhat.com> 1.0.3-2
- Some more fixes, thanks to Patrice Dumas (#329291)

* Fri Oct 12 2007 Lubomir Kundrak <lkundrak@redhat.com> 1.0.3-1
- Incorporating advises from Patrice Dumas (#329291) in account

* Fri Oct 12 2007 Lubomir Kundrak <lkundrak@redhat.com> 0.3.3.2etch1-1
- Initial package
