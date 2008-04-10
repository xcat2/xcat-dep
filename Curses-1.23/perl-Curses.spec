%define _use_internal_dependency_generator 0
%define debug_package %nil

Name: perl-Curses
Version: 1.23
Release: 1
Summary: Terminal screen handling and optimization
License: Perl/Artistic License?
Group: Applications/CPAN
URL: http://cpan.org/modules/by-module/Curses/Curses-1.23.tar.gz
BuildRoot: %{_tmppath}/%{name}-root
Requires: perl >= 0:5.002
Buildarch: noarch
Source: Curses-%{version}.tar.gz

%description
"Curses" is the interface between Perl and your system’s curses(3) library.
For descriptions on the usage of a given function, variable, or constant,
consult your system’s documentation, as such information invariably varies
(:-) between different curses(3) libraries and operating systems.  This
document describes the interface itself, and assumes that you already know
how your system’s c.

%prep
%setup -q -n Curses-%{version} 

%build
umask 022
CFLAGS="$RPM_OPT_FLAGS" perl Makefile.PL PREFIX=$RPM_BUILD_ROOT/usr INSTALLDIRS=vendor
make
make test

%install
umask 022
if [ "$RPM_BUILD_ROOT" != "/" ]; then
   %{__rm} -rf $RPM_BUILD_ROOT
fi
make install

[ -x /usr/lib/rpm/brp-compress ] && /usr/lib/rpm/brp-compress

find $RPM_BUILD_ROOT \( -name perllocal.pod -o -name .packlist \) -exec rm -v {} \;

find $RPM_BUILD_ROOT/usr -type f -print | \
	sed "s@^$RPM_BUILD_ROOT@@g" | \
	grep -v perllocal.pod | \
	grep -v "\.packlist" > %{name}-%{version}-filelist
if [ "$(cat %{name}-%{version}-filelist)X" = "X" ] ; then
    echo "ERROR: EMPTY FILE LIST"
    exit -1
fi

%clean
if [ "$RPM_BUILD_ROOT" != "/" ]; then
   %{__rm} -rf $RPM_BUILD_ROOT
fi

%files -f %{name}-%{version}-filelist
%defattr(-,root,root)

%changelog
* Thu Apr 10 2008 Egan Ford <datajerk@gmail.com>
+ perl-Curses-1.23-1
- First cut for xCAT 2.0.

* Tue Jan 09 2007 Daryl W. Grunau <dwg@lanl.gov>
+ xcat-perl-Curses-1.23-1
- First cut.

