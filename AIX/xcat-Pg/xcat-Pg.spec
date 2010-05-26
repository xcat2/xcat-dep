Summary: Package for Postgresql  on AIX
Name:xcat-postgresql 
Version: 5 
Release: 1
License: GPL
Group: Applications/System
Vendor: postgresql 
Packager: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
#BuildRoot: /var/tmp/postgresql-root
BuildArch: ppc
Source: postgresql-8.4.4-aix6.1.tar.gz 
Provides: xcat-postgresql = %{version}

%description
postgresql-8.4.4  (64-bit).

%prep
%setup -q -n postgresql-8.4.4 
%build

%install

mkdir -p $RPM_BUILD_ROOT/var/lib/pgsql
cp -rp /opt/freeware/src/packages/BUILD/postgresql-8.4.4/*  $RPM_BUILD_ROOT/var/lib/pgsql


%post

%clean

%files
%defattr(-,root,root)
/var/lib/pgsql

