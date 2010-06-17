Source: fping.tar.gz
Release: 1
AutoReq: true
AutoProv: true
BuildRoot: %{_tmppath}/fping-2.4b2_1-root

Name:	 fping
Version: 2.4b2_1
Group: System/Utilities
License: Stanford
Summary: Pings hosts in parallel
URL:	 http://fping.sourceforge.net/

%Description
fping pings hosts in parallel
%Prep
%setup -q

%Build
make
%Install
mkdir -p $RPM_BUILD_ROOT/usr/bin
cp fping $RPM_BUILD_ROOT/usr/bin
cp fping6 $RPM_BUILD_ROOT/usr/bin
mkdir -p $RPM_BUILD_ROOT/usr/share/man/man8/
cp fping.8 $RPM_BUILD_ROOT/usr/share/man/man8/
pwd
echo $RPM_BUILD_ROOT
%Files
%defattr(-,root,root)
/usr/bin/fping
/usr/bin/fping6
/usr/share/man/man8/fping.8
