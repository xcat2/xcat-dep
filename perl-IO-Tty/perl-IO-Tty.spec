Name:           perl-IO-Tty
Version:        1.20
Release:        1%{?dist}
Summary:        Perl interface to pseudo tty's
License:        (GPL+ or Artistic) and BSD
URL:            https://metacpan.org/release/IO-Tty
Source0:        https://cpan.metacpan.org/authors/id/T/TO/TODDR/IO-Tty-%{version}.tar.gz
BuildRequires:  coreutils
BuildRequires:  findutils
BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  perl-interpreter
BuildRequires:  perl-devel
BuildRequires:  perl-generators
BuildRequires:  perl(Config)
BuildRequires:  perl(Cwd)
BuildRequires:  perl(Exporter)
BuildRequires:  perl(ExtUtils::MakeMaker)
BuildRequires:  perl(Carp)
BuildRequires:  perl(DynaLoader)
BuildRequires:  perl(IO::File)
BuildRequires:  perl(IO::Handle)
BuildRequires:  perl(POSIX)
BuildRequires:  perl(strict)
BuildRequires:  perl(vars)
BuildRequires:  perl(Test::More)
BuildRequires:  perl(warnings)
Requires:       perl(:MODULE_COMPAT_%(eval "`perl -V:version`"; echo $version))

# Do not "provide" the private perl libs.
%{?perl_default_filter}

%description
IO::Tty and IO::Pty provide an interface to pseudo tty's.

%prep
%setup -q -n IO-Tty-%{version}

%build
perl Makefile.PL INSTALLDIRS=vendor OPTIMIZE="%{optflags}"
make %{?_smp_mflags}

%install
make pure_install DESTDIR=%{buildroot}
find %{buildroot} -type f -name .packlist -delete
find %{buildroot} -type f -name '*.bs' -empty -delete
%{_fixperms} %{buildroot}

%check
make test

%files
%doc ChangeLog README
%{perl_vendorarch}/auto/IO/
%{perl_vendorarch}/IO/
%{_mandir}/man3/IO::Pty.3*
%{_mandir}/man3/IO::Tty.3*
%{_mandir}/man3/IO::Tty::Constant.3*

%changelog
* Fri Sep 04 2026 Daniel Hilst <392820+dhilst@users.noreply.github.com> - 1.20-1
- Build IO-Tty 1.20. 1.12 mis-detects _getpty on EL8 and newer and the module
  then fails to load.
