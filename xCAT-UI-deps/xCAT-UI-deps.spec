Summary: Set of dependencies for the xCAT web client
Name: xCAT-UI-deps
Version: 2.7
Release: 1
License: EPL
Group: Applications/System
Source: xCAT-UI-deps.tar.gz
Packager: IBM
Vendor: IBM
URL: http://xcat.sourceforge.net/

Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
BuildArch: noarch
Provides: xCAT-UI-deps = %{version}
Requires: python >= 2.3

%description
Provides a set of dependencies (e.g. JQuery) for the xCAT web client.

%prep
%setup -q -n xCAT-UI-deps

%build
# Nothing to do

%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT%{prefix}/ui
set +x
cp -r * $RPM_BUILD_ROOT%{prefix}/ui
chmod 755 $RPM_BUILD_ROOT%{prefix}/ui/*
chmod 755 $RPM_BUILD_ROOT%{prefix}/ui/lib/ajaxterm/*.py
set -x

%files
%defattr(-,root,root)
%{prefix}/ui
