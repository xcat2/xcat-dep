%define pkgname Sys-Virt
%define filelist %{pkgname}-%{version}-filelist
%define NVR %{pkgname}-%{version}-%{release}
%define maketest 0

name:      perl-Sys-Virt
summary:   Sys-Virt - Represent and manage a libvirt hypervisor connection
version:   11.10.0
release:   1%{?dist}
vendor:    Daniel P. Berrange <berrange@redhat.com>
packager:  Arix International <cpan2rpm@arix.com>
license:   Artistic
group:     Applications/CPAN
url:       http://www.cpan.org
buildroot: %{_tmppath}/%{name}-%{version}-%(id -u -n)
prefix:    %(echo %{_prefix})
source:    Sys-Virt-v%{version}.tar.gz

BuildRequires: gcc
BuildRequires: make
BuildRequires: perl-interpreter
BuildRequires: perl-devel
BuildRequires: perl(ExtUtils::MakeMaker)
BuildRequires: perl(ExtUtils::CBuilder)
BuildRequires: perl(Module::Build)
BuildRequires: perl(XML::XPath)
BuildRequires: perl(XML::XPath::XMLParser)
BuildRequires: perl(Time::HiRes)
BuildRequires: perl(Sys::Hostname)
BuildRequires: perl-generators
BuildRequires: libvirt-devel
BuildRequires: pkgconfig(libvirt)

%description
The Sys::Virt module provides a Perl XS binding to the libvirt
virtual machine management APIs. This allows machines running
within arbitrary virtualization containers to be managed with
a consistent API.

%prep
%setup -q -n %{pkgname}-v%{version}
chmod -R u+w %{_builddir}/%{pkgname}-v%{version}

%build
CFLAGS="$RPM_OPT_FLAGS"
%{__perl} Makefile.PL `%{__perl} -MExtUtils::MakeMaker -e ' print qq|PREFIX=%{buildroot}%{_prefix}| if \$ExtUtils::MakeMaker::VERSION =~ /5\.9[1-6]|6\.0[0-5]/ '`
%{__make}
%if %maketest
%{__make} test
%endif

%install
[ "%{buildroot}" != "/" ] && rm -rf %{buildroot}

%{__make} pure_install DESTDIR=%{buildroot}

cmd=/usr/share/spec-helper/compress_files
[ -x $cmd ] || cmd=/usr/lib/rpm/brp-compress
[ -x $cmd ] && $cmd

# SuSE Linux
if [ -e /etc/SuSE-release -o -e /etc/UnitedLinux-release ]
then
    %{__mkdir_p} %{buildroot}/var/adm/perl-modules
    %{__cat} `find %{buildroot} -name "perllocal.pod"`  \
        | %{__sed} -e s+%{buildroot}++g                 \
        > %{buildroot}/var/adm/perl-modules/%{name}
fi

# remove special files
find %{buildroot} -name "perllocal.pod" \
    -o -name ".packlist"                \
    -o -name "*.bs"                     \
    |xargs -i rm -f {}

# no empty directories
find %{buildroot}%{_prefix}             \
    -type d -depth                      \
    -exec rmdir {} \; 2>/dev/null

%{__perl} -MFile::Find -le '
    find({ wanted => \&wanted, no_chdir => 1}, "%{buildroot}");
    print "%doc  Changes INSTALL README LICENSE examples";
    for my $x (sort @dirs, @files) {
        push @ret, $x unless indirs($x);
        }
    print join "\n", sort @ret;

    sub wanted {
        return if /auto$/;

        local $_ = $File::Find::name;
        my $f = $_; s|^\Q%{buildroot}\E||;
        return unless length;
        return $files[@files] = $_ if -f $f;

        $d = $_;
        /\Q$d\E/ && return for reverse sort @INC;
        $d =~ /\Q$_\E/ && return
            for qw|/etc %_prefix/man %_prefix/bin %_prefix/share|;

        $dirs[@dirs] = $_;
        }

    sub indirs {
        my $x = shift;
        $x =~ /^\Q$_\E\// && $x ne $_ && return 1 for @dirs;
        }
    ' > %filelist

[ -z %filelist ] && {
    echo "ERROR: empty %files listing"
    exit -1
    }

%clean
[ "%{buildroot}" != "/" ] && rm -rf %{buildroot}

%files -f %filelist
%defattr(-,root,root)

%changelog
* Sat Jun 06 2026 Daniel Hilst <392820+dhilst@users.noreply.github.com> - 11.10.0-1
- Update to v11.10.0 from CPAN
- Drop Sys-Virt-fixes.patch (not applicable to modern codebase)

* Sun Jul 27 2008 root@mgt.cluster
- Initial build.
