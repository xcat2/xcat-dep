Summary: Package for MySQL Connector/ODBC on AIX
Name: mysql-connector-odbc
Version: 3.51.27
Release: 64bit
License: GPL
Group: Applications/System
Vendor: MySQL
Packager: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
BuildArch: ppc
Source: mysql-connector-odbc-3.51.27-aix5.3-powerpc-64bit.tar.gz
Provides: mysql-connector-odbc = %{version}

%description
MySQL Connector/ODBC 3.51.27 on AIX systems (64-bit).

%prep
%setup -q -n mysql-connector-odbc-3.51.27-aix5.3-powerpc-64bit
%build

%install

mkdir -p $RPM_BUILD_ROOT/usr/local/bin
mkdir -p $RPM_BUILD_ROOT/usr/local/lib
mkdir -p $RPM_BUILD_ROOT/usr/share/doc/mysql-connector-odbc-3.51.27

cp bin/* $RPM_BUILD_ROOT/usr/local/bin
#chmod 755 $RPM_BUILD_ROOT/usr/local/bin/*
cp lib/* $RPM_BUILD_ROOT/usr/local/lib
#chmod 755 $RPM_BUILD_ROOT/usr/local/lib/*
cp ChangeLog $RPM_BUILD_ROOT/usr/share/doc/mysql-connector-odbc-3.51.27
cp INSTALL $RPM_BUILD_ROOT/usr/share/doc/mysql-connector-odbc-3.51.27
cp LICENSE.exceptions $RPM_BUILD_ROOT/usr/share/doc/mysql-connector-odbc-3.51.27
cp LICENSE.gpl $RPM_BUILD_ROOT/usr/share/doc/mysql-connector-odbc-3.51.27
cp README $RPM_BUILD_ROOT/usr/share/doc/mysql-connector-odbc-3.51.27
cp README.debug $RPM_BUILD_ROOT/usr/share/doc/mysql-connector-odbc-3.51.27
#chmod 644 $RPM_BUILD_ROOT/usr/share/doc/mysql-connector-odbc-3.51.27/*

%post

%clean

%files
%defattr(-,root,root)
/usr/local/lib
/usr/local/bin
/usr/share/doc/mysql-connector-odbc-3.51.27

