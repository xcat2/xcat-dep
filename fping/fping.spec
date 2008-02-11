Source: fping.tar.gz
Patch: fping.patch
Release: 2
AutoReq: true
AutoProv: true
BuildRoot: %{_tmppath}/fping-2.4b2-root

Name:	 fping
Version: 2.4b2_to
Group: System/Utilities
License: Stanford
Summary: Pings hosts in parallel
URL:	 http://fping.sourceforge.net/

%Description
fping pings hosts in parallel
%Prep
%setup -q
%patch -p1


%Build
%configure
make
%Install
mkdir -p $RPM_BUILD_ROOT/usr/bin
cp fping $RPM_BUILD_ROOT/usr/bin
mkdir -p $RPM_BUILD_ROOT/usr/share/man/man8/
cp fping.8 $RPM_BUILD_ROOT/usr/share/man/man8/
pwd
echo $RPM_BUILD_ROOT
%Files
%defattr(-,root,root)
/usr/bin/fping
/usr/share/man/man8/fping.8.gz
