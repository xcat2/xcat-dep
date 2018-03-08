Summary: xCAT openbmc python dependency
Name: python-openbmc-dep
Version: 1.0
Release: %{?release:%{release}}%{!?release:snap%(date +"%Y%m%d%H%M")}
Epoch: 1
License: MIT-Equivalent
Group: Applications/System
Source: python-openbmc-dep-%{version}.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

#workaround for https://github.com/gevent/gevent/issues/685
%define _python_bytecompile_errors_terminate_build 0

%ifnos linux
AutoReqProv: no
%endif

#BuildArch: noarch
Requires: python-requests

%description
python-openbmc-dep provides docopt, gevent and greenlet python modules which xCAT-openbmc-py requires.

%prep
%setup -q -n python-openbmc-dep
#pip install -U --force --prefix `pwd` docopt gevent

%build

%install
rm -rf $RPM_BUILD_ROOT
install -d $RPM_BUILD_ROOT/%{prefix}/lib/python/agent
install -m644 lib/python*/site-packages/*.py $RPM_BUILD_ROOT/%{prefix}/lib/python/agent
install -m755 lib64/python*/site-packages/*.so $RPM_BUILD_ROOT/%{prefix}/lib/python/agent

install -d $RPM_BUILD_ROOT/%{prefix}/lib/python/agent/gevent
install -d $RPM_BUILD_ROOT/%{prefix}/lib/python/agent/gevent/libev
install -m755 lib64/python*/site-packages/gevent/*.* $RPM_BUILD_ROOT/%{prefix}/lib/python/agent/gevent
install -m755 lib64/python*/site-packages/gevent/libev/*.* $RPM_BUILD_ROOT/%{prefix}/lib/python/agent/gevent/libev


%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
%{prefix}

%changelog

%pre

%post

%preun

