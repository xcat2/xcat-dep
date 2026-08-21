%global genesis_arch %{?genesis_arch}%{!?genesis_arch:x86_64}

Name: xCAT-genesis-base-%{genesis_arch}
Version: %{?version}%{!?version:0}
Release: %{?release}%{!?release:1}
Epoch: 2
Summary: xCAT Genesis netboot image
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
install -d -m 0755 %{buildroot}/opt/xcat/share/xcat/netboot/genesis/%{genesis_arch}
install -m 0644 image/* %{buildroot}/opt/xcat/share/xcat/netboot/genesis/%{genesis_arch}/
install -d -m 0755 %{buildroot}%{_docdir}/%{name}
install -m 0644 xcat-core-revision %{buildroot}%{_docdir}/%{name}/

%post
mkdir -p /etc/xcat
touch /etc/xcat/genesis-base-updated
if [ -x /opt/xcat/sbin/mknb ] && [ -r /proc/cmdline ] && \
   [ "$(stat -c '%%i %%d' / 2>/dev/null)" = "$(stat -c '%%i %%d' /proc/1/root/. 2>/dev/null)" ]; then
    if /opt/xcat/sbin/mknb %{genesis_arch}; then
        rm -f /etc/xcat/genesis-base-updated
    else
        echo "mknb %{genesis_arch} was deferred; run it after xcatd is ready" >&2
    fi
fi

%files
%dir /opt/xcat
%dir /opt/xcat/share
%dir /opt/xcat/share/xcat
%dir /opt/xcat/share/xcat/netboot
%dir /opt/xcat/share/xcat/netboot/genesis
/opt/xcat/share/xcat/netboot/genesis/%{genesis_arch}
%doc %{_docdir}/%{name}/xcat-core-revision
