%define _unpackaged_files_terminate_build 0
Summary: perl-version 
Name: perl-version 
Version: 0.76 
Release: 1
License: Perl/Artistic License?
Group: Applications/CPAN
Source: version-0.76.tar.gz 
BuildRoot: /tmp/version
BuildArch: noarch
Packager: unknown@localhost 
AutoReq: no
AutoReqProv: no
Requires: perl(Test::More)
Provides: perl(version::vxs) perl(version)

%description
Distribution id = J/JP/JPEACOCK/version-0.76.tar.gz
    CPAN_USERID  JPEACOCK (John Peacock <jpeacock@cpan.org>)
    CONTAINSMODS version::vxs version
    MD5_STATUS   OK
    archived     tar
    unwrapped    YES



%prep
%setup -q -n version-0.76

%build
CFLAGS="$RPM_OPT_FLAGS $CFLAGS" perl Makefile.PL 
make

%clean 
if [ "%{buildroot}" != "/" ]; then
  rm -rf %{buildroot} 
fi


%install

make PREFIX=%{_prefix} \
     DESTDIR=%{buildroot} \
     INSTALLDIRS=site \
     install

[ -x /usr/lib/rpm/brp-compress ] && /usr/lib/rpm/brp-compress

find ${RPM_BUILD_ROOT} \
  \( -path '*/perllocal.pod' -o -path '*/.packlist' -o -path '*.bs' \) -a -prune -o \
  -type f -printf "/%%P\n" > version-filelist

if [ "$(cat version-filelist)X" = "X" ] ; then
    echo "ERROR: EMPTY FILE LIST"
    exit 1
fi

%files -f version-filelist
%defattr(-,root,root)

%changelog
* Thu Nov 20 2008 unknown@localhost 
- Initial build
