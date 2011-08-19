Name:           esxboot-xcat
Version:        1.0.0
Release:        1
Summary:        xCAT patched variant of vmware's boot loader

Group:          System Environment/Kernel
License:        GPL
URL:           http://www.vmware.com/download/open_source.html
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}
BuildArch:	noarch

%define Distribution %(rpm -q -qf /etc/redhat-release --qf '%%{name}' | cut -d"-"  -f 1)
%define os_version %(rpm -q --qf '%%{version}' %{Distribution}-release)
%define os_release %(rpm -q --qf '%%{release}' %{Distribution}-release | cut -d"." -f 1)


Source0: efiboot.tgz
Patch: esxboot-xcat.patch

%description
The xCAT Network Boot Agent is a slightly modified version of gPXE.  It provides enhanced boot features for any UNDI compliant x86 host.  This includes iSCSI, http/ftp downloads, and gPXE script based booting.

%prep

%setup   -n efiboot
%patch -p1

%build

rm -rf %{buildroot}

./configure
make -f Makefile.main BUILDENV=uefi64


%install

mkdir -p  %{buildroot}/tftpboot/xcat
cp build/uefi64/esxboot/esxboot_x64.efi  %{buildroot}/tftpboot/xcat/esxboot-x64.efi


%post 

%preun

%clean
%{__rm} -rf %{buildroot}

%files
/tftpboot/xcat/esxboot-x64.efi
%changelog
