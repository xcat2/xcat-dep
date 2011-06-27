%define pkg yaboot-xcat
%define ver 1.3.17

Summary: yaboot binary for tftp server
%define _binary_payload w9.bzdio
%define _binaries_in_noarch_packages_terminate_build   0
Name: %{pkg}
Version: %{ver}
Release: rc1
Group: System/Administration
License: GPL2
URL: http://yaboot.ozlabs.org/
Source: yaboot-%{ver}-rc1.tar.gz
Patch0: yaboot-32bitbuild.patch
#Patch1: yaboot-debug.patch
#Patch2: yaboot-move_kernel.patch
Patch3: yaboot-sanedhcppriority.patch
Patch4: yaboot-promclaim.patch
BuildRoot: %{_tmppath}/%{pkg}-buildroot
Prefix: %{_prefix}
BuildArch: noarch

%description
This is a version of yaboot to facilitate an xCAT management node to boot
ppc nodes.  


%prep
%{__rm} -rf %{buildroot}
%setup -q -n yaboot-%{ver}-rc1
%patch0 -p1
#%patch1 -p1
#%patch2 -p1
%patch3 -p1
%patch4 -p1




%build
make

%install
mkdir -p %{buildroot}/tftpboot/
cp second/yaboot %{buildroot}/tftpboot/

%files
%defattr(-,root,root)
/tftpboot/yaboot

