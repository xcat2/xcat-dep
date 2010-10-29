%define name zhcp

Summary: zhcp
Name: %{name}
Version: 1.1
Release: 1
Source: zhcp-build.tar.gz
Vendor: IBM
License: IBM (C) Copyright 2010 Eclipse Public License
Group: System/tools
Prefix: %{_prefix}

%description
The System z hardware control point (zHCP) is C program API to interface with 
z/VM SMAPI.

%prep
cd /opt/zhcpbuild/SOURCES/
tar -zxvf zhcp-build.tar.gz -C /opt/zhcpbuild/BUILD/ --strip 1

%build
make

%install
make install
make post
make clean

%post
echo "/opt/zhcp/lib" > /etc/ld.so.conf.d/zhcp.conf
/sbin/ldconfig

%files
%defattr(-,root,root,755)
/opt/zhcp/*

