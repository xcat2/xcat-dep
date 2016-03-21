%define upstream_name    Net-HTTPS-NB
%define upstream_version 0.14

%{?perl_default_filter}

Name:       perl-%{upstream_name}
Version:    %{upstream_version}
Release:    2

Summary:    Non-blocking HTTPS client
License:    GPL+ or Artistic
Group:      Development/Perl
Url:        http://search.cpan.org/dist/%{upstream_name}
Source0:    http://www.cpan.org/modules/by-module/Net/%{upstream_name}-%{upstream_version}.tar.gz
Patch:      Net-HTTPS-NB-0.14.patch

BuildRequires: perl(Exporter)
BuildRequires: perl(ExtUtils::MakeMaker)
BuildRequires: perl(IO::Socket::SSL) >= 0.980.0
BuildRequires: perl(Net::HTTP)
BuildRequires: perl(Net::HTTPS)
BuildArch:  noarch

%description
Same interface as Net::HTTPS but it will never try multiple reads when the
read_response_headers() or read_entity_body() methods are invoked. In
addition allows non-blocking connect.

* If read_response_headers() did not see enough data to complete the
  headers an empty list is returned.

* If read_entity_body() did not see new entity data in its read the value
  -1 is returned.

%prep
%setup -q -n %{upstream_name}-%{upstream_version}

%patch -p1

%build
%__perl Makefile.PL

make

%install
%make_install
find ${RPM_BUILD_ROOT} -type f -name perllocal.pod -exec rm -f {} ';' 
find ${RPM_BUILD_ROOT} -type f -name .packlist -exec rm -f {} ';' 
find ${RPM_BUILD_ROOT} \( -path '*/perllocal.pod' -o -path '*/.packlist' -o -path '*.bs' \) -a -prune -o -type f -printf "/%%P\n" > version-filelist
if [ "$(cat version-filelist)X" = "X" ] ; then
    echo "ERROR: EMPTY FILE LIST"
    exit 1
fi

%files -f version-filelist
%defattr(-,root,root)

%changelog
* Sat Feb 20 2016 umeabot <umeabot> 0.140.0-2.mga6
+ Revision: 971331
- Mageia 6 Mass Rebuild

  + sander85 <sander85>
    - update to 0.14

* Wed Oct 14 2015 sander85 <sander85> 0.140.0-1.mga6
+ Revision: 891476
- update to 0.14

* Sun Oct 19 2014 umeabot <umeabot> 0.130.0-5.mga5
+ Revision: 788555
- Rebuild to potentially add missing dependencies

* Wed Oct 15 2014 umeabot <umeabot> 0.130.0-4.mga5
+ Revision: 749262
- Second Mageia 5 Mass Rebuild

* Tue Sep 16 2014 umeabot <umeabot> 0.130.0-3.mga5
+ Revision: 685663
- Mageia 5 Mass Rebuild

* Sat Oct 19 2013 umeabot <umeabot> 0.130.0-2.mga4
+ Revision: 527941
- Mageia 4 Mass Rebuild

* Fri Jun 14 2013 kharec <kharec> 0.130.0-1.mga4
+ Revision: 442978
- update to 0.13

* Fri Feb 22 2013 kharec <kharec> 0.120.0-1.mga3
+ Revision: 399852
- imported package perl-Net-HTTPS-NB


* Fri Feb 22 2013 cpan2dist 0.12-1mga
- initial mageia release, generated with cpan2dist
