%ifarch i386 i586 i686 x86
Source1: kernel-2.6.18-53.el5.i686.rpm 
Source2: modlist-2.6.18-53.el5.x86
%define kver 2.6.18-53.el5
%define version	2.6.18_53
%define tarch x86
%endif
%ifarch x86_64
Source1: kernel-2.6.18-53.el5.x86_64.rpm
Source2: modlist-2.6.18-53.el5.x86_64
%define version	2.6.18_53
%define kver 2.6.18-53.el5
%define tarch x86_64
%endif
%ifarch ppc ppc64
Source1: kernel-2.6.18-92.el5.ppc64.rpm
Source2: modlist-2.6.18-92.el5.ppc64
%define kver 2.6.18-92.el5
%define tarch ppc64
%define version	2.6.18_92
%endif
BuildArch: noarch
%define name	xCAT-nbkernel-%{tarch}
Release: 2
Epoch: 1
AutoReq: false
AutoProv: false
Requires: xCAT-server xCAT-nbroot-oss-%{tarch} xCAT-nbroot-core-%{tarch}

Name:	 %{name}
Version: %{version}
Group: System/Utilities
License: GPL
Summary: xcat-nbroot-oss provides opensource components of the netboot image
URL:	 http://xcat.org
Buildroot:  %{_localstatedir}/tmp/xcat-nbk
Prefix: /opt/xcat

%Description
xcat-nbroot-oss is a particular packaging of buildroot from the uclibc.org site.
All files included are as they were downloadable on 4/7/2007
%Prep
rm -rf %{name}
mkdir -p %{name}/%{prefix}/share/xcat/netboot/%{tarch}/nbroot
cd %{name}
mkdir -p ./%{prefix}/share/xcat/netboot/%{tarch}/nbroot
cd ./%{prefix}/share/xcat/netboot/%{tarch}/nbroot
rpm2cpio %{SOURCE1} | cpio -ivdum
mkdir -p ../../../../../../../tftpboot/xcat/
cp boot/vmlinuz* ../../../../../../../tftpboot/xcat/nbk.%{tarch}
mv boot/* ../
rmdir boot





%Build
cd %{name}
cd ./%{prefix}/share/xcat/netboot/%{tarch}/nbroot/lib/modules/*
pwd;
find kernel -type f -exec grep -q {} %{SOURCE2} \; -o -type f -a -exec rm {} \;
find kernel -type d -a -empty | xargs rmdir
find kernel -type d -a -empty | xargs rmdir
find kernel -type d -a -empty | xargs rmdir
cd -
cd ./%{prefix}/share/xcat/netboot/%{tarch}/nbroot
depmod -b . %{kver}

%Install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT
cd %{name}
cp -a * $RPM_BUILD_ROOT

%Files
%defattr(-,root,root)
/
