%global genesis_arch %{?genesis_arch}%{!?genesis_arch:x86_64}

Name: xCAT-genesis-openembedded-%{genesis_arch}
Version: %{?version}%{!?version:0}
Release: %{?release}%{!?release:1}
Summary: xCAT OpenEmbedded Genesis netboot image
License: Various
URL: https://xcat.org/
Source0: %{name}-%{version}.tar.gz
BuildArch: noarch
AutoReqProv: no

%description
The OpenEmbedded Genesis image used by xCAT for discovery, inventory, and
service actions before a node boots its installed operating system.

%prep
%setup -q

%build

%install
rm -rf %{buildroot}
install -d -m 0755 %{buildroot}/opt/xcat/share/xcat/netboot/genesis-openembedded/%{genesis_arch}
install -m 0644 image/* %{buildroot}/opt/xcat/share/xcat/netboot/genesis-openembedded/%{genesis_arch}/
# Keep this path stable across RPM build hosts. %%{_docdir} differs on SUSE.
install -d -m 0755 %{buildroot}/usr/share/doc/%{name}
install -m 0644 xcat-core-revision %{buildroot}/usr/share/doc/%{name}/

%files
%dir /opt/xcat
%dir /opt/xcat/share
%dir /opt/xcat/share/xcat
%dir /opt/xcat/share/xcat/netboot
%dir /opt/xcat/share/xcat/netboot/genesis-openembedded
/opt/xcat/share/xcat/netboot/genesis-openembedded/%{genesis_arch}
%doc /usr/share/doc/%{name}/xcat-core-revision
