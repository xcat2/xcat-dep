%define pkg yaboot-xcat
%define ver 1.3.15

Summary: yaboot binary for tftp server
%define _binary_payload w9.bzdio
Name: %{pkg}
Version: %{ver}
Release: 05262010
Group: System/Administration
License: GPL2
URL: http://yaboot.ozlabs.org/
Source: yaboot-%{ver}-05122010.tar.gz
Patch0: yaboot-skipmac.patch
Patch1: yaboot-32bitbuild.patch
Patch2: yaboot-1.3.15-promclaim.patch
Patch3: yaboot-1.3.14-better_netboot.patch
Patch4: yaboot-1.3.14-ipv6.patch
Patch5: yaboot-1.3.14-move_kernel.patch
Patch6: yaboot-1.3.14-better_netboot2.patch
Patch7: yaboot-1.3.15-05122010-sanedhcppriority.patch
BuildRoot: %{_tmppath}/%{pkg}-buildroot
Prefix: %{_prefix}
BuildArch: noarch

%description
This is a version of yaboot to facilitate an xCAT management node to boot
ppc nodes.  


%prep
%{__rm} -rf %{buildroot}
%setup -q -n yaboot-%{ver}-05122010
%patch0 -p1
%patch1 -p1
%patch2 -p1
%patch5 -p1
%patch3 -p1
%patch4 -p1
%patch6 -p1
%patch7 -p1


%build
make

%install
mkdir -p %{buildroot}/tftpboot/
cp second/yaboot %{buildroot}/tftpboot/

%files
%defattr(-,root,root)
/tftpboot/yaboot

