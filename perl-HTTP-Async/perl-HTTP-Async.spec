%define upstream_name    HTTP-Async
%define upstream_version 0.30

%{?perl_default_filter}

Name:       perl-%{upstream_name}
Version:    %{upstream_version}
Release:    2

Summary:    Politely process multiple HTTP requests
License:    GPL+ or Artistic
Group:      Development/Perl
Url:        http://search.cpan.org/dist/%{upstream_name}
Source0:    http://www.cpan.org/modules/by-module/HTTP/%{upstream_name}-%{upstream_version}.tar.gz
Patch:      HTTP-Async-0.30.patch
BuildArch:  noarch

%description
Although using the conventional 'LWP::UserAgent' is fast and easy it does
have some drawbacks - the code execution blocks until the request has been
completed and it is only possible to process one request at a time.
'HTTP::Async' attempts to address these limitations.

It gives you a 'Async' object that you can add requests to, and then get
the requests off as they finish. The actual sending and receiving of the
requests is abstracted. As soon as you add a request it is transmitted, if
there are too many requests in progress at the moment they are queued.
There is no concept of starting or stopping - it runs continuously.

Whilst it is waiting to receive data it returns control to the code that
called it meaning that you can carry out processing whilst fetching data
from the network. All without forking or threading - it is actually done
using 'select' lists.

%prep
%setup -q -n %{upstream_name}-%{upstream_version}

%patch -p1

%build
CFLAGS="$RPM_OPT_FLAGS $CFLAGS" %__perl Makefile.PL

make

#%check
#%make test

%install
make PREFIX=%{_prefix} \
     DESTDIR=%{buildroot} \
     INSTALLDIRS=site \
     install
#%make_install

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
* Sat Feb 20 2016 umeabot <umeabot> 0.300.0-2.mga6
+ Revision: 971324
- Mageia 6 Mass Rebuild

* Wed Oct 14 2015 sander85 <sander85> 0.300.0-1.mga6
+ Revision: 891385
- update to 0.30

* Thu Jun 25 2015 shlomif <shlomif> 0.290.0-1.mga6
+ Revision: 843206
- update to 0.29

* Sat Oct 18 2014 umeabot <umeabot> 0.260.0-4.mga5
+ Revision: 788383
- Rebuild to potentially add missing dependencies

* Wed Oct 15 2014 umeabot <umeabot> 0.260.0-3.mga5
+ Revision: 742741
- Second Mageia 5 Mass Rebuild

* Tue Sep 16 2014 umeabot <umeabot> 0.260.0-2.mga5
+ Revision: 684992
- Mageia 5 Mass Rebuild

* Sat Jun 07 2014 sander85 <sander85> 0.260.0-1.mga5
+ Revision: 634333
- update to 0.26

* Tue Mar 25 2014 jquelin <jquelin> 0.250.0-1.mga5
+ Revision: 608358
- update to 0.25

* Tue Feb 04 2014 shlomif <shlomif> 0.230.0-1.mga5
+ Revision: 581190
- New version 0.23

* Sat Oct 19 2013 umeabot <umeabot> 0.220.0-2.mga4
+ Revision: 534493
- Mageia 4 Mass Rebuild

* Thu Sep 12 2013 sander85 <sander85> 0.220.0-1.mga4
+ Revision: 478134
- update to 0.22

* Thu Aug 29 2013 sander85 <sander85> 0.210.0-1.mga4
+ Revision: 473095
- update to 0.21

* Sun Jul 21 2013 sander85 <sander85> 0.200.0-1.mga4
+ Revision: 456932
- update to 0.20

* Sun Jun 02 2013 shlomif <shlomif> 0.180.0-1.mga4
+ Revision: 434433
- New version 0.18

* Sun Jan 13 2013 umeabot <umeabot> 0.110.0-2.mga3
+ Revision: 368255
- Mass Rebuild - https://wiki.mageia.org/en/Feature:Mageia3MassRebuild

* Wed Nov 14 2012 jquelin <jquelin> 0.110.0-1.mga3
+ Revision: 317678
- update to 0.11

* Mon Jun 04 2012 kharec <kharec> 0.100.0-1.mga3
+ Revision: 253983
- update to 0.10

* Fri Dec 16 2011 kharec <kharec> 0.90.0-1.mga2
+ Revision: 182446
- imported package perl-HTTP-Async


* Fri Dec 16 2011 cpan2dist 0.09-1mga
- initial mageia release, generated with cpan2dist
