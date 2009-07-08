Name:           qemu-kvm
Version:        0.10.5
Release:        2
Summary:        Kernel Virtual Machine virtualization environment

Group:          System Environment/Kernel
License:        GPL
URL:            http://www.qumranet.com
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}

ExclusiveArch:  i386 x86_64 ia64

Requires:	kvm-kmod bridge-utils

%define Distribution %(rpm -q -qf /etc/redhat-release --qf '%%{name}' | cut -d"-"  -f 1)

BuildRequires:  zlib-devel

Source0: qemu-kvm-0.10.5.tar.gz
Patch: qemu-option-rom-expansion.patch
Patch1: qemu-kvm-0.10.5-flush-aio-on-migration.patch

%description
The Kernel Virtual Machine provides a virtualization enviroment for processors
with hardware support for virtualization: Intel's VT-x&VT-i and AMD's AMD-V.

%prep

%setup 
%patch -p1
%patch1 -p1

%build
rm -rf %{buildroot}

./configure --prefix=/usr --disable-sdl --disable-gfx-check
make
%ifarch i386 x86_64
make -C kvm/extboot
%endif

%install

make DESTDIR=%{buildroot} install
cp kvm/extboot/extboot.bin %{buildroot}/usr/share/qemu/
ln -sf qemu-system-x86_64 %{buildroot}/usr/bin/kvm
rm %{buildroot}/usr/share/qemu/pxe-e1000.bin

%define bindir /usr/bin
%define bin %{bindir}/kvm
%define initdir /etc/init.d
%define confdir /etc/kvm
%define utilsdir /etc/kvm/utils

%post 
#/sbin/chkconfig --add kvm
#/sbin/chkconfig --level 2345 kvm on
#/sbin/chkconfig --level 16 kvm off
/usr/sbin/groupadd -fg 444 kvm

%preun
if [ "$1" != 0 ]; then
	/sbin/service kvm stop
	/sbin/chkconfig --level 2345 kvm off
	/sbin/chkconfig --del kvm
fi

%clean
%{__rm} -rf %{buildroot}

%files
/usr/bin/kvm
/usr
%changelog
