%define name zhcp

Summary: zhcp
Name: %{name}
Version: 1.3
Release: 1
Source: zhcp-build.tar.gz
Vendor: IBM
License: IBM Copyright 2012 Eclipse Public License
Group: System/tools
BuildRoot: %{_tmppath}/zhcp
Prefix: /opt/zhcp

%description
The System z hardware control point (zHCP) is C program API to interface with 
z/VM SMAPI.

%prep
tar -zxvf ../SOURCES/zhcp-build.tar.gz -C ../BUILD/ --strip 1

%build
make

%install
make install
make post
make clean

mkdir -p $RPM_BUILD_ROOT/usr/bin
ln -sf %{prefix}/bin/smcli $RPM_BUILD_ROOT/usr/bin
chmod 644 $RPM_BUILD_ROOT/usr/bin/smcli
mkdir -p $RPM_BUILD_ROOT/usr/share/man/man1/
cp smcli.1.gz $RPM_BUILD_ROOT/usr/share/man/man1/

%post
echo "/opt/zhcp/lib" > /etc/ld.so.conf.d/zhcp.conf
/sbin/ldconfig

%preun
# Delete man page and smcli command
rm -rf /etc/ld.so.conf.d/zhcp.conf
rm -rf /usr/bin/smcli
rm -rf /usr/share/man/man1/smcli.1.gz

%files
# Files provided by this package
%defattr(-,root,root)
/opt/zhcp/*
/etc/ld.so.conf.d/zhcp.conf
/usr/bin/smcli
/usr/share/man/man1/smcli.1.gz

