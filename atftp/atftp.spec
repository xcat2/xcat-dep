Name: atftp
Summary: Advanced Trivial File Transfer Protocol (ATFTP) - TFTP server
Group: System Environment/Daemons
Version: 0.7
Release: 8
License: GPL
Vendor: Linux Networx Inc.
Source: atftp_0.7.dfsg.orig.tar.gz
Source1: tftpd
Patch: atftp_0.7.dfsg-3.diff
Patch1: dfsg-3-to-multicast.diff
Patch2: dfsg-3-bigfiles.diff
Patch3: dfsg-3-to-winpaths.diff
Buildroot: /var/tmp/atftp-buildroot
Packager: Allen Reese <areese@lnxi.com>
Conflicts: tftp-server


%description
Multithreaded TFTP server implementing all options (option extension and
multicast) as specified in RFC1350, RFC2090, RFC2347, RFC2348 and RFC2349.
Atftpd also support multicast protocol knowed as mtftp, defined in the PXE
specification. The server supports being started from inetd(8) as well as
a deamon using init scripts.


%package client
Summary: Advanced Trivial File Transfer Protocol (ATFTP) - TFTP client
Group: Applications/Internet


%description client
Advanced Trivial File Transfer Protocol client program for requesting
files using the TFTP protocol.


%prep
%setup -n atftp-0.7.dfsg
%patch -p1
%patch1 -p1
%patch2 -p1
%patch3 -p1


%build
%configure
make


%install
[ -n "$RPM_BUILD_ROOT" -a "$RPM_BUILD_ROOT" != '/' ] && rm -rf $RPM_BUILD_ROOT
%makeinstall
mkdir -p "$RPM_BUILD_ROOT"/etc/init.d
cp %{SOURCE1} "$RPM_BUILD_ROOT"/etc/init.d



%files
%{_mandir}/man8/atftpd.8.gz
%{_sbindir}/atftpd
%{_mandir}/man8/in.tftpd.8.gz
%{_sbindir}/in.tftpd
/etc/init.d/tftpd


%files client
%{_mandir}/man1/atftp.1.gz
%{_bindir}/atftp


%preun


%post
if [ -x /usr/lib/lsb/install_initd ]; then
  /usr/lib/lsb/install_initd /etc/init.d/tftpd
elif [ -x /sbin/chkconfig ]; then
  /sbin/chkconfig --add tftpd
fi
/etc/init.d/tftpd restart



%clean
[ -n "$RPM_BUILD_ROOT" -a "$RPM_BUILD_ROOT" != '/' ] && rm -rf $RPM_BUILD_ROOT


%changelog
* Sat Oct 20 2007 Jarrod Johnson <jbj-at@ura.dnsalias.org>
- Update with debian patch

* Tue Jan 07 2003 Thayne Harbaugh <thayne@plug.org>
- put client in sub-rpm
