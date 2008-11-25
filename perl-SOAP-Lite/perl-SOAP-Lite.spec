%define _unpackaged_files_terminate_build 0
Summary: perl-SOAP-Lite 
Name: perl-SOAP-Lite 
Version: 0.710.08 
Release: 1
License: Perl/Artistic License?
Group: Applications/CPAN
Source: SOAP-Lite-0.710.08.tar.gz 
BuildRoot: /tmp/SOAP-Lite
BuildArch: noarch
Packager: unknown@localhost 
AutoReq: no
AutoReqProv: no
Requires: perl(Scalar::Util) perl(IO::Socket::SSL) perl(URI) perl(IO::File) perl(Net::FTP) perl(Compress::Zlib) perl(version) perl(Test::More) perl(LWP::UserAgent) perl(MIME::Base64) perl(HTTP::Daemon) perl(XML::Parser) >= 2.23
Provides: perl(SOAP::Packager) perl(My::PersistentIterator) perl(My::Parameters) perl(IO::SessionSet) perl(My::Chat) perl(XMLRPC::Test) perl(My::Examples) perl(SOAP::Lite::Deserializer::XMLSchema2001) perl(SOAP::Apache) perl(SOAP::Lite::Deserializer::XMLSchemaSOAP1_2) perl(SOAP::Lite) perl(Apache::XMLRPC::Lite) perl(IO::SessionData) perl(SOAP::Lite::Deserializer::XMLSchema1999) perl(Apache::SOAP) perl(SOAP::Test) perl(XML::Parser::Lite) perl(SOAP::Constants) perl(SOAP::Lite::Packager) perl(SOAP::Transport::LOOPBACK) perl(SOAP::Lite::Deserializer::XMLSchemaSOAP1_1) perl(My::SessionIterator) perl(SOAP::Transport::HTTP::Daemon::ForkAfterProcessing) perl(SOAP::Lite::Utils) perl(XMLRPC::Lite) perl(SOAP::Transport::HTTP::Daemon::ForkOnAccept) perl(My::PingPong)

%description
Distribution id = M/MK/MKUTTER/SOAP-Lite-0.710.08.tar.gz
    CPAN_USERID  MKUTTER (Martin Kutter <kutterma@users.sourceforge.net>)
    CONTAINSMODS SOAP::Packager My::PersistentIterator My::Parameters IO::SessionSet My::Chat XMLRPC::Test My::Examples SOAP::Lite::Deserializer::XMLSchema2001 SOAP::Apache SOAP::Lite::Deserializer::XMLSchemaSOAP1_2 SOAP::Lite Apache::XMLRPC::Lite IO::SessionData SOAP::Lite::Deserializer::XMLSchema1999 Apache::SOAP SOAP::Test XML::Parser::Lite SOAP::Constants SOAP::Lite::Packager SOAP::Transport::LOOPBACK SOAP::Lite::Deserializer::XMLSchemaSOAP1_1 My::SessionIterator SOAP::Transport::HTTP::Daemon::ForkAfterProcessing SOAP::Lite::Utils XMLRPC::Lite SOAP::Transport::HTTP::Daemon::ForkOnAccept My::PingPong
    MD5_STATUS   OK
    archived     tar
    unwrapped    YES



%prep
%setup -q -n SOAP-Lite-0.710.08

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
  -type f -printf "/%%P\n" > SOAP-Lite-filelist

if [ "$(cat SOAP-Lite-filelist)X" = "X" ] ; then
    echo "ERROR: EMPTY FILE LIST"
    exit 1
fi

%files -f SOAP-Lite-filelist
%defattr(-,root,root)

%changelog
* Thu Nov 20 2008 unknown@localhost 
- Initial build
