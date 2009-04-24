
Name:           scsi-target-utils
Version:        0.9.6
Release:        1
Summary:        The SCSI target daemon and utility programs

Group:          System Environment/Daemons
License:        GPL
URL:            http://stgt.berlios.de
Source0:        http://stgt.berlios.de/releases/tgt-0.9.6.tar.bz2
Source1:        tgtd.init
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

BuildRequires:  openssl-devel, pkgconfig
Requires:       /sbin/chkconfig

%description
The SCSI target package contains the daemon and tools to setup a SCSI targets.
Currently, software iSCSI targets are supported.

%prep
%setup -q -n tgt-0.9.6


%build
if pkg-config openssl ; then
        CPPFLAGS=`pkg-config --cflags openssl`; export CPPFLAGS
        LDFLAGS=`pkg-config --libs openssl`; export LDFLAGS
fi
cd usr && make %{?_smp_mflags} ISCSI=1


%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT%{_sbindir}
mkdir -p $RPM_BUILD_ROOT%{_mandir}/man8
mkdir -p $RPM_BUILD_ROOT%{_initrddir}

install -p -m 755 %{SOURCE1} $RPM_BUILD_ROOT%{_initrddir}/tgtd
install -p -m 644 doc/manpages/tgtadm.8 $RPM_BUILD_ROOT/%{_mandir}/man8
cd usr && make install DESTDIR=$RPM_BUILD_ROOT
rm $RPM_BUILD_ROOT/usr/sbin/tgt-admin


%post
/sbin/chkconfig --add tgtd


%postun
if [ "$1" = "1" ]; then
     /sbin/service tgtd condrestart > /dev/null 2>&1
fi


%preun
if [ "$1" = "0" ]; then
     /sbin/service tgtd stop > /dev/null 2>&1
     /sbin/chkconfig --del tgtd
fi


%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%doc README
%doc doc/README.iscsi
%{_sbindir}/tgtd
%{_sbindir}/tgtadm
%{_sbindir}/tgtimg
#%{_sbindir}/tgt-admin Not yet, Config-General needed for this, will wait for now
%{_sbindir}/tgt-setup-lun
%{_mandir}/man8/*
%{_initrddir}/tgtd

%changelog
* Mon Nov 03 2008 Jarrod B Johnson <jbj-xd@ura.dnsalias.org> - 0.9.1-1
- Roll in most recent stable rlease
* Tue Jul 10 2007 Mike Christie <mchristie@redhat.com> - 0.0-0.20070620snap
- first build
