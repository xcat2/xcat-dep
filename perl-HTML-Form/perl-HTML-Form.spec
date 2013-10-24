#
# spec file for package perl-HTML-Form
#
# Copyright (c) 2013 SUSE LINUX Products GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#


Name:           perl-HTML-Form
Version:        6.03
Release:        5.1
%define cpan_name HTML-Form
Summary:        Class that represents an HTML form element
License:        Artistic-1.0 or GPL-1.0+
Group:          Development/Libraries/Perl
Url:            http://search.cpan.org/dist/HTML-Form/
Source:         http://www.cpan.org/authors/id/G/GA/GAAS/%{cpan_name}-%{version}.tar.gz
BuildArch:      noarch
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
BuildRequires:  perl
BuildRequires:  perl-macros
BuildRequires:  perl(HTML::TokeParser)
BuildRequires:  perl(HTTP::Request) >= 6
BuildRequires:  perl(HTTP::Request::Common) >= 6.03
BuildRequires:  perl(URI) >= 1.10
#BuildRequires: perl(HTML::Form)
#BuildRequires: perl(HTTP::Response)
Requires:       perl(HTML::TokeParser)
Requires:       perl(HTTP::Request) >= 6
Requires:       perl(HTTP::Request::Common) >= 6.03
Requires:       perl(URI) >= 1.10
%{perl_requires}

%description
Objects of the 'HTML::Form' class represents a single HTML '<form> ...
</form>' instance. A form consists of a sequence of inputs that usually
have names, and which can take on various values. The state of a form can
be tweaked and it can then be asked to provide 'HTTP::Request' objects that
can be passed to the request() method of 'LWP::UserAgent'.

%prep
%setup -q -n %{cpan_name}-%{version}

%build
%{__perl} Makefile.PL INSTALLDIRS=vendor
%{__make} %{?_smp_mflags}

%check
%{__make} test

%install
%perl_make_install
%perl_process_packlist
%perl_gen_filelist

%files -f %{name}.files
%defattr(-,root,root,755)
%doc Changes README

%changelog
* Wed Jul 24 2013 coolo@suse.com
- updated to 6.03
  Support the new HTML5 input types without warning
  Fix test failure when HTTP-Message 6.03 (or better) was installed [RT#75155]
* Mon Feb 20 2012 coolo@suse.com
- updated to 6.01
  Don't pick up label text from textarea [RT#72925]
  Restore perl-5.8.1 compatiblity.
* Mon Mar 14 2011 vcizek@novell.com
- initial package 6.00
  * created by cpanspec 1.78.03
