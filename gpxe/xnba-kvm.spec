Name:           xnba-kvm
Version:        0.9.7
Release:        11
Summary:        gPXE loader for virtual guests

Group:          System Environment/Kernel
License:        GPL
URL:            http://etherboot.org/wiki/index.php
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}
Obsoletes:      gpxe-kvm

ExclusiveArch:  i386 x86_64


%define Distribution %(rpm -q -qf /etc/redhat-release --qf '%%{name}' | cut -d"-"  -f 1)
%define os_version %(rpm -q --qf '%%{version}' %{Distribution}-release)
%define os_release %(rpm -q --qf '%%{release}' %{Distribution}-release | cut -d"." -f 1)


Source0: gpxe-0.9.7.tar.gz
Patch0: gpxe-0.9.7-branding.patch
Patch1: gpxe-0.9.7-registeriscsionpxe.patch
Patch2: gpxe-0.9.7-config.patch
Patch3: gpxe-0.9.7-ignorepackets.patch
Patch4: gpxe-0.9.7-kvmworkaround.patch
Patch5: gpxe-0.9.7-hdboot.patch
Patch6: gpxe-0.9.7-xnbauserclass.patch

%description
The gPXE network bootloader provides network boot capability for virtual machines with e1000 and virtio network devices. This includes iSCSI and PXE with tftp or ftp image download capability.

%prep

%setup  -n gpxe-%{version}
%patch -p1
%patch1 -p1
%patch2 -p1
%patch3 -p1
%patch4 -p1
%patch5 -p1
%patch6 -p1

%build

rm -rf %{buildroot}

cd src
make bin/e1000.rom
make bin/virtio-net.rom


%install

mkdir -p  %{buildroot}/usr/share/qemu/
cp src/bin/e1000.rom %{buildroot}/usr/share/qemu/pxe-e1000.bin
cp src/bin/virtio-net.rom %{buildroot}/usr/share/qemu/pxe-virtio.bin


%post 

%preun

%clean
%{__rm} -rf %{buildroot}

%files
/usr
%changelog
