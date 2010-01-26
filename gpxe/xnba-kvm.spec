Name:           xnba-kvm
Version:        0.9.9
Release:        1
Summary:        xNBA loader for virtual guests
Obsoletes:      etherboot-zroms-kvm
Provides:      etherboot-zroms-kvm

Group:          System Environment/Kernel
License:        GPL
URL:            http://etherboot.org/wiki/index.php
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}
Obsoletes:      gpxe-kvm

ExclusiveArch:  i386 x86_64


%define Distribution %(rpm -q -qf /etc/redhat-release --qf '%%{name}' | cut -d"-"  -f 1)
%define os_version %(rpm -q --qf '%%{version}' %{Distribution}-release)
%define os_release %(rpm -q --qf '%%{release}' %{Distribution}-release | cut -d"." -f 1)


Source0: gpxe-%{version}.tar.bz2
Patch0: gpxe-0.9.7-branding.patch
Patch1: gpxe-0.9.9-registeriscsionpxe.patch
Patch2: gpxe-0.9.9-config.patch
Patch3: gpxe-0.9.7-ignorepackets.patch
Patch4: gpxe-0.9.7-kvmworkaround.patch
Patch5: gpxe-0.9.7-hdboot.patch
Patch6: gpxe-0.9.7-xnbauserclass.patch
Patch7: gpxe-0.9.7-undinet.patch
Patch8: gpxe-0.9.9-acceptproxyoffer.patch
Patch9: gpxe-0.9.9-ignorecloseddevs.patch
Patch10: gpxe-0.9.9-ignorenonpxepxe.patch
Patch11: gpxe-0.9.9-saverestorepciregister.patch
Patch12: gpxe-0.9.9-tftpblockwrap.patch
Patch13: gpxe-0.9.9-int18boot.patch

%description
The xNBA network bootloader provides network boot capability for virtual machines with e1000 and virtio network devices. This includes iSCSI and PXE with tftp or ftp image download capability.  It is a modified variant of gPXE

%prep

%setup  -n gpxe-%{version}
%patch -p1
%patch1 -p1
%patch2 -p1
%patch3 -p1
%patch4 -p1
%patch5 -p1
%patch6 -p1
%patch7 -p1
%patch8 -p1
%patch9 -p1
%patch10 -p1
%patch11 -p1
%patch12 -p1
%patch13 -p1


%build

rm -rf %{buildroot}

cd src
make bin/e1000.rom
make bin/virtio-net.rom


%install

mkdir -p  %{buildroot}/usr/share/qemu/
mkdir -p  %{buildroot}/usr/share/etherboot
cp src/bin/e1000.rom %{buildroot}/usr/share/etherboot/e1000-82542.zrom
cp src/bin/virtio-net.rom %{buildroot}/usr/share/etherboot/virtio-net.zrom
ln -sf ../etherboot/e1000-82542.zrom %{buildroot}/usr/share/qemu/pxe-e1000.bin
ln -sf ../etherboot/virtio-net.zrom %{buildroot}/usr/share/qemu/pxe-virtio.bin

%post 

%preun

%clean
%{__rm} -rf %{buildroot}

%files
/usr
%changelog
