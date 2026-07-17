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
# Ship the tracked prebuilt EFI payload (SOURCE4) instead of compiling on targets where the
# gnu-efi toolchain layout does not support elilo's build: ppc64le (no x86 EFI toolchain) and
# EL8 (gnu-efi-devel places elf_x86_64_efi.lds under a path elilo's Makefile does not find).
# elilo-x64.efi is a noarch artifact, so the prebuilt is byte-identical to the compiled one.
# Use the tracked prebuilt on ppc (no x86 EFI toolchain) and on EL8 (gnu-efi lds path gap).
# Three SEPARATE %if blocks, each a single simple compare -- NOT one `A || B` expression (the
# older rpm in the EL8/EL9 mock chroot mis-evaluates `||`), and NOT %ifarch (during `rpmbuild -bs`
# the srpm's BuildRequires are frozen against %{_host_cpu}, not the target). Crucially, alma ppc
# chroots report %{_host_cpu}=powerpc64le while rocky reports ppc64le, so BOTH must be matched --
# that mismatch is exactly why elilo pulled in the (ppc-absent) gnu-efi BuildRequires on alma ppc.
%if "%{_host_cpu}" == "ppc64le"
%global use_prebuilt 1
%endif
%if "%{_host_cpu}" == "powerpc64le"
%global use_prebuilt 1
%endif
%if 0%{?rhel} == 8
%global use_prebuilt 1
%endif
%if 0%{?suse_version}
%global use_prebuilt 1
%endif
BuildRequires: gcc
BuildRequires: make
BuildRequires: cpio
%if ! 0%{?use_prebuilt}
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
%if 0%{?use_prebuilt}
# Reuse the prebuilt EFI payload from the tracked noarch package (ppc64le / EL8).
mkdir -p prebuilt
rpm2cpio %{SOURCE4} | (cd prebuilt && cpio -idm --quiet)
test -f prebuilt/tftpboot/xcat/elilo-x64.efi
%endif

%build

rm -rf %{buildroot}

%if ! 0%{?use_prebuilt}
make
%endif


%install

mkdir -p  %{buildroot}/tftpboot/xcat
%if 0%{?use_prebuilt}
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
