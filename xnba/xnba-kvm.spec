Name:           xnba-kvm
Version:        1.0.2
Release:        4
Summary:        xNBA loader for virtual guests
Obsoletes:      etherboot-zroms-kvm
Provides:      etherboot-zroms-kvm
Obsoletes:     gpxe-roms-qemu
Provides:      gpxe-roms-qemu

Group:          System Environment/Kernel
License:        GPL
URL:            http://etherboot.org/wiki/index.php
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}
Obsoletes:      gpxe-kvm

ExclusiveArch:  i386 x86_64


%define Distribution %(rpm -q -qf /etc/redhat-release --qf '%%{name}' | cut -d"-"  -f 1)
%define os_version %(rpm -q --qf '%%{version}' %{Distribution}-release)
%define os_release %(rpm -q --qf '%%{release}' %{Distribution}-release | cut -d"." -f 1)


Source0: xnba-%{version}.tar.bz2

%description
The xNBA network bootloader provides network boot capability for virtual machines with e1000 and virtio network devices. This includes iSCSI and PXE with tftp or ftp image download capability.  It is a modified variant of iPXE

%prep

%setup  -n xnba-%{version}

%build

rm -rf %{buildroot}

cd src
make bin/8086100e.rom
make bin/virtio-net.rom
make bin/rtl8139.rom
make bin/pcnet32.rom
make bin/ne.rom
make bin/rtl8029.rom


%install

mkdir -p  %{buildroot}/usr/share/qemu/
mkdir -p  %{buildroot}/usr/share/gpxe
mkdir -p  %{buildroot}/usr/share/etherboot
cp src/bin/8086100e.rom %{buildroot}/usr/share/etherboot/e1000-82542.zrom
cp src/bin/pcnet32.rom %{buildroot}/usr/share/etherboot/pcnet32.zrom
cp src/bin/ne.rom %{buildroot}/usr/share/etherboot/ne.zrom
cp src/bin/rtl8139.rom %{buildroot}/usr/share/etherboot/rtl8139.zrom
cp src/bin/rtl8029.rom %{buildroot}/usr/share/etherboot/rtl8029.zrom
cp src/bin/virtio-net.rom %{buildroot}/usr/share/etherboot/virtio-net.zrom
ln -sf ../etherboot/e1000-82542.zrom %{buildroot}/usr/share/qemu/pxe-e1000.bin
ln -sf ../etherboot/virtio-net.zrom %{buildroot}/usr/share/qemu/pxe-virtio.bin
ln -sf ../etherboot/ne.zrom %{buildroot}/usr/share/qemu/pxe-ne2k_pci.bin
ln -sf ../etherboot/pcnet32.zrom %{buildroot}/usr/share/qemu/pxe-pcnet.bin
ln -sf ../etherboot/rtl8139.zrom %{buildroot}/usr/share/qemu/pxe-rtl8139.bin
ln -sf ../etherboot/e1000-82542.zrom %{buildroot}/usr/share/gpxe/e1000-0x100e.rom
ln -sf ../etherboot/virtio-net.zrom %{buildroot}/usr/share/gpxe/virtio-net.rom
ln -sf ../etherboot/pcnet32.zrom %{buildroot}/usr/share/gpxe/pcnet32.rom
ln -sf ../etherboot/rtl8139.zrom %{buildroot}/usr/share/gpxe/rtl8139.rom
ln -sf ../etherboot/rtl8029.zrom %{buildroot}/usr/share/gpxe/rtl8029.rom

%post 

%preun

%clean
%{__rm} -rf %{buildroot}

%files
/usr
%changelog
