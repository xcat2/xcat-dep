#
# 5.4+ enables Perl by default
#

# because perl(Tk) is optional, automatic dependencies will never succeed:
%define _use_internal_dependency_generator 0
%define __find_requires %{_builddir}/net-snmp-%{version}/dist/find-requires
%define __find_provides /usr/lib/rpm/find-provides
%define _perl_dir /usr/opt/perl5

Summary: Tools and servers for the SNMP protocol
Name: net-snmp
Version: 5.4.2.1
# update release for vendor release. (eg 1.fc6, 1.rh72, 1.ydl3, 1.ydl23)
Release: 1
URL: http://www.net-snmp.org/
License: BSDish
Group: System Environment/Daemons
Vendor: Net-SNMP project
Source: http://prdownloads.sourceforge.net/net-snmp/net-snmp-%{version}.tar.gz
#Prereq: openssl
Obsoletes: cmu-snmp ucd-snmp ucd-snmp-utils
BuildRoot: /tmp/%{name}-root
Packager: The Net-SNMP Coders <http://sourceforge.net/projects/net-snmp/>
#Requires:
BuildRequires: coreutils
Patch0: net-snmp-find-requires.patch

%description

Net-SNMP provides tools and libraries relating to the Simple Network
Management Protocol including: An extensible agent, An SNMP library,
tools to request or set information from SNMP agents, tools to
generate and handle SNMP traps, etc.  Using SNMP you can check the
status of a network of computers, routers, switches, servers, ... to
evaluate the state of your network.

%package devel
Group: Development/Libraries
Summary: The includes and static libraries from the Net-SNMP package.
AutoReqProv: no
Requires: net-snmp = %{version}
Obsoletes: cmu-snmp-devel ucd-snmp-devel

%description devel
The net-snmp-devel package contains headers and libraries which are
useful for building SNMP applications, agents, and sub-agents.

%package perl
Group: Development/Libraries
Summary: The perl NET-SNMP module and the mib2c tool
Requires: %{name} = %{version}

%description perl
The net-snmp-perl package contains the perl files to use SNMP from within
Perl.

Install the net-snmp-perl package, if you want to use mib2c or SNMP with perl.

%prep
%setup -q -n %{name}-%{version}
%patch -p1

%build
export CC=cc_r
export PATH=/usr/vac/bin:$PATH
./configure \
	--prefix="/opt/freeware" \
	--enable-static \
	--enable-shared \
	--with-logfile="/var/log/snmpd.log" \
	--with-persistent-directory="/var/net-snmp" \
	--enable-ucd-snmp-compatibility \
	--with-openssl \
	--disable-ipv6 \
	--enable-local-smux \
	--with-sys-location="Unknown" \
	--with-sys-contact="root@localhost" \
	--with-default-snmp-version="3" \
	
chmod +x %{__find_requires}
make %{?smp_mflags}

%install
#export CC=cc_r
# ----------------------------------------------------------------------
# 'install' sets the current directory to _topdir/BUILD/{name}-{version}
# ----------------------------------------------------------------------
rm -rf $RPM_BUILD_ROOT

make DESTDIR=%{buildroot} install

# Remove 'snmpinform' from the temporary directory because it is a
# symbolic link, which cannot be handled by the rpm installation process.
%__rm -f $RPM_BUILD_ROOT%{_prefix}/bin/snmpinform
# install the init script
mkdir -p $RPM_BUILD_ROOT/etc/rc.d/init.d
perl -i -p -e 's@/usr/local/share/snmp/@/etc/snmp/@g;s@usr/local@%{_prefix}@g' dist/snmpd-init.d
/opt/freeware/bin/install -m 755 dist/snmpd-init.d $RPM_BUILD_ROOT/etc/rc.d/init.d/snmpd
cp local/mib2c.*.conf ${RPM_BUILD_ROOT}%{_datadir}/snmp

cd perl
make DESTDIR=%{_perl_dir} install
# remove special files
find $RPM_BUILD_ROOT -name perllocal.pod \
        -o -name .packlist \
        -o -name "*.bs" \
        -o -name Makefile.subs.pl \
        | xargs -i rm -f {}
cd ..


%post
# ----------------------------------------------------------------------
# The 'post' script is executed just after the package is installed.
# ----------------------------------------------------------------------
# Create the symbolic link 'snmpinform' after all other files have
# been installed.
%__rm -f $RPM_INSTALL_PREFIX/bin/snmpinform
%__ln_s $RPM_INSTALL_PREFIX/bin/snmptrap $RPM_INSTALL_PREFIX/bin/snmpinform

# run ldconfig
#PATH="$PATH:/sbin" ldconfig -n $RPM_INSTALL_PREFIX/lib

%preun
# ----------------------------------------------------------------------
# The 'preun' script is executed just before the package is erased.
# ----------------------------------------------------------------------
# Remove the symbolic link 'snmpinform' before anything else, in case
# it is in a directory that rpm wants to remove (at present, it isn't).
%__rm -f $RPM_INSTALL_PREFIX/bin/snmpinform

%postun
# ----------------------------------------------------------------------
# The 'postun' script is executed just after the package is erased.
# ----------------------------------------------------------------------

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)

# Install the following documentation in _defaultdocdir/{name}-{version}/
%doc AGENT.txt ChangeLog CodingStyle COPYING
%doc EXAMPLE.conf.def FAQ INSTALL NEWS PORTING TODO
%doc README README.agentx README.hpux11 README.krb5
%doc README.snmpv3 README.solaris README.thread README.win32
%doc README.aix README.osX README.tru64 README.irix README.agent-mibs
%doc README.Panasonic_AM3X.txt
	 
%{_datadir}/snmp

%{_bindir}
%{_sbindir}
%{_mandir}/man1/*
# don't include Perl man pages, which start with caps
%{_mandir}/man3/[^A-Z]*
%{_mandir}/man5/*
%{_mandir}/man8/*
%{_libdir}/*.so*
/etc/rc.d/init.d/snmpd

%files devel
%defattr(-,root,root)

%{_includedir}
%{_libdir}/*.a
%{_libdir}/*.la

%files perl
%defattr(-,root,root)
%{_bindir}/mib2c
%{_bindir}/tkmib
%{_perl_dir}/lib/site_perl/5.8.2/aix-thread-multi/*
%attr(0644,root,root) %{_mandir}/man1/mib2c.1
%attr(0644,root,root) %{_mandir}/man1/tkmib.1
%attr(0644,root,root) /usr/share/man/man3/*SNMP*.3

%verifyscript
echo "No additional verification is done for net-snmp"

%changelog
* Tue May  6 2008 Jan Safranek <jsafranek@users.sf.net>
- remove %{libcurrent}
- don't use Provides: unless necessary, let rpmbuild compute the provided
  libraries

* Tue Jun 30 2007 Thomas Anders <tanders@users.sf.net>
- add "BuildRequires: perl-ExtUtils-Embed", e.g. for Fedora 7
- add --enable-as-needed if building with embedded Perl support
* Wed Nov 23 2006 Thomas Anders <tanders@users.sf.net>
- fixes for 5.4 and 64-bit platforms
- enable Perl by default, but allow for --without perl_modules|embedded_perl
- add netsnmp_ prefix for local defines

* Fri Sep  1 2006 Thomas Anders <tanders@users.sf.net>
- Update to 5.4.dev
- introduce %{libcurrent}
- use new disman/event name
- add: README.aix README.osX README.tru64 README.irix README.agent-mibs
  README.Panasonic_AM3X.txt
- add new NetSNMP::agent::Support

* Fri Jan 13 2006 hardaker <hardaker@users.sf.net>
- Update to 5.3.0.1

* Wed Dec 28 2005 hardaker <hardaker@users.sf.net>
- Update to 5.3

* Tue Oct 28 2003 rs <rstory@users.sourceforge.net>
- fix conditional perl build after reading rpm docs

* Sat Oct  4 2003 rs <rstory@users.sourceforge.net> - 5.0.9-4
- fix to build without requiring arguments
- separate embedded perl and perl modules options
- fix fix for init.d script for non-/usr/local installation

* Fri Sep 26 2003 Wes Hardaker <hardaker@users.sourceforge.net>
- fix perl's UseNumeric
- fix init.d script for non-/usr/local installation

* Fri Sep 12 2003 Wes Hardaker <hardaker@users.sourceforge.net>
- fixes for 5.0.9's perl support

* Mon Sep 01 2003 Wes Hardaker <hardaker@users.sourceforge.net>
- added perl support

* Wed Oct 09 2002 Wes Hardaker <hardaker@users.sourceforge.net>
- Incorperated most of Mark Harig's better version of the rpm spec and Makefile

* Wed Oct 09 2002 Wes Hardaker <hardaker@users.sourceforge.net>
- Made it possibly almost usable.

* Mon Apr 22 2002 Robert Story <rstory@users.sourceforge.net>
- created
