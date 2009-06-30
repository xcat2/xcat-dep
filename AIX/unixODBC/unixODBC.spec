Summary: Metapackage for unixODBC on AIX
Name: unixODBC
Version: 2.2.14
Release: 64bit
License: LGPL
Group: Applications/System
Vendor: unixODBC 
Packager: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
BuildArch: ppc
Source1: unixODBC-2.2.14-aix-ppc-64.tar.gz
Provides: unixODBC = %{version}

%description
unixODBC 2.2.14 on AIX systems (64-bit).

%prep
 
%build

%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/usr/local
cp %{SOURCE1} $RPM_BUILD_ROOT/
cd $RPM_BUILD_ROOT
gunzip -f unixODBC-2.2.14-aix-ppc-64.tar.gz
tar -xf unixODBC-2.2.14-aix-ppc-64.tar
cd usr/local/lib
/opt/freeware/bin/ar -x libodbc.a
/opt/freeware/bin/ar -x libodbccr.a
/opt/freeware/bin/ar -x libodbcinst.a
ln -s -f libodbcinst.so.1 libodbcinst.so
ln -s -f libodbccr.so.1 libodbccr.so
ln -s -f libodbc.so.1 libodbc.so

%post

%postun

%clean

%files
%defattr(-,root,root)
/usr/local/include
/usr/local/lib
/usr/local/bin
