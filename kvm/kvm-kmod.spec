%define kmod_name kvm

%{!?kverrel:%define kverrel %(rpm -q kernel-devel --qf '%{RPMTAG_VERSION}-%{RPMTAG_RELEASE}' | tail -1)}

%define kversion %(echo "%{kverrel}" | sed -e 's|-.*||')
%define krelease %(echo "%{kverrel}" | sed -e 's|.*-||')


Name:           kvm-kmod
Version:        84
Release:        2_%{kversion}_%{krelease}
Summary:        %{kmod_name} kernel module

Group:          System Environment/Kernel
License:        GPL
URL:            http://www.qumranet.com
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}
Source:		kvm.tar.gz
Patch:		kvm-kmod-makefix.patch

ExclusiveArch: i386 x86_64 ia64

%description
This kernel module provides support for virtual machines using hardware support
(Intel VT-x&VT-i or AMD SVM).

%prep
%setup -q  -n kvm-84
%patch -p1

%build

rm -rf %{buildroot}
./configure --disable-sdl --disable-gfx-check

make -C kernel 

%install
make -C kernel install DESTDIR=%{buildroot}

%define moddir /lib/modules/%{kverrel}/extra
chmod u+x %{buildroot}/%{moddir}/%{kmod_name}*.ko

%post 

depmod %{kverrel}

%postun

depmod %{kverrel}

%clean
%{__rm} -rf %{buildroot}

%files
%{moddir}/%{kmod_name}.ko
%ifarch i386 x86_64
%{moddir}/%{kmod_name}-amd.ko
%endif
%{moddir}/%{kmod_name}-intel.ko


%changelog
