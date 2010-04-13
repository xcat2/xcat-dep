%define name zhcp

Summary: zhcp
Name: %{name}
Version: 1
Release: 1
Source: zhcp-build.tar.gz
Vendor: IBM
License: Licensed materials - Property of IBM
Group: System/tools
Prefix: %{_prefix}

%description

%prep
cd /opt/zhcpbuild/SOURCES/
tar -zxvf zhcp-build.tar.gz -C /opt/zhcpbuild/BUILD/ --strip 1

%build
make

%install
make install
make post
make clean

%files
%defattr(-,root,root,755)
/opt/zhcp/*

