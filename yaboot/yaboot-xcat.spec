%define pkg yaboot-xcat
%define ver 1.3.14

Summary: yaboot binary for tftp server
Name: %{pkg}
Version: %{ver}
Release: 2
Group: System/Administration
License: GPL2
URL: http://yaboot.ozlabs.org/
Source: http://yaboot.ozlabs.org/releases/yaboot-1.3.14.tar.gz
Patch0: yaboot-fixes.patch
Patch1: yaboot-buf-expand.patch
BuildRoot: %{_tmppath}/%{pkg}-buildroot
Prefix: %{_prefix}
BuildArch: noarch

%description
This is a version of yaboot to facilitate an xCAT management node to boot
ppc nodes.  


%prep
%{__rm} -rf %{buildroot}
%setup -q -n yaboot-%{ver}
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

