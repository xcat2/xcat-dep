Name:           gpxe-undi
Version:        0.9.7
Release:        1
Summary:        gPXE loader for PXE clients

Group:          System Environment/Kernel
License:        GPL
URL:            http://etherboot.org/wiki/index.php
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}
BuildArch:	noarch

%define Distribution %(rpm -q -qf /etc/redhat-release --qf '%%{name}' | cut -d"-"  -f 1)
%define os_version %(rpm -q --qf '%%{version}' %{Distribution}-release)
%define os_release %(rpm -q --qf '%%{release}' %{Distribution}-release | cut -d"." -f 1)


Source0: gpxe-0.9.7.tar.gz
Patch0: gpxe-0.9.7-kvmworkaround.patch
Patch1: gpxe-0.9.7-registeriscsionpxe.patch
Patch2: gpxe-0.9.7-strip.patch

%description
The gPXE network bootloader provides enhanced boot features for any UNDI compliant x86 host.  This includes iSCSI, ftp downloads, and gPXE script based booting.

%prep

%setup  -n gpxe-%{version}
%patch -p1
%patch1 -p1
%patch2 -p1

%build

rm -rf %{buildroot}

cd src
make bin/undionly.kpxe


%install

mkdir -p  %{buildroot}/tftpboot/
cp src/bin/undionly.kpxe %{buildroot}/tftpboot/undionly.kpxe


%post 

%preun

%clean
%{__rm} -rf %{buildroot}

%files
/tftpboot/undionly.kpxe
%changelog
