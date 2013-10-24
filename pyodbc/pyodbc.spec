%{!?python_sitearch: %define python_sitearch %(%{__python} -c "from distutils.sysconfig import get_python_lib; print get_python_lib(1)")}

Name:           pyodbc
Version:        3.0.7
Release:        1%{?dist}
Summary:        Python DB API 2.0 Module for ODBC
Group:          Development/Languages
License:        MIT
URL:            http://code.google.com/p/pyodbc/
Source0:        http://pyodbc.googlecode.com/files/%{name}-%{version}.zip
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Requires:       unixODBC, python >= 2.4
BuildRequires:  unixODBC-devel
BuildRequires:  python-devel

%description
A Python DB API 2 and 3 module for ODBC. This project provides an up-to-date, 
convenient interface to ODBC using native data types like datetime and 
decimal.

%prep
%setup -q

%build
%{__python} setup.py build

%install
%{__rm} -rf %{buildroot}
%{__python} setup.py install -O1 --skip-build --root %{buildroot}

%clean
%{__rm} -rf %{buildroot}

%files
%defattr(-,root,root,-)
%doc LICENSE.txt README.rst
%{python_sitearch}/*

%changelog
* Sun Aug 17 2014 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 3.0.7-1
- Rebuilt for https://fedoraproject.org/wiki/Fedora_21_22_Mass_Rebuild

* Sat Jun 07 2014 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 3.0.6-4
- Rebuilt for https://fedoraproject.org/wiki/Fedora_21_Mass_Rebuild

* Sun Aug 04 2013 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 3.0.6-3
- Rebuilt for https://fedoraproject.org/wiki/Fedora_20_Mass_Rebuild

* Thu Feb 14 2013 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 3.0.6-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_19_Mass_Rebuild

* Mon Aug 13 2012 Honza Horak <hhorak@redhat.com> - 3.0.6-1
- Upstream released 3.0.6
 
* Sat Jul 21 2012 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 2.1.5-7
- Rebuilt for https://fedoraproject.org/wiki/Fedora_18_Mass_Rebuild

* Sat Jan 14 2012 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 2.1.5-6
- Rebuilt for https://fedoraproject.org/wiki/Fedora_17_Mass_Rebuild

* Tue Feb 08 2011 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 2.1.5-5
- Rebuilt for https://fedoraproject.org/wiki/Fedora_15_Mass_Rebuild

* Wed Jul 21 2010 David Malcolm <dmalcolm@redhat.com> - 2.1.5-4
- Rebuilt for https://fedoraproject.org/wiki/Features/Python_2.7/MassRebuild

* Sun Jul 26 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 2.1.5-3
- Rebuilt for https://fedoraproject.org/wiki/Fedora_12_Mass_Rebuild

* Wed Apr 22 2009 Ray Van Dolson <rayvd@fedoraproject.org> - 2.1.5-2
- EVR bump

* Wed Apr 22 2009 Ray Van Dolson <rayvd@fedoraproject.org> - 2.1.5-1
- Upstream released 2.1.5

* Mon Feb 23 2009 Ray Van Dolson <rayvd@fedoraproject.org> - 2.1.4-5
- Removing versioned BuildRequires

* Mon Feb 23 2009 Ray Van Dolson <rayvd@fedoraproject.org> - 2.1.4-4
- Changes for plague

* Sun Feb 22 2009 Ray Van Dolson <rayvd@fedoraproject.org> - 2.1.4-3
- Removed extraneous Requires

* Sun Feb 22 2009 Ray Van Dolson <rayvd@fedoraproject.org> - 2.1.4-2
- Added README.rst file from git repo

* Wed Jan 07 2009 Ray Van Dolson <rayvd@fedoraproject.org> - 2.1.4-1
- Upstream released 2.1.4

* Wed Dec 03 2008 Ray Van Dolson <rayvd@fedoraproject.org> - 2.1.1-1
- New upstream version and homepage

* Mon Jun 02 2008 Ray Van Dolson <rayvd@fedoraproject.org> - 2.0.58-3
- Removed silly python BuildRequires

* Mon Jun 02 2008 Ray Van Dolson <rayvd@fedoraproject.org> - 2.0.58-2
- Added python and python-devel to BuildRequires

* Fri May 30 2008 Ray Van Dolson <rayvd@fedoraproject.org> - 2.0.58-1
- Initial package
