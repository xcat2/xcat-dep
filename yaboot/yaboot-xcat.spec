%define pkg yaboot-xcat
%define ver 1.3.15

Summary: yaboot binary for tftp server
%define _binary_payload w9.bzdio
Name: %{pkg}
Version: %{ver}
Release: 05172010
Group: System/Administration
License: GPL2
URL: http://yaboot.ozlabs.org/
Source: yaboot-%{ver}-05122010.tar.gz
Patch0: yaboot-skipmac.patch
Patch1: yaboot-32bitbuild.patch
Patch5: yaboot-1.3.14-move_kernel.patch
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
%patch5 -p1


%build
make

%install
mkdir -p %{buildroot}/tftpboot/
cp second/yaboot %{buildroot}/tftpboot/

%files
%defattr(-,root,root)
/tftpboot/yaboot

