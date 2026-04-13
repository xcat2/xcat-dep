Name:           elilo-xcat
Version:        3.14
Release:        6
Summary:        xCAT patched variant of elilo

Group:          System Environment/Kernel
License:        GPL
URL:           http://sourceforge.net/projects/elilo
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}
BuildArch:	noarch

%define Distribution %(rpm -q -qf /etc/redhat-release --qf '%%{name}' | cut -d"-"  -f 1)
%define os_version %(rpm -q --qf '%%{version}' %{Distribution}-release)
%define os_release %(rpm -q --qf '%%{release}' %{Distribution}-release | cut -d"." -f 1)


Source0: elilo-3.14-source.tar.gz
Patch1: elilo-xcat.patch
Patch2: elilo-big-bzimage-limit.patch
Patch3: elilo-gnu-efi-strncpy-conflict.patch
Source4: elilo-xcat-3.14-6.noarch.rpm
BuildRequires: gcc
BuildRequires: make
BuildRequires: cpio
%if "%{_host_cpu}" != "ppc64le"
BuildRequires: gnu-efi
BuildRequires: gnu-efi-devel
%endif

%description
elilo with patches from the xCAT team.  Most significantly, adds iPXE usage to the network support

%prep

%setup   -n elilo
%patch1  -p1
%patch2  -p1
%patch3  -p1
# EL10 keeps the relevant gnu-efi linker inputs under /usr/lib.
# On EL9, crt objects and linker scripts are still under /usr/lib, but the
# linkable static archives must be searched from /usr/lib64.
%if 0%{?rhel} >= 10
sed -i 's|^GNUEFILIB[[:space:]]*=.*|GNUEFILIB  = /usr/lib|' Make.defaults
sed -i 's|^EFILIB[[:space:]]*=.*|EFILIB   = /usr/lib|' Make.defaults
sed -i 's|^EFICRT0[[:space:]]*=.*|EFICRT0   = /usr/lib|' Make.defaults
%else
sed -i 's|^GNUEFILIB[[:space:]]*=.*|GNUEFILIB  = /usr/lib64|' Make.defaults
sed -i 's|^EFILIB[[:space:]]*=.*|EFILIB   = /usr/lib64|' Make.defaults
sed -i 's|^EFICRT0[[:space:]]*=.*|EFICRT0   = /usr/lib|' Make.defaults
%endif
%if "%{_host_cpu}" == "ppc64le"
# On ppc64le, reuse the prebuilt EFI payload from the tracked noarch package.
mkdir -p prebuilt
rpm2cpio %{SOURCE4} | (cd prebuilt && cpio -idm --quiet)
test -f prebuilt/tftpboot/xcat/elilo-x64.efi
%endif

%build

rm -rf %{buildroot}

%if "%{_host_cpu}" != "ppc64le"
make
%endif


%install

mkdir -p  %{buildroot}/tftpboot/xcat
%if "%{_host_cpu}" == "ppc64le"
cp prebuilt/tftpboot/xcat/elilo-x64.efi %{buildroot}/tftpboot/xcat/elilo-x64.efi
%else
cp elilo.efi %{buildroot}/tftpboot/xcat/elilo-x64.efi
%endif


%post 

%preun

%clean
%{__rm} -rf %{buildroot}

%files
/tftpboot/xcat/elilo-x64.efi
%changelog
