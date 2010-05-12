%define pkg yaboot-xcat
%define ver 1.3.15

Summary: yaboot binary for tftp server
Name: %{pkg}
Version: %{ver}
Release: 05122010
Group: System/Administration
License: GPL2
URL: http://yaboot.ozlabs.org/
Source: yaboot-%{ver}-%{release}.tar.gz
Patch0: yaboot-skipmac.patch
Patch1: yaboot-32bitbuild.patch
BuildRoot: %{_tmppath}/%{pkg}-buildroot
Prefix: %{_prefix}
BuildArch: noarch

%description
This is a version of yaboot to facilitate an xCAT management node to boot
ppc nodes.  


%prep
%{__rm} -rf %{buildroot}
%setup -q -n yaboot-%{ver}-%{release}
%patch0 -p1
%patch1 -p1


%build
make

%install
mkdir -p %{buildroot}/tftpboot/
cp second/yaboot %{buildroot}/tftpboot/

%files
%defattr(-,root,root)
/tftpboot/yaboot

