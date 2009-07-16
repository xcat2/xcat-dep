Summary: Metapackage for unixODBC on AIX
Name: unixODBC
Version: 2.2.15
Release: pre 
License: LGPL
Group: Applications/System
Vendor: unixODBC 
Packager: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
BuildArch: ppc
Source1: unixODBC-2.2.15pre-aix-ppc.tar.gz
Provides: unixODBC = %{version}

%description
unixODBC 2.2.15 on AIX systems.

%prep
 
%build

%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/usr/local
cp %{SOURCE1} $RPM_BUILD_ROOT/
cd $RPM_BUILD_ROOT
gunzip -f unixODBC-2.2.15pre-aix-ppc.tar.gz
tar -xf unixODBC-2.2.15pre-aix-ppc.tar 
cd usr/local/lib
ln -s libodbcinst.so.1 libodbcinst.so
ln -s libodbccr.so.1 libodbccr.so
ln -s libodbc.so.1 libodbc.so

%post
cd /usr/local/lib
ln -s /usr/local/lib/libodbc.so.1 /usr/lib/libodbc.so
ln -s /usr/local/lib/libodbcinst.so.1 /usr/lib/libodbcinst.so
ln -s /usr/local/lib/libodbccr.so.1 /usr/lib/libodbccr.so

%postun
rm /usr/lib/libodbc.so
rm /usr/lib/libodbcinst.so
rm /usr/lib/libodbccr.so

%clean

%files
%defattr(-,root,root)
/etc/odbc.ini
/etc/odbcinst.ini
/usr/local/lib
/usr/local/bin
