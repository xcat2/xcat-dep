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
BuildRequires: gzip
BuildRequires: tar

%description
The OpenEmbedded Genesis image used by xCAT for discovery, inventory, and
service actions before a node boots its installed operating system.

%prep
rm -rf %{name}-%{version}
tar -xzf "$RPM_SOURCE_DIR/%{name}-%{version}.tar.gz"

%build

%install
cd %{name}-%{version}
rm -rf "$RPM_BUILD_ROOT"
install -d -m 0755 "$RPM_BUILD_ROOT/opt/xcat/share/xcat/netboot/genesis-openembedded/%{genesis_arch}"
install -m 0644 image/* "$RPM_BUILD_ROOT/opt/xcat/share/xcat/netboot/genesis-openembedded/%{genesis_arch}/"
# Keep this path stable across RPM build hosts. %%{_docdir} differs on SUSE.
install -d -m 0755 "$RPM_BUILD_ROOT/usr/share/doc/%{name}"
install -m 0644 xcat-core-revision "$RPM_BUILD_ROOT/usr/share/doc/%{name}/"
install -d -m 0755 "$RPM_BUILD_ROOT/usr/libexec/xcat"
install -m 0755 activate "$RPM_BUILD_ROOT/usr/libexec/xcat/genesis-openembedded-activate-%{genesis_arch}"

%posttrans
/usr/libexec/xcat/genesis-openembedded-activate-%{genesis_arch} %{genesis_arch}

%postun
if [ "$1" -eq 0 ] && [ -f /proc/cmdline ]; then
    host_root=$(stat -c '%i %d' / 2>/dev/null) || host_root=
    init_root=$(stat -c '%i %d' /proc/1/root/. 2>/dev/null) || init_root=
    if [ -n "$host_root" ] && [ "$host_root" = "$init_root" ] \
        && [ -x /opt/xcat/sbin/mknb ]; then
        /opt/xcat/sbin/mknb %{genesis_arch} --remove-openembedded || :
        /opt/xcat/sbin/mknb %{genesis_arch} || :
    fi
fi

%files
%defattr(-,root,root,-)
%dir /opt/xcat
%dir /opt/xcat/share
%dir /opt/xcat/share/xcat
%dir /opt/xcat/share/xcat/netboot
%dir /opt/xcat/share/xcat/netboot/genesis-openembedded
/opt/xcat/share/xcat/netboot/genesis-openembedded/%{genesis_arch}
%dir /usr/share/doc/%{name}
%doc /usr/share/doc/%{name}/xcat-core-revision
/usr/libexec/xcat/genesis-openembedded-activate-%{genesis_arch}
