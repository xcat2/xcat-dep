Name: gpxe-xcat
Summary: gPXE - UNDI package
Group: System Environment/Daemons
Version: 0.9.5
Release: 1
License: GPL
BuildRoot: %{_tmppath}/%{pkg}-buildroot
BuildArch: noarch
Source: gpxe-0.9.5.tar.bz2
Patch: register-iscsi-on-tftp.patch
Packager: Jarrod Johnson <jbj-xd@ura.dnsalias.org>

%description
A network bootloader supporting several different protocols.  xCAT uses it to provide RFC4173 capability for any PXE compliant x86 system.


%prep
%setup -n gpxe-0.9.5
%patch -p1

%build
make -C src bin/undionly.kpxe


%install
[ -n "$RPM_BUILD_ROOT" -a "$RPM_BUILD_ROOT" != '/' ] && rm -rf $RPM_BUILD_ROOT
mkdir -p "$RPM_BUILD_ROOT"/tftpboot
cp src/bin/undionly.kpxe "$RPM_BUILD_ROOT"/tftpboot/


%files
/tftpboot/undionly.kpxe


%clean


%changelog
* Sat Nov 01 2008 Jarrod Johnson <jbj-xd@ura.dnsalias.org>
- Initial packaging
