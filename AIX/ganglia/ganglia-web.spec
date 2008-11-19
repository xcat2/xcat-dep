Summary: Metapackage for Ganglia-Web interface on AIX
Name: ganglia-web 
Version: 5.0
Release: 1
License: EPL
Group: Applications/System
Vendor: IBM Corp.
Packager: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
BuildArch: ppc
Source1: ganglia-web-MPerzl.tar.gz 
Provides: ganglia-web = %{version}

%description
Installs Ganglia web interface

%prep

%build

%install

mkdir -p $RPM_BUILD_ROOT/var/www/htdocs
cp %{SOURCE1} $RPM_BUILD_ROOT/var/www/htdocs

%post

cd /usr/local

# uwrap
gunzip /var/www/htdocs/ganglia-web-MPerzl.tar.gz
tar -xvf /var/www/htdocs/ganglia-web-MPerzl.tar





%clean

%files
/var/www/htdocs/ganglia-web-MPerzl.tar.gz
%defattr(-,root,root)
